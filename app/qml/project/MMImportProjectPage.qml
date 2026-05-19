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

import Qt5Compat.GraphicalEffects
import QtQuick.Dialogs

import mm 1.0 as MM

import "../components"

/**
 * MMImportProjectPage
 *
 * Allows the user to pick a local .qgz file from any location on the device
 * and open it directly in Mergin Maps, bypassing the Mergin server workflow.
 *
 * Usage: push this page onto the project controller's StackView.
 * It emits openProjectRequested(path) when a valid file is selected.
 */
MMPage {
  id: root

  // ── Public API ────────────────────────────────────────────────────────────

  /// Emitted with a POSIX path to the .qgz file ready to be opened
  signal openProjectRequested( string projectFilePath )

  // ── Page chrome ──────────────────────────────────────────────────────────

  pageHeader.title: qsTr( "Import Local Project" )
  pageHeader.backVisible: true

  onBackClicked: stackView.popOnePageOrClose()

  // ── Body ─────────────────────────────────────────────────────────────────

  pageContent: Item {
    width: parent.width
    height: parent.height

    ColumnLayout {
      anchors {
        centerIn: parent
        left: parent.left
        right: parent.right
        margins: __style.pageMargins
      }

      spacing: __style.margin24

      // Illustration / icon
      MMIcon {
        Layout.alignment: Qt.AlignHCenter
        source: __style.folderIcon   // reuse existing icon from mmstyle.h
        size: 80 * __dp
        color: __style.grassColor
      }

      // Title text
      MMText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: qsTr( "Open a QGIS project from your device" )
        font: __style.t2
        color: __style.nightColor
        wrapMode: Text.WordWrap
      }

      // Description
      MMText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: qsTr( "Select a .qgz file stored anywhere on your device. "
                  + "On Android the file will be copied to the app's private "
                  + "cache so QGIS libraries can open it." )
        font: __style.p6
        color: __style.greyColor
        wrapMode: Text.WordWrap
      }

      // ── Primary action button ───────────────────────────────────────────
      MMButton {
        id: pickFileBtn

        Layout.fillWidth: true
        Layout.topMargin: __style.margin12

        text: qsTr( "Select .qgz file" )
        iconSourceLeft: __style.workspacesIcon

        onClicked: {
          busyOverlay.visible = true
          // Delegate to C++ – result arrives via Connections below
          __filePickerManager.openFilePicker()
        }
      }

      // Small hint
      MMText {
        id: statusText

        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: ""
        font: __style.p7
        color: __style.greyColor
        wrapMode: Text.WordWrap
        visible: text !== ""
      }
    }

    // Translucent overlay shown while Android copies the file to cache
    Rectangle {
      id: busyOverlay
      anchors.fill: parent
      color: Qt.rgba( 0, 0, 0, 0.35 )
      visible: false
      z: 10

      MMBusyIndicator {
        anchors.centerIn: parent
        running: busyOverlay.visible
      }

      // Safety: allow tap-to-cancel overlay if something hangs
      MouseArea {
        anchors.fill: parent
        onClicked: busyOverlay.visible = false
      }
    }
  }

  // ── Connections to C++ FilePickerManager singleton ────────────────────────

  Connections {
    target: __filePickerManager

    function onFileSelected( filePath ) {
      busyOverlay.visible = false
      statusText.text = qsTr( "Project loaded: " ) + filePath
      root.openProjectRequested( filePath )
    }

    function onFilePickerCancelled() {
      busyOverlay.visible = false
      statusText.text = qsTr( "Selection cancelled." )
    }

    function onNotifyError( msg ) {
      busyOverlay.visible = false
      statusText.text = msg
      __notificationModel.addError( msg )
    }

    function onNotifyInfo( msg ) {
      __notificationModel.addInfo( msg )
    }
  }
}