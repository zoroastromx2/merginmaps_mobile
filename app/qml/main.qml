import QtQuick
import QtCore
import QtQuick.Controls
import QtMultimedia
import QtQml.Models
import QtPositioning // para GPS
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

import mm 1.0 as MM
import MMInput

import "./map" // Componentes relacionados con el mapa (controlador, herramientas).
import "./dialogs" // Diálogos personalizados (errores, advertencias).
import "./layers"// Paneles para gestionar las capas del mapa
import "./components" // Botones, listas, etc., reutilizables.
import "./project"// Gestión de proyectos (carga, sincronización).
import "./settings" // Pantalla de configuración.
import "./gps" // Paneles para datos y seguimiento GPS.
import "./form" // La lógica para mostrar y editar los formularios de atributos de las entidades.

import "./tables" // Diálogos para la manipulación de tablas

/*
(ApplicationWindow):
Es el contenedor principal de toda la aplicación.
Aquí se define el título de la app ("MDM Móvil 2026") y se configuran sus dimensiones, visibilidad y comportamiento
dependiendo de si el sistema operativo es iOS, Android o Windows
*/

ApplicationWindow {
  id: window

  visible: true
  x:  __appwindowx
  y:  __appwindowy
  width:  __appwindowwidth
  height: __appwindowheight
  visibility: __appwindowvisibility

  // ... resto del archivo sin cambios ...

  MMToolbar {
    id: mapToolbar

    anchors.bottom: parent.bottom
    visible: map.state === "view"

    model: ObjectModel {

      // ── Botón: Zoom a CVEGEO desde JSON ─────────────────────────────────────
      MMToolbarButton {
        id: zoomCvegeoButton
        text: qsTr("Ir a CVEGEO")
        iconSource: __style.searchIcon

        onClicked: {
          zoomCvegeoButton.enabled = false
          __filePickerManager.openFilePicker()
        }
      }

      MMToolbarButton {
        id: addTable
        text: qsTr("Abrir Archivo") // Cambié el texto // traducir
        iconSource: __style.homeIcon
        onClicked: {
        __filePickerManager.openFilePicker()
        }
      }

      // ... resto del toolbar sin cambios ...
    }
  }

  // ... resto del archivo sin cambios ...

  Connections {
    target: __filePickerManager

    function registerAndLoad( filePath, errorMsg ) {
      if ( filePath === "" ) return
      var lastSlash = filePath.lastIndexOf( '/' )
      if ( lastSlash < 0 ) {
        __notificationModel.addError( errorMsg + filePath )
        return
      }
      var name = filePath.substring( lastSlash + 1 ).replace( /\.[^/.]+$/, "" )
      __localProjectsManager.addLocalProjectByFilePath( filePath, name )
      if ( __activeProject.load( filePath ) ) {
        stateManager.state = "map"
      } else {
        __notificationModel.addError( errorMsg + filePath )
      }
    }

    function onFileSelected( filePath ) {
      registerAndLoad( filePath, qsTr( "No se pudo abrir el proyecto: " ) )
    }

    function onExternalProjectOpened( filePath ) {
      registerAndLoad( filePath, qsTr( "Failed to open external project: " ) )
    }
  }
}
