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

import mm 1.0 as MM

import "../components"

/*
 * MMTablesController — controller for the tables module.
 * The only component that knows dbManager.
 * Manages navigation with an internal StackView and connects signals
 * from Pages/Drawers to backend calls.
 */

Item {
  id: root

  // ── API pública ───────────────────────────────────────────────────────
  signal closed()

  property var dbManager: null

  // ── StackView de navegación ───────────────────────────────────────────
  StackView {
    id: stackView
    anchors.fill: parent

    Component.onCompleted: {
      stackView.push(databaseManagerPageComp, {}, StackView.Immediate)
    }
  }

  // ── Página principal: gestor de BD ────────────────────────────────────
  Component {
    id: databaseManagerPageComp

    MMDatabaseManagerPage {
      tableModel:   root.dbManager ? root.dbManager.tableModel : null
      tableList:    root.dbManager ? root.dbManager.tableList : []
      currentTable: root.dbManager ? root.dbManager.currentTable : ""
      rowCount:     root.dbManager ? root.dbManager.rowCount : 0

      onTableSelected:          function(name) { root.dbManager.setCurrentTable(name) }
      onAddRowRequested:        function() { root.dbManager.addRow() }
      onRemoveRowRequested:     function(i) { root.dbManager.removeRow(i) }
      onSubmitChangesRequested: function() {
        if (root.dbManager.submitChanges()) {
          viewStateSuccess()
        } else {
          viewStateError()
        }
      }
      onRevertChangesRequested: function() { root.dbManager.revertChanges() }
      onFilterRequested:        function(text) { root.dbManager.filterTable(text) }
      onClearFilterRequested:   function() { root.dbManager.clearFilter() }
      onCreateTableRequested:   function() { stackView.push(createTablePageComp, {}, StackView.PushTransition) }
      onCreateDatabaseRequested: function() { stackView.push(createDatabasePageComp, {}, StackView.PushTransition) }
      onBackClicked:            function() { root.closed() }
    }
  }

  // ── Página: crear / abrir base de datos ──────────────────────────────
  Component {
    id: createDatabasePageComp

    MMCreateDatabasePage {
      // Exponer la ruta predeterminada del dbManager si está disponible,
      // para que el FolderListModel la escanee desde el primer render.
      defaultPath: root.dbManager && root.dbManager.defaultDatabasePath
                   ? root.dbManager.defaultDatabasePath
                   : "./"

      onCreateDatabaseRequested: function(name, path) {
        if (name.trim() === "") {
          errorMessage = qsTr("El nombre no puede estar vacío")
          return
        }

        var dbPath = path.trim()
        if (dbPath === "") dbPath = "./"
        if (!dbPath.endsWith("/") && !dbPath.endsWith("\\")) dbPath += "/"

        var fullPath = dbPath + name.trim() + ".db"
        console.log("Intentando crear BD en: " + fullPath)

        if (root.dbManager && root.dbManager.initializeDatabase(fullPath)) {
          // Marcar como exitosa y guardar ruta — el usuario cierra manualmente
          databaseReady = true
          createdDbPath = fullPath
        } else {
          errorMessage = qsTr("Error: ") + (root.dbManager ? root.dbManager.getLastError() : qsTr("DBManager no disponible"))
        }
      }

      onDatabaseSelected: function(name, path) {
        // Construir la ruta completa (name ya viene con extensión .db / .sqlite)
        var dbPath = path
        if (!dbPath.endsWith("/") && !dbPath.endsWith("\\")) dbPath += "/"
        var fullPath = dbPath + name
        console.log("Abriendo BD existente: " + fullPath)

        if (root.dbManager && root.dbManager.initializeDatabase(fullPath)) {
          // Mostrar mensaje de confirmación en la página y volver al gestor
          // tras un breve instante para que el usuario lo vea.
          selectedDbMessage = qsTr("'%1' abierta correctamente. Cargando gestor…").arg(name)
          openAfterSelectTimer.start()
        } else {
          errorMessage = qsTr("Error al abrir BD: ") +
                         (root.dbManager ? root.dbManager.getLastError() : qsTr("DBManager no disponible"))
        }
      }

      onExportDatabaseRequested: function(destPath) {
        if (root.dbManager) {
          if (root.dbManager.copyDatabaseTo(destPath)) {
            console.log("BD exportada a: " + destPath)
          } else {
            errorMessage = qsTr("Error al exportar: ") + root.dbManager.getLastError()
          }
        }
      }

      onBackClicked: function() { stackView.pop(StackView.PopTransition) }
    }
  }

  // ── Página: crear tabla ───────────────────────────────────────────────
  Component {
    id: createTablePageComp

    MMCreateTableDrawer {
      dbNameToShow: root.dbManager ? root.dbManager.databaseName : ""
      dbPathToShow: root.dbManager ? root.dbManager.databasePath : ""

      onCreateTableRequested: function(tableName, fields) {
        if (!root.dbManager) {
          errorMessage = qsTr("DBManager no está configurado")
          return
        }
        if (root.dbManager.createTable(tableName, fields)) {
          stackView.pop(StackView.PopTransition)
        } else {
          errorMessage = qsTr("Error: ") + root.dbManager.getLastError()
        }
      }
      onClosed: function() { stackView.pop(StackView.PopTransition) }
    }
  }

  // ── Timer: cierre automático tras crear BD con éxito ──────────────────
  Timer {
    id: closeAfterSuccessTimer
    interval: 1500
    onTriggered: stackView.pop(StackView.PopTransition)
  }

  // ── Timer: volver al gestor después de seleccionar una BD existente ───
  // Se activa desde onDatabaseSelected; espera 1.2 s para que el usuario
  // lea el mensaje de confirmación y luego hace pop al gestor.
  Timer {
    id: openAfterSelectTimer
    interval: 1200
    onTriggered: stackView.pop(StackView.PopTransition)
  }

  // ── Conexiones con el backend ──────────────────────────────────────────
  Connections {
    target: root.dbManager

    function onErrorOccurred(errorMessage) {
      console.log("MMTablesController: error en dbManager: " + errorMessage)
    }

    function onTableModelChanged() {
      console.log("MMTablesController: tableModel actualizado")
    }

    function onDataChanged() {
      console.log("MMTablesController: datos actualizados")
    }
  }

  // ── Helpers de estado ─────────────────────────────────────────────────
  function viewStateSuccess() {
    console.log("MMTablesController: operación exitosa")
  }

  function viewStateError() {
    console.log("MMTablesController: operación con error")
  }
}
