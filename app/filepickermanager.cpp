/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "filepickermanager.h"
#include "coreutils.h"

// ── Android ──────────────────────────────────────────────────────────────────
#ifdef ANDROID
#include <QtCore/private/qandroidextras_p.h>
#include <QJniObject>
#include <QStandardPaths>
#include <QDir>
#include <QGuiApplication>
#include <QCoreApplication>

// ── Windows ──────────────────────────────────────────────────────────────────
#elif defined( Q_OS_WIN )
#include <QFileDialog>
#include <QUrl>

// ── Other Desktop (Linux / macOS) ────────────────────────────────────────────
#else
#include <QFileDialog>
#include <QUrl>
#endif

FilePickerManager::FilePickerManager( QObject *parent )
    : QObject( parent )
{
#ifdef ANDROID
    // Poll for files that arrived via ACTION_VIEW (user tapped a .qgz in an
    // external file manager) every time the app comes to the foreground.
    QObject::connect(
        qobject_cast<QGuiApplication *>( QCoreApplication::instance() ),
        &QGuiApplication::applicationStateChanged,
        this,
        [ this ]( Qt::ApplicationState state )
        {
            if ( state == Qt::ApplicationActive )
            {
                checkPendingExternalProject();
            }
        } );
#endif
}

void FilePickerManager::openFilePicker()
{
#ifdef ANDROID
    // ── Android: launch SAF ACTION_OPEN_DOCUMENT ─────────────────────────────
    //
    // We use ACTION_OPEN_DOCUMENT (not ACTION_GET_CONTENT) so that the system
    // grants us a persistent, re-openable URI with proper Scoped Storage
    // semantics.  No MANAGE_EXTERNAL_STORAGE permission is needed.
    //
    // MIME type: "application/zip"  (.qgz is a renamed zip archive).
    // We also add "application/octet-stream" as a fallback via EXTRA_MIME_TYPES
    // so that file managers that mis-identify the type still show the file.

    const QJniObject ACTION_OPEN_DOCUMENT =
        QJniObject::getStaticObjectField(
            "android/content/Intent",
            "ACTION_OPEN_DOCUMENT",
            "Ljava/lang/String;" );

    QJniObject intent(
        "android/content/Intent",
        "(Ljava/lang/String;)V",
        ACTION_OPEN_DOCUMENT.object<jstring>() );

    if ( !ACTION_OPEN_DOCUMENT.isValid() || !intent.isValid() )
    {
        emit notifyError( tr( "Cannot create file picker Intent." ) );
        return;
    }

    // Primary MIME type (required by setType)
    intent = intent.callObjectMethod(
        "setType",
        "(Ljava/lang/String;)Landroid/content/Intent;",
        QJniObject::fromString( "application/zip" ).object<jstring>() );

    // Allow additional MIME types so that more file managers expose .qgz files
    QJniEnvironment env;
    jobjectArray mimeArray = env->NewObjectArray(
        3,
        env->FindClass( "java/lang/String" ),
        nullptr );
    env->SetObjectArrayElement( mimeArray, 0, QJniObject::fromString( "application/zip" ).object<jstring>() );
    env->SetObjectArrayElement( mimeArray, 1, QJniObject::fromString( "application/octet-stream" ).object<jstring>() );
    env->SetObjectArrayElement( mimeArray, 2, QJniObject::fromString( "*/*" ).object<jstring>() );

    const QJniObject EXTRA_MIME_TYPES =
        QJniObject::getStaticObjectField(
            "android/content/Intent",
            "EXTRA_MIME_TYPES",
            "Ljava/lang/String;" );

    intent.callObjectMethod(
        "putExtra",
        "(Ljava/lang/String;[Ljava/lang/String;)Landroid/content/Intent;",
        EXTRA_MIME_TYPES.object<jstring>(),
        mimeArray );

    env->DeleteLocalRef( mimeArray );

    // Only local files (avoids Drive/cloud URIs that can't be accessed offline)
    intent = intent.callObjectMethod(
        "putExtra",
        "(Ljava/lang/String;Z)Landroid/content/Intent;",
        QJniObject::fromString( "EXTRA_LOCAL_ONLY" ).object<jstring>(),
        true );

    QtAndroidPrivate::startActivity( intent.object<jobject>(), QGZ_PICKER_CODE, this );

// ── Desktop (Windows, Linux, macOS) ──────────────────────────────────────────
#else
    const QString path = QFileDialog::getOpenFileName(
        nullptr,
        tr( "Select QGIS Project" ),
        QString(),               // start dir – OS remembers last one
        tr( "QGIS Projects (*.qgz);;All files (*)" ) );

    if ( path.isEmpty() )
    {
        emit filePickerCancelled();
    }
    else
    {
        // QFileDialog already returns an absolute native path – pass it directly.
        emit fileSelected( path );
    }
#endif
}

// ── Android callback ─────────────────────────────────────────────────────────
#ifdef ANDROID
void FilePickerManager::handleActivityResult( const int receiverRequestCode,
                                             const int resultCode,
                                             const QJniObject &data )
{
    if ( receiverRequestCode != QGZ_PICKER_CODE )
        return;

    const jint RESULT_OK =
        QJniObject::getStaticField<jint>( "android/app/Activity", "RESULT_OK" );

    if ( resultCode != RESULT_OK )
    {
        // User pressed Back / cancelled
        emit filePickerCancelled();
        return;
    }

    if ( !data.isValid() )
    {
        emit notifyError( tr( "File picker returned no data." ) );
        return;
    }

    // Retrieve the content:// URI from the Intent
    const QJniObject uri =
        data.callObjectMethod( "getData", "()Landroid/net/Uri;" );

    if ( !uri.isValid() )
    {
        emit notifyError( tr( "Invalid URI returned by file picker." ) );
        return;
    }

    // Delegate the content:// → local-file copy to the Java Activity.
    // importQgzFile() creates a copy inside the app's cache dir and returns
    // the absolute path string.  QGIS / GDAL can open that path directly.
    const QJniObject activity =
        QJniObject( QNativeInterface::QAndroidApplication::context() );

    const QString localPath =
        activity.callObjectMethod(
                    "importQgzFile",
                    "(Landroid/net/Uri;Ljava/lang/String;)Ljava/lang/String;",
                    uri.object(),
                    QJniObject::fromString(
                        QStandardPaths::writableLocation( QStandardPaths::CacheLocation ) )
                        .object<jstring>() )
            .toString();

    if ( localPath.isEmpty() )
    {
        const QString msg = tr( "Could not copy the selected .qgz file to the app cache." );
        CoreUtils::log( "FilePickerManager", msg );
        emit notifyError( msg );
        return;
    }

    // Strip the "file://" prefix if the Java side returned a file URI
    QString posixPath = localPath;
    if ( posixPath.startsWith( "file://" ) )
        posixPath = QUrl( posixPath ).toLocalFile();

    CoreUtils::log( "FilePickerManager", "QGZ imported to: " + posixPath );
    emit fileSelected( posixPath );
}
#endif

// ── Android: poll for ACTION_VIEW pending path ────────────────────────────────
#ifdef ANDROID
void FilePickerManager::checkPendingExternalProject()
{
    // Ask the Java Activity whether a .qgz was opened externally.
    // getAndConsumeExternalProjectPath() returns "" if nothing is pending.
    const QString path =
        QJniObject::callStaticObjectMethod<jstring>(
            "uk/co/lutraconsulting/MMActivity",
            "getAndConsumeExternalProjectPath",
            "()Ljava/lang/String;" )
        .toString();

    if ( path.isEmpty() )
        return;

    CoreUtils::log( "FilePickerManager",
                    "External project received via ACTION_VIEW: " + path );
    emit externalProjectOpened( path );
}
#endif