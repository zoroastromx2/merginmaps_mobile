/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifndef FILEPICKERMANAGER_H
#define FILEPICKERMANAGER_H

#ifdef ANDROID
#include <QtCore/private/qandroidextras_p.h>
#include <QJniObject>
#endif

#include <QObject>
#include <QUrl>

/**
 * \brief FilePickerManager
 *
 * Exposes a cross-platform file picker to QML.
 *
 * - Windows / Desktop : uses QFileDialog synchronously.
 * - Android           : launches ACTION_OPEN_DOCUMENT via the Storage Access
 *                       Framework (Scoped Storage). On result, the content://
 *                       URI is copied to the app's cache directory and the
 *                       resulting POSIX path is emitted through fileSelected().
 *
 *                       Also polls for files opened via ACTION_VIEW (i.e. the
 *                       user tapped a .qgz in an external file manager).  When
 *                       such a file is detected, externalProjectOpened() is
 *                       emitted with the same POSIX path convention.
 *
 * Register in main.cpp as a singleton:
 *   qmlRegisterSingletonInstance("mm", 1, 0, "FilePickerManager",
 *                                &filePickerManager);
 */
class FilePickerManager : public QObject
#ifdef ANDROID
    , QAndroidActivityResultReceiver
#endif
{
    Q_OBJECT

public:
    explicit FilePickerManager( QObject *parent = nullptr );

    /// Request code used when starting the Android picker Activity
#ifdef ANDROID
    static constexpr int QGZ_PICKER_CODE = 110;
#endif

    /**
     * Opens the OS file picker filtered to *.qgz / zip files.
     *
     * On Desktop the result is synchronous and fileSelected() is emitted
     * directly from this call.  On Android the result arrives asynchronously
     * via handleActivityResult().
     */
    Q_INVOKABLE void openFilePicker();

#ifdef ANDROID
    void handleActivityResult( int receiverRequestCode,
                              int resultCode,
                              const QJniObject &data ) override;

    /**
     * Queries the Java Activity for a .qgz path that was received via
     * ACTION_VIEW (external file manager tap) and, if one is available,
     * emits externalProjectOpened().
     *
     * Connected to QGuiApplication::applicationStateChanged so it runs
     * whenever the app comes to the foreground.
     */
    void checkPendingExternalProject();
#endif

signals:
    /// Emitted with a valid POSIX path (no "file://" prefix) when a .qgz
    /// file has been successfully selected and – on Android – copied to cache.
    void fileSelected( const QString &filePath );

    /// Emitted when the user cancels the picker or an error occurs.
    void filePickerCancelled();

    /**
     * Emitted when the user opened a .qgz file from an external file manager
     * (ACTION_VIEW intent).  The path is an absolute POSIX path, ready for
     * QgsProject::read().
     */
    void externalProjectOpened( const QString &filePath );

    /// Convenience signals for UI error/info toasts (mirrors AndroidUtils)
    void notifyError( const QString &msg );
    void notifyInfo( const QString &msg );
};

#endif // FILEPICKERMANAGER_H