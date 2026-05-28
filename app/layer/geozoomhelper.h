#pragma once

#include <QObject>
#include <QString>

class InputMapSettings;
class ActiveProject;

class GeoZoomHelper : public QObject
{
    Q_OBJECT

public:
    explicit GeoZoomHelper( ActiveProject *activeProject, QObject *parent = nullptr );
    ~GeoZoomHelper() override = default;

    /**
   * Lee un archivo JSON local con la estructura:
   *   [{ "Proyecto":"...", "BD":"...", "Capa":"...", "CVEGEO":"..." }]
   *
   * Extrae los campos, y hace zoom a la entidad dentro del GeoPackage.
   * La ruta al .gpkg se resuelve relativa al directorio del proyecto activo.
   *
   * \param jsonPath      Ruta absoluta al archivo .json de configuración
   * \param projectDir    Directorio del proyecto activo (para resolver la ruta al .gpkg)
   * \param mapSettings   Puntero al InputMapSettings activo del mapa
   * \param errorMsg      [out] Mensaje de error legible si retorna false
   * \return true si el zoom se realizó con éxito
   */
    Q_INVOKABLE bool zoomFromJsonFile( const QString &jsonPath,
                                      const QString &projectDir,
                                      InputMapSettings *mapSettings,
                                      QString &errorMsg );

    /**
   * Sobrecarga invocable desde QML (sin parámetro de salida errorMsg).
   * El error queda disponible en la propiedad lastError.
   */
    Q_INVOKABLE bool zoomFromJsonFile( const QString &jsonPath,
                                      const QString &projectDir,
                                      InputMapSettings *mapSettings );

    /**
   * Lee la configuración CVEGEO apropiada para el estado actual de la app.
   * Si no hay proyecto cargado, intenta leer "Proyecto" desde el JSON global,
   * carga el proyecto y después realiza el zoom.
   */
    Q_INVOKABLE bool zoomFromConfiguredJson( InputMapSettings *mapSettings );

    /**
   * Usa un archivo JSON seleccionado por el usuario.
   * El directorio padre del JSON se usa como projectDir, y si el campo
   * "Proyecto" está presente en el JSON, el proyecto se carga desde ahí.
   * Así el JSON y el .gpkg pueden estar en la misma carpeta sin configuración
   * adicional.
   */
    Q_INVOKABLE bool zoomFromPickedJson( const QString &jsonPath,
                                        InputMapSettings *mapSettings );

    /**
   * Lee el JSON e intenta resolver la ruta del proyecto (.qgz) indicada en
   * el campo "Proyecto".  Devuelve la ruta absoluta resuelta, o una cadena
   * vacía si el JSON no existe, no es válido o no contiene "Proyecto".
   * Útil para que QML compruebe el estado del archivo antes del arranque
   * automático sin desencadenar el zoom.
   */
    Q_INVOKABLE QString parseProjectPathFromJson( const QString &jsonPath );

    /**
   * Búsqueda y zoom directo, sin pasar por JSON.
   */
    Q_INVOKABLE bool zoomToCvegeo( const QString &gpkgPath,
                                  const QString &layerName,
                                  const QString &cvegeoValue,
                                  InputMapSettings *mapSettings,
                                  const QString &fieldName = QStringLiteral( "CVEGEO" ) );

    //! Último mensaje de error (para inspeccionarlo desde QML)
    Q_PROPERTY( QString lastError READ lastError NOTIFY lastErrorChanged )
    QString lastError() const { return mLastError; }

signals:
    void lastErrorChanged();

private:
    void setLastError( const QString &msg );
    ActiveProject *mActiveProject = nullptr;
    QString mLastError;
};
