/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import mm 1.0 as MM

import "../components"
import "../inputs"

/*
 * MMCreateDatabasePage — SQLite database creation page.
 * Follows the MMPage pattern: view only, no business logic.
 * All communication with the backend is done via signals and properties.
 */

MMPage {
  id: root

  // ── Propiedades de entrada ────────────────────────────────────────────
  property string errorMessage: ""    // el Controller escribe aquí si falla
  property bool   databaseReady: false  // true cuando la BD fue creada con éxito
  property string createdDbPath: ""   // ruta completa del .db recién creado

  // ── Señales de salida ─────────────────────────────────────────────────
  signal createDatabaseRequested(string name, string path)
  signal exportDatabaseRequested(string destinationPath)

  // ── Diálogo: selección de carpeta (campo Ubicación) ───────────────────
  FolderDialog {
    id: folderDialog
    title: qsTr("Seleccionar carpeta de destino")
    onAccepted: {
      var folderPath = folderDialog.selectedFolder.toString()
      if (folderPath.startsWith("file:///")) {
        folderPath = folderPath.substring(8)
      } else if (folderPath.startsWith("file://")) {
        folderPath = folderPath.substring(7)
      }
      dbPathInput.text = folderPath
    }
  }

  // ── Diálogo: guardar copia de la BD ───────────────────────────────────
  FileDialog {
    id: exportFileDialog
    title: qsTr("Guardar copia de la base de datos")
    fileMode: FileDialog.SaveFile
    nameFilters: ["SQLite (*.db *.sqlite)", qsTr("Todos los archivos (*)")]
    defaultSuffix: "db"
    onAccepted: {
      root.exportDatabaseRequested(exportFileDialog.selectedFile.toString())
    }
  }

  // ── Cabecera ──────────────────────────────────────────────────────────
  pageHeader {
    title: qsTr("Crear Base de Datos")
    baseHeaderHeight: __style.row80
    backVisible: true
  }

  // ── Contenido principal ───────────────────────────────────────────────
  pageContent: MMScrollView {
    width: parent.width
    height: parent.height

    ColumnLayout {
      width: parent.width
      spacing: __style.spacing20

      // Campo: nombre de la BD
      MMTextInput {
        id: dbNameInput
        Layout.fillWidth: true
        title: qsTr("Nombre de la Base de Datos")
        placeholderText: qsTr("Ej: miproyecto")
        enabled: !root.databaseReady
      }

      // Campo: ubicación + botón Examinar
      ColumnLayout {
        Layout.fillWidth: true
        spacing: __style.spacing8

        MMTextInput {
          id: dbPathInput
          Layout.fillWidth: true
          title: qsTr("Ubicación (dejar vacío para ruta predeterminada)")
          placeholderText: qsTr("Ej: E:/MisDocumentos/")
          enabled: !root.databaseReady
        }

        MMButton {
          text: qsTr("Examinar…")
          size: MMButton.Sizes.Small
          type: MMButton.Types.Secondary
          enabled: !root.databaseReady
          onClicked: folderDialog.open()
        }
      }

      // Notificación de error
      MMNotificationBox {
        Layout.fillWidth: true
        visible: root.errorMessage !== ""
        type: MMNotificationBox.Types.Error
        title: qsTr("Error")
        description: root.errorMessage
      }

      // Notificación de éxito + botón Exportar (visible tras creación exitosa)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: __style.spacing12
        visible: root.databaseReady

        MMNotificationBox {
          Layout.fillWidth: true
          type: MMNotificationBox.Types.Success
          title: qsTr("¡Base de datos creada!")
          description: root.createdDbPath
        }

        MMButton {
          text: qsTr("Exportar BD…")
          Layout.fillWidth: true
          enabled: root.createdDbPath !== ""
          onClicked: exportFileDialog.open()
        }
      }

      Item { implicitHeight: __style.spacing20 }

      // Botones de acción
      RowLayout {
        Layout.fillWidth: true
        spacing: __style.spacing12

        MMButton {
          text: qsTr("Crear")
          Layout.fillWidth: true
          visible: !root.databaseReady
          onClicked: {
            root.createDatabaseRequested(
              dbNameInput.text.trim(),
              dbPathInput.text.trim()
            )
          }
        }

        MMButton {
          text: root.databaseReady ? qsTr("Cerrar") : qsTr("Cancelar")
          type: MMButton.Types.Secondary
          Layout.fillWidth: true
          onClicked: root.backClicked()
        }
      }
    }
  }

  Component.onCompleted: {
    console.log("MMCreateDatabasePage cargado")
  }
}