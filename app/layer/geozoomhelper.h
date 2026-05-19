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
