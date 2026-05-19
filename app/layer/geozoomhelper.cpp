#include "geozoomhelper.h"
#include "map/inputmapsettings.h"

// Qt
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

// QGIS
#include <qgsvectorlayer.h>
#include <qgsfeaturerequest.h>
#include <qgsfeature.h>
#include <qgsgeometry.h>
#include <qgsrectangle.h>
#include <qgscoordinatetransform.h>
#include <qgsproject.h>
#include <qgsmessagelog.h>

GeoZoomHelper::GeoZoomHelper( QObject *parent )
    : QObject( parent )
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
    // 1. Leer el archivo --------------------------------------------------------
    QFile file( jsonPath );
    if ( !file.open( QIODevice::ReadOnly | QIODevice::Text ) )
    {
        errorMsg = QStringLiteral( "No se pudo abrir el archivo JSON:\n%1" ).arg( jsonPath );
        return false;
    }

    const QByteArray raw = file.readAll();
    file.close();

    // 2. Parsear JSON -----------------------------------------------------------
    QJsonParseError parseErr;
    const QJsonDocument doc = QJsonDocument::fromJson( raw, &parseErr );

    if ( parseErr.error != QJsonParseError::NoError )
    {
        errorMsg = QStringLiteral( "JSON inválido: %1" ).arg( parseErr.errorString() );
        return false;
    }

    if ( !doc.isArray() || doc.array().isEmpty() )
    {
        errorMsg = QStringLiteral( "El JSON debe ser un array no vacío." );
        return false;
    }

    // 3. Extraer campos de la primera entrada -----------------------------------
    const QJsonObject entry = doc.array().first().toObject();

    const QString cvegeo  = entry.value( QStringLiteral( "CVEGEO" ) ).toString().trimmed();
    const QString bdFile  = entry.value( QStringLiteral( "BD" ) ).toString().trimmed();
    const QString capa    = entry.value( QStringLiteral( "Capa" ) ).toString().trimmed();

    if ( cvegeo.isEmpty() || bdFile.isEmpty() || capa.isEmpty() )
    {
        errorMsg = QStringLiteral( "El JSON debe contener los campos: CVEGEO, BD y Capa." );
        return false;
    }

    // 4. Construir ruta al GeoPackage ------------------------------------------
    QString dir = projectDir;
    if ( !dir.endsWith( '/' ) ) dir += '/';
    const QString gpkgPath = dir + bdFile;

    // 5. Delegar en zoomToCvegeo -----------------------------------------------
    if ( !zoomToCvegeo( gpkgPath, capa, cvegeo, mapSettings ) )
    {
        errorMsg = mLastError.isEmpty()
        ? QStringLiteral( "No se encontró CVEGEO '%1' en la capa '%2'." )
                .arg( cvegeo, capa )
        : mLastError;
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