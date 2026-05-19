#include "geozoomhelper.h"
#include "activeproject.h"
#include "map/inputmapsettings.h"

// Qt
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QStandardPaths>

// QGIS
#include <qgsvectorlayer.h>
#include <qgsfeaturerequest.h>
#include <qgsfeature.h>
#include <qgsgeometry.h>
#include <qgsrectangle.h>
#include <qgscoordinatetransform.h>
#include <qgsproject.h>
#include <qgsmessagelog.h>

namespace
{
struct GeoZoomConfigEntry
{
    QString projectPath;
    QString bdFile;
    QString layerName;
    QString cvegeo;
};

QString projectLocalCvegeoConfigPath( const QString &projectDir )
{
    return QDir( projectDir ).filePath( QStringLiteral( "cvegeo_config.json" ) );
}

QString projectDirectoryFromPath( const QString &projectPath )
{
    return QFileInfo( projectPath ).absolutePath();
}

// Relative project paths from the config are resolved against the directory
// that contains the JSON file. Absolute paths are used as-is.
QString resolveProjectPath( const QString &projectPath, const QString &jsonPath )
{
    QFileInfo projectInfo( projectPath );
    if ( projectInfo.isAbsolute() )
        return projectInfo.filePath();

    return QDir( QFileInfo( jsonPath ).absolutePath() ).filePath( projectPath );
}

bool readFirstConfigEntry( const QString &jsonPath, GeoZoomConfigEntry &entry, QString &errorMsg )
{
    QFile file( jsonPath );
    if ( !file.open( QIODevice::ReadOnly | QIODevice::Text ) )
    {
        errorMsg = QStringLiteral( "No se pudo abrir el archivo JSON:\n%1" ).arg( jsonPath );
        return false;
    }

    const QByteArray raw = file.readAll();
    file.close();

    QJsonParseError parseErr;
    const QJsonDocument doc = QJsonDocument::fromJson( raw, &parseErr );
    if ( parseErr.error != QJsonParseError::NoError )
    {
        errorMsg = QStringLiteral( "JSON inválido: %1" ).arg( parseErr.errorString() );
        return false;
    }

    if ( !doc.isArray() || doc.array().isEmpty() )
    {
        errorMsg = QStringLiteral( "El JSON no contiene entradas." );
        return false;
    }

    const QJsonObject jsonEntry = doc.array().first().toObject();
    entry.projectPath = jsonEntry.value( QStringLiteral( "Proyecto" ) ).toString().trimmed();
    entry.bdFile = jsonEntry.value( QStringLiteral( "BD" ) ).toString().trimmed();
    entry.layerName = jsonEntry.value( QStringLiteral( "Capa" ) ).toString().trimmed();
    entry.cvegeo = jsonEntry.value( QStringLiteral( "CVEGEO" ) ).toString().trimmed();

    if ( entry.cvegeo.isEmpty() || entry.bdFile.isEmpty() || entry.layerName.isEmpty() )
    {
        errorMsg = QStringLiteral( "El JSON debe contener los campos: CVEGEO, BD y Capa." );
        return false;
    }

    return true;
}
} // namespace

GeoZoomHelper::GeoZoomHelper( ActiveProject *activeProject, QObject *parent )
    : QObject( parent )
    , mActiveProject( activeProject )
{
}

void GeoZoomHelper::setLastError( const QString &msg )
{
    if ( mLastError == msg ) return;
    mLastError = msg;
    QgsMessageLog::logMessage( msg, QStringLiteral( "MDM Movil App" ) );
    emit lastErrorChanged();
}

// ── Sobrecarga QML-friendly ───────────────────────────────────────────────────
bool GeoZoomHelper::zoomFromJsonFile( const QString &jsonPath,
                                     const QString &projectDir,
                                     InputMapSettings *mapSettings )
{
    QString err;
    bool ok = zoomFromJsonFile( jsonPath, projectDir, mapSettings, err );
    if ( !ok ) setLastError( err );
    return ok;
}

// ── Implementación principal ──────────────────────────────────────────────────
bool GeoZoomHelper::zoomFromJsonFile( const QString &jsonPath,
                                     const QString &projectDir,
                                     InputMapSettings *mapSettings,
                                     QString &errorMsg )
{
    GeoZoomConfigEntry entry;
    if ( !readFirstConfigEntry( jsonPath, entry, errorMsg ) )
    {
        return false;
    }

    // 4. Construir ruta al GeoPackage ------------------------------------------
    QString dir = projectDir;
    if ( !dir.endsWith( '/' ) ) dir += '/';
    const QString gpkgPath = dir + entry.bdFile;

    // 5. Delegar en zoomToCvegeo -----------------------------------------------
    if ( !zoomToCvegeo( gpkgPath, entry.layerName, entry.cvegeo, mapSettings ) )
    {
        errorMsg = mLastError.isEmpty()
        ? QStringLiteral( "No se encontró CVEGEO '%1' en la capa '%2'." )
                .arg( entry.cvegeo, entry.layerName )
        : mLastError;
        return false;
    }

    return true;
}

bool GeoZoomHelper::zoomFromConfiguredJson( InputMapSettings *mapSettings )
{
    if ( !mActiveProject )
    {
        setLastError( QStringLiteral( "GeoZoomHelper: activeProject es nulo." ) );
        return false;
    }

    QString jsonPath;
    QString projectDir;
    GeoZoomConfigEntry entry;

    if ( mActiveProject->isProjectLoaded() )
    {
        const QString projectPath = mActiveProject->qgsProject()->fileName();
        projectDir = projectDirectoryFromPath( projectPath );
        jsonPath = projectLocalCvegeoConfigPath( projectDir );

        QString errorMsg;
        if ( !readFirstConfigEntry( jsonPath, entry, errorMsg ) )
        {
            setLastError( errorMsg );
            return false;
        }
    }
    else
    {
        jsonPath = QDir( QStandardPaths::writableLocation( QStandardPaths::AppDataLocation ) )
                       .filePath( QStringLiteral( "cvegeo_config.json" ) );

        QString errorMsg;
        if ( !readFirstConfigEntry( jsonPath, entry, errorMsg ) )
        {
            setLastError( errorMsg );
            return false;
        }

        if ( entry.projectPath.isEmpty() )
        {
            setLastError( QStringLiteral(
                "No hay proyecto activo y el JSON no contiene la clave 'Proyecto'." ) );
            return false;
        }

        const QString projectPath = resolveProjectPath( entry.projectPath, jsonPath );
        if ( !mActiveProject->load( projectPath ) )
        {
            setLastError( QStringLiteral( "No se pudo cargar el proyecto: %1" ).arg( projectPath ) );
            return false;
        }

        projectDir = projectDirectoryFromPath( projectPath );
    }

    const QString gpkgPath = QDir( projectDir ).filePath( entry.bdFile );
    if ( !zoomToCvegeo( gpkgPath, entry.layerName, entry.cvegeo, mapSettings ) )
    {
        setLastError( mLastError.isEmpty()
                          ? QStringLiteral( "No se encontró CVEGEO '%1' en la capa '%2'." )
                                .arg( entry.cvegeo, entry.layerName )
                          : mLastError );
        return false;
    }

    return true;
}

// ── Zoom directo por CVEGEO ───────────────────────────────────────────────────
bool GeoZoomHelper::zoomToCvegeo( const QString &gpkgPath,
                                 const QString &layerName,
                                 const QString &cvegeoValue,
                                 InputMapSettings *mapSettings,
                                 const QString &fieldName )
{
    if ( !mapSettings )
    {
        setLastError( QStringLiteral( "GeoZoomHelper: mapSettings es nulo." ) );
        return false;
    }

    // 1. Abrir capa del GeoPackage ---------------------------------------------
    const QString uri = QStringLiteral( "%1|layername=%2" ).arg( gpkgPath, layerName );
    QgsVectorLayer layer( uri, layerName, QStringLiteral( "ogr" ) );

    if ( !layer.isValid() )
    {
        setLastError( QStringLiteral( "No se pudo abrir la capa '%1' en '%2'." )
                         .arg( layerName, gpkgPath ) );
        return false;
    }

    // 2. Buscar entidad por CVEGEO ---------------------------------------------
    const QString expression =
        QStringLiteral( "\"%1\" = '%2'" ).arg( fieldName, cvegeoValue );

    QgsFeatureRequest request;
    request.setFilterExpression( expression );
    request.setLimit( 1 );

    QgsFeature feature;
    QgsFeatureIterator it = layer.getFeatures( request );

    if ( !it.nextFeature( feature ) || !feature.isValid() )
    {
        setLastError( QStringLiteral( "No se encontró %1='%2'." )
                         .arg( fieldName, cvegeoValue ) );
        return false;
    }

    QgsGeometry geom = feature.geometry();
    if ( geom.isNull() || !geom.constGet() )
    {
        setLastError( QStringLiteral( "La entidad '%1' tiene geometría nula." )
                         .arg( cvegeoValue ) );
        return false;
    }

    // 3. Reproyectar al CRS del mapa -------------------------------------------
    const QgsCoordinateReferenceSystem srcCrs  = layer.crs();
    const QgsCoordinateReferenceSystem destCrs =
        mapSettings->mapSettings().destinationCrs();

    if ( srcCrs.isValid() && destCrs.isValid() && srcCrs != destCrs )
    {
        QgsCoordinateTransform ct( srcCrs, destCrs, QgsProject::instance() );
        try
        {
            geom.transform( ct );
        }
        catch ( const QgsCsException &e )
        {
            setLastError( QStringLiteral( "Error de reproyección: %1" ).arg( e.what() ) );
            return false;
        }
    }

    // 4. Zoom ------------------------------------------------------------------
    QgsRectangle bbox = geom.boundingBox();

    if ( bbox.isEmpty() )   // punto u objeto degenerado: solo centrar
    {
        QgsRectangle currentExtent = mapSettings->mapSettings().visibleExtent();
        const QgsVector offset = currentExtent.center() - bbox.center();
        currentExtent -= offset;
        mapSettings->setExtent( currentExtent );
    }
    else
    {
        constexpr double SCALE_FACTOR = 1.18;
        bbox.scale( SCALE_FACTOR );
        mapSettings->setExtent( bbox );
    }

    setLastError( QString() );   // limpiar error anterior
    QgsMessageLog::logMessage(
        QStringLiteral( "Zoom a %1='%2' OK." ).arg( fieldName, cvegeoValue ),
        QStringLiteral( "MDM Movil App" ) );

    return true;
}
