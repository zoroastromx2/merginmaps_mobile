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
import Qt.labs.folderlistmodel

import mm 1.0 as MM

import "../components"
import "../inputs"

/*
 * MMCreateDatabasePage — SQLite database creation page.
 * Follows the MMPage pattern: view only, no business logic.
 * All communication with the backend is done via signals and properties.
 *
 * Features:
 *   • FolderListModel scans the active folder for .db / .sqlite files.
 *   • On load the path field is pre-filled with defaultPath so the scan
 *     starts immediately against the real default directory.
 *   • A ListView below dbNameInput lets the user pick an existing database.
 *   • The primary action button reads "Seleccionar" when the typed name
 *     matches an existing file, and "Crear" otherwise.
 *   • Signal databaseSelected(name, path) is emitted in "Seleccionar" mode.
 *   • Property selectedDbMessage shows a success banner after selection;
 *     the Controller sets it and then pops the page after a short delay.
 */

MMPage {
  id: root

  // ── Propiedades de entrada ────────────────────────────────────────────
  property string errorMessage: ""      // el Controller escribe aquí si falla
  property bool   databaseReady: false  // true cuando la BD fue creada con éxito
  property string createdDbPath: ""     // ruta completa del .db recién creado

  /// Mensaje de confirmación cuando se selecciona una BD existente.
  /// El Controller escribe aquí el nombre y luego cierra la página.
  property string selectedDbMessage: ""

  // Ruta predeterminada usada cuando dbPathInput está vacío.
  // El Controller (o quien instancie la página) puede sobrescribirla.
  property string defaultPath: "./"

  // ── Señales de salida ─────────────────────────────────────────────────
  signal createDatabaseRequested(string name, string path)
  signal exportDatabaseRequested(string destinationPath)
  /// Emitida cuando el usuario elige una BD existente (modo "Seleccionar").
  signal databaseSelected(string name, string path)

  // ── Helpers internos ──────────────────────────────────────────────────

  /// Devuelve la carpeta activa (con barra final garantizada).
  readonly property string _activeFolder: {
    var p = dbPathInput.text.trim()
    if (p === "") p = root.defaultPath
    if (p !== "" && !p.endsWith("/") && !p.endsWith("\\")) p += "/"
    return p
  }

  /// Convierte _activeFolder a una URL que acepta FolderListModel.
  readonly property string _activeFolderUrl: {
    var p = root._activeFolder
    if (p.startsWith("file:")) return p
    // Windows absolute path (C:/…) needs three slashes; Unix already has leading /
    if (p.match(/^[A-Za-z]:\//)) return "file:///" + p
    return "file://" + p
  }

  /// true cuando el nombre escrito (+ .db o .sqlite) ya existe en la carpeta.
  readonly property bool _nameAlreadyExists: {
    var base = dbNameInput.text.trim()
    if (base === "") return false
    for (var i = 0; i < dbListModel.count; i++) {
      var fn = dbListModel.get(i, "fileName")
      if (fn === base + ".db" || fn === base + ".sqlite" || fn === base) return true
    }
    return false
  }

  // ── Modelo de carpeta ─────────────────────────────────────────────────
  FolderListModel {
    id: dbListModel
    folder: root._activeFolderUrl
    nameFilters: ["*.db", "*.sqlite"]
    showDirs: false
    showFiles: true
    showHidden: false
  }

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
    title: qsTr("Crear / Abrir Base de Datos")
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

      // ── Campo: nombre de la BD ────────────────────────────────────────
      MMTextInput {
        id: dbNameInput
        Layout.fillWidth: true
        title: qsTr("Nombre de la Base de Datos")
        placeholderText: qsTr("Ej: miproyecto")
        enabled: !root.databaseReady && root.selectedDbMessage === ""
      }

      // ── Lista de bases de datos existentes ────────────────────────────
      ColumnLayout {
        Layout.fillWidth: true
        spacing: __style.spacing8
        visible: dbListModel.count > 0 && !root.databaseReady && root.selectedDbMessage === ""

        MMText {
          text: qsTr("Bases de datos en esta carpeta:")
          font: __style.p6
          color: __style.nightColor
          Layout.fillWidth: true
        }

        // Contenedor con borde que envuelve la lista
        Rectangle {
          Layout.fillWidth: true
          // Altura máxima: 5 filas de row40; se adapta si hay menos entradas
          implicitHeight: Math.min(dbListModel.count, 5) * __style.row40
                          + __style.margin12 * 2
          color: __style.polarColor
          radius: __style.radius12
          border.color: __style.greyColor
          border.width: __style.width1
          clip: true

          ListView {
            id: dbListView
            anchors {
              fill: parent
              margins: __style.margin12
            }
            model: dbListModel
            spacing: __style.spacing4
            clip: true

            delegate: Rectangle {
              id: dbDelegate
              width: dbListView.width
              height: __style.row40
              radius: __style.radius8
              color: delegateArea.containsMouse
                     ? __style.lightGreenColor
                     : "transparent"

              // ── Filename label ──────────────────────────────────────
              MMText {
                anchors {
                  verticalCenter: parent.verticalCenter
                  left: parent.left
                  right: parent.right
                  leftMargin: __style.margin8
                  rightMargin: __style.margin8
                }
                text: model.fileName
                font: __style.p5
                color: __style.nightColor
                elide: Text.ElideRight
              }

              // ── Click area ─────────────────────────────────────────
              MouseArea {
                id: delegateArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  // Strip extension so the name field stays clean
                  var fn = model.fileName
                  if (fn.endsWith(".db"))
                    fn = fn.slice(0, -3)
                  else if (fn.endsWith(".sqlite"))
                    fn = fn.slice(0, -7)
                  dbNameInput.text = fn
                }
              }
            }
          }
        }
      }

      // ── Campo: ubicación + botón Examinar ─────────────────────────────
      ColumnLayout {
        Layout.fillWidth: true
        spacing: __style.spacing8

        MMTextInput {
          id: dbPathInput
          Layout.fillWidth: true
          title: qsTr("Ubicación")
          placeholderText: qsTr("Ej: E:/MisDocumentos/")
          enabled: !root.databaseReady && root.selectedDbMessage === ""
        }

        MMButton {
          text: qsTr("Examinar…")
          size: MMButton.Sizes.Small
          type: MMButton.Types.Secondary
          enabled: !root.databaseReady && root.selectedDbMessage === ""
          onClicked: folderDialog.open()
        }
      }

      // ── Notificación de error ─────────────────────────────────────────
      MMNotificationBox {
        Layout.fillWidth: true
        visible: root.errorMessage !== ""
        type: MMNotificationBox.Types.Error
        title: qsTr("Error")
        description: root.errorMessage
      }

      // ── Notificación de éxito: BD creada + botón Exportar ────────────
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

      // ── Notificación de éxito: BD seleccionada ────────────────────────
      MMNotificationBox {
        Layout.fillWidth: true
        visible: root.selectedDbMessage !== ""
        type: MMNotificationBox.Types.Success
        title: qsTr("Base de datos seleccionada")
        description: root.selectedDbMessage
      }

      Item { implicitHeight: __style.spacing20 }

      // ── Botones de acción ─────────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: __style.spacing12

        // Botón principal: "Seleccionar" si el nombre ya existe, "Crear" si no.
        MMButton {
          id: primaryActionBtn
          Layout.fillWidth: true
          visible: !root.databaseReady && root.selectedDbMessage === ""

          text: root._nameAlreadyExists ? qsTr("Seleccionar") : qsTr("Crear")

          onClicked: {
            var name = dbNameInput.text.trim()
            var path = root._activeFolder

            if (root._nameAlreadyExists) {
              // Resolve the actual filename (prefer .db)
              var resolvedName = name + ".db"
              for (var i = 0; i < dbListModel.count; i++) {
                var fn = dbListModel.get(i, "fileName")
                if (fn === name + ".db" || fn === name + ".sqlite" || fn === name) {
                  resolvedName = fn
                  break
                }
              }
              root.databaseSelected(resolvedName, path)
            } else {
              root.createDatabaseRequested(name, path)
            }
          }
        }

        MMButton {
          text: (root.databaseReady || root.selectedDbMessage !== "") ? qsTr("Cerrar") : qsTr("Cancelar")
          type: MMButton.Types.Secondary
          Layout.fillWidth: true
          onClicked: root.backClicked()
        }
      }
    }
  }

  Component.onCompleted: {
    console.log("MMCreateDatabasePage cargado")
    // Pre-fill the path field with defaultPath so FolderListModel scans it
    // immediately and the user can see existing databases right away.
    dbPathInput.text = root.defaultPath
  }
}
