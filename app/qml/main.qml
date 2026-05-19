/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

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
  /*
    Banderas (flags):
    Configura el comportamiento de la ventana según el sistema operativo.
    En iOS, usa una bandera especial para maximizar la pantalla completa.
    En escritorio (Windows/Linux/macOS), agrega los botones típicos de título, minimizar, maximizar y cerrar.
  */
  flags: {
    if ( Qt.platform.os === "ios" ) {
      return Qt.Window | Qt.MaximizeUsingFullscreenGeometryHint
    }
    else if ( Qt.platform.os !== "ios" && Qt.platform.os !== "android" ) {
      return Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint |
          Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint
    }

    return Qt.Window
  }

  title: "MDM Móvil 2026" // Do not translate

  /*
   Orientación (isPortraitOrientation):
   Detecta si la pantalla está en orientación vertical.
   Al cambiar, llama a recalculateSafeArea(),
   que ajusta los márgenes de la interfaz para evitar áreas no seguras (como la "muesca" o "isla dinámica" en móviles).
  */

  readonly property bool isPortraitOrientation: ( Screen.primaryOrientation === Qt.PortraitOrientation
                                                 || Screen.primaryOrientation === Qt.InvertedPortraitOrientation )

  onIsPortraitOrientationChanged: recalculateSafeArea()

  /*
   Guardar posición: Los manejadores onXChanged, onYChanged, etc.,
   disparan un timer (storeWindowPositionTimer) que guarda la geometría de la ventana en las configuraciones de la app
   después de 1 segundo de inactividad en el redimensionamiento.
  */

  // start window where it was closed last time
  onXChanged: storeWindowPosition()
  onYChanged: storeWindowPosition()
  onWidthChanged: storeWindowPosition()
  onHeightChanged: storeWindowPosition()

/*
 Gestor de Estados (stateManager):
 Es un componente que controla qué pantalla principal está viendo el usuario en un momento dado.
 Se divide en tres estados:
 "map" (la vista del mapa y herramientas de edición),
 "projects" (la lista de proyectos) y
 "misc" (para configuraciones y el panel del GPS).
*/

  Item {
    id: stateManager
    state: "map"

    states: [
      State { name: "map" },
      State { name: "projects" },
      State { name: "misc" }
    ]
// aquí carga el mapa 2026 < ---
    onStateChanged: {
      if ( stateManager.state === "map" ) {
        map.state = "view"
        syncButton.iconRotateAnimationRunning = ( __syncManager.hasPendingSync( __activeProject.projectFullName() ) )
      }
      else if ( stateManager.state === "projects" ) {
        projectController.openPanel()
      }
      if ( stateManager.state !== "map" ) {
        map.state = "inactive";
      }
    }
  }

  function showProjError(message) {
    projDialog.detailedDescription = message
    projDialog.open()
  }

  function identifyFeature( pair ) {
    let hasNullGeometry = pair.feature.geometry.isNull

    if ( hasNullGeometry ) {
      formsStackManager.openForm( pair, "readOnly", "form" )
    }
    else if ( pair.valid ) {
      map.highlightPair( pair )
      formsStackManager.openForm( pair, "readOnly", "preview")
    }
  }

  Component.onCompleted: {
      stateManager.state = "map"
      contentItem.Keys.released.connect( function( event ) {
        if ( event.key === Qt.Key_Back ) {
          event.accepted = true
          window.backButtonPressed()
        }
      } )
    }

  MMMapController {
    id: map
    height: window.height - mapToolbar.height
    width: window.width
    mapExtentOffset: {
      if ( stakeoutPanelLoader.active )
      {
        return stakeoutPanelLoader.item.panelHeight - mapToolbar.height
      }
      else if ( measurePanelLoader.active )
      {
        return measurePanelLoader.item.panelHeight - mapToolbar.height
      }
      else if ( multiSelectPanelLoader.active )
      {
        return multiSelectPanelLoader.item.panelHeight - mapToolbar.height
      }
      else if ( formsStackManager.takenVerticalSpace > 0 )
      {
        return formsStackManager.takenVerticalSpace - mapToolbar.height
      }

      return 0
    }
    onFeatureIdentified: function( pair ) { formsStackManager.openForm( pair, "readOnly", "preview" ); }
    onFeaturesIdentified: function( pairs ) { formsStackManager.closeDrawer(); featurePairSelection.showPairs( pairs ); }
    onNothingIdentified: { formsStackManager.closeDrawer() }
    onRecordingFinished: function( pair ) { formsStackManager.openForm( pair, "add", "form" ); map.highlightPair( pair ) }
    onEditingGeometryStarted: { mapPanelsStackView.hideMapStackIfNeeded(); formsStackManager.geometryEditingStarted() }
    onEditingGeometryFinished: function( pair ) { mapPanelsStackView.showMapStack(); formsStackManager.geometryEditingFinished( pair ) }
    onEditingGeometryCanceled: { mapPanelsStackView.showMapStack(); formsStackManager.geometryEditingFinished( null, false ) }
    onRecordInLayerFeatureStarted: { mapPanelsStackView.hideMapStackIfNeeded(); formsStackManager.geometryEditingStarted() }
    onRecordInLayerFeatureFinished: function( pair ) { mapPanelsStackView.showMapStack(); formsStackManager.recordInLayerFinished( pair ) }
    onRecordInLayerFeatureCanceled: { mapPanelsStackView.showMapStack(); formsStackManager.recordInLayerFinished( null, false ) }
    onSplittingStarted: formsStackManager.hideAll()
    onSplittingFinished: { formsStackManager.closeAll() }
    onSplittingCanceled: { formsStackManager.reopenAll() }
    onAccuracyButtonClicked: { gpsDataDrawerLoader.active = true; gpsDataDrawerLoader.focus = true }
    onStakeoutStarted: function( pair ) { stakeoutPanelLoader.active = true; stakeoutPanelLoader.focus = true; stakeoutPanelLoader.item.targetPair = pair }
    onMeasureStarted: function( pair ) { measurePanelLoader.active = true; measurePanelLoader.focus = true }
    onMultiSelectStarted: { multiSelectPanelLoader.active = true; multiSelectPanelLoader.focus = true }
    onDrawStarted: { sketchesPanelLoader.active = true; sketchesPanelLoader.focus = true }
    onLocalChangesPanelRequested: { stateManager.state = "projects"; projectController.openChangesPanel( __activeProject.projectFullName(), true ) }
    onOpenTrackingPanel: { trackingPanelLoader.active = true }
    onOpenStreamingPanel: { streamingModeDialog.open() }
    Component.onCompleted: {
      __activeProject.mapSettings = map.mapSettings
      __iosUtils.positionKit = PositionKit
      __iosUtils.compass = map.compass
      __variablesManager.compass = map.compass
      __variablesManager.positionKit = PositionKit
    }
  }

  LocationPermission {
    id: locationPermission
    accuracy: LocationPermission.Precise
  }

  MMToolbar {
    id: mapToolbar
    anchors.bottom: parent.bottom
    visible: map.state === "view"

    model: ObjectModel {
      MMToolbarButton {
        id: zoomCvegeoButton
        text: qsTr("Ir a CVEGEO")
        iconSource: __style.searchIcon
        onClicked: {
          __filePickerManager.openFilePicker()
        }
      }

      MMToolbarButton {
        id: addTable
        text: qsTr("Abrir Archivo")
        iconSource: __style.homeIcon
        onClicked: {
          __filePickerManager.openFilePicker()
        }
      }

      MMToolbarButton {
          text: qsTr("Tablas")
          iconSource: __style.addTableIcon
          visible: __activeProject.projectRole !== "reader"
          onClicked: {
              stateManager.state = "misc"
              mapPanelsStackView.push(tablesControllerComponent, {}, StackView.PushTransition)
          }
      }

      MMToolbarButton {
          text: qsTr("Nueva BD")
          iconSource: __style.addIcon
          visible: __activeProject.projectRole !== "reader"
          onClicked: {
              stateManager.state = "misc"
              mapPanelsStackView.push(createDatabasePageComponent, {}, StackView.PushTransition)
          }
      }

      MMToolbarButton {
        text: qsTr("Layers")
        iconSource: __style.layersIcon
        onClicked: {
          stateManager.state = "misc"
          let layerspanel = mapPanelsStackView.push( layersPanelComponent, {}, StackView.PushTransition )
        }
      }

      MMToolbarButton {
        id: syncButton
        text: qsTr("Sync")
        iconSource: __style.syncIcon
        visible: false
        onClicked: { __activeProject.requestSync() }
      }

      MMToolbarButton {
        id: addButton
        text: qsTr("Add")
        iconSource: __style.addIcon
        visible: __activeProject.projectRole !== "reader"
        onClicked: {
          if ( __activeProject.projectHasRecordingLayers() ) {
            stateManager.state = "map"
            map.record()
          }
          else {
            __notificationModel.addInfo( qsTr( "No editable layers found." ) )
          }
        }
      }

      MMToolbarButton {
        text: qsTr("Zoom to project")
        iconSource: __style.zoomToProjectIcon
        onClicked: {
          map.centeredToGPS = false
          __inputUtils.zoomToProject( __activeProject.qgsProject, map.mapSettings )
        }
      }

      MMToolbarButton {
        text: qsTr("Map themes")
        iconSource: __style.mapThemesIcon
        onClicked: {
          mapThemesPanel.visible = true
          stateManager.state = "misc"
        }
      }

      MMToolbarButton {
        id: positionTrackingButton
        text: qsTr("Position tracking")
        iconSource: __style.positionTrackingIcon
        active: map.isTrackingPosition
        visible: __activeProject.positionTrackingSupported
        onClicked: { trackingPanelLoader.active = true }
      }

      MMToolbarButton {
        text: qsTr("Measure")
        iconSource: __style.measurementToolIcon
        onClicked: map.measure()
      }

      MMToolbarButton {
        text: qsTr("Local changes")
        iconSource: __style.localChangesIcon
        visible: false
        onClicked: {
          stateManager.state = "projects"
          projectController.openChangesPanel( __activeProject.projectFullName(), true )
        }
      }

      MMToolbarButton {
        text: qsTr("Settings")
        iconSource: __style.settingsIcon
        onClicked: {
          settingsController.open()
        }
      }
    }
  }

  MMSettingsController {
    id: settingsController
    onOpened: { stateManager.state = "misc" }
    onClosed: { stateManager.state = "map" }
  }

  MMProjectController {
    id: projectController
    height: window.height
    width: window.width
    activeProjectId: __activeProject.localProject.id() ?? ""
    onVisibleChanged: { if ( projectController.visible ) { projectController.forceActiveFocus() } }
    onOpenProjectRequested: function( projectPath ) { __activeProject.load( projectPath ) }
    onClosed: stateManager.state = "map"
  }

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
      var lower = filePath.toLowerCase()
      if ( lower.endsWith( ".json" ) ) {
        var lastSlash = filePath.lastIndexOf( '/' )
        var projectDir = lastSlash >= 0 ? filePath.substring( 0, lastSlash ) : ""
        zoomCvegeoButton.enabled = true
        var ok = __geoZoomHelper.zoomFromJsonFile( filePath, projectDir, map.mapSettings )
        if ( !ok ) {
          __notificationModel.addError( __geoZoomHelper.lastError )
        } else {
          map.centeredToGPS = false
          stateManager.state = "map"
        }
        return
      }

      registerAndLoad( filePath, qsTr( "No se pudo abrir el proyecto: " ) )
      zoomCvegeoButton.enabled = true
    }

    function onExternalProjectOpened( filePath ) {
      registerAndLoad( filePath, qsTr( "Failed to open external project: " ) )
    }

    function onFilePickerCancelled() {
      zoomCvegeoButton.enabled = true
    }
  }

  StackView { id: mapPanelsStackView }
  Component { id: layersPanelComponent }
  Component { id: tablesControllerComponent }
  Component { id: createDatabasePageComponent }
  Component { id: databaseSelectedPageComponent }
  Component { id: gpsDataDrawerComponent }
  Loader { id: gpsDataDrawerLoader }
  MMMapThemeDrawer { id: mapThemesPanel }
  MMStreamingModeDialog { id: streamingModeDialog }
  Loader { id: trackingPanelLoader }
  MMProjectIssuesPage { id: projectIssuesPage }
  Loader { id: stakeoutPanelLoader }
}
