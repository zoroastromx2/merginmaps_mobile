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

import mm 1.0 as MM

//
// MMMapCanvas es el componente visual que muestra el mapa cartográfico y
// gestiona toda la interacción del usuario con él: toques, arrastres, pellizcos
// (pinch-to-zoom) y la rueda del ratón en escritorio.
//
// Es un "lienzo" (canvas) puro: no conoce proyectos ni capas directamente;
// delega el renderizado a MM.MapCanvasMap y expone señales hacia arriba para
// que el controlador padre (MMMapController) reaccione a los gestos.
//

Item {
  id: mapRoot

  // ── Señales públicas ────────────────────────────────────────────────────────

  // Emitida ~350 ms después de un toque simple. El retardo intencional permite
  // distinguir un clic de un doble clic antes de notificar al padre.
  signal clicked( point p )

  // Emitida cuando el usuario mantiene presionado el dedo/botón sin moverse
  // (pressAndHold). Se usa, por ejemplo, para mostrar el menú contextual
  // del mapa o para iniciar la captura de un punto.
  signal longPressed( point p )

  // Emitida cuando se detectan dos toques rápidos consecutivos en posiciones
  // cercanas. El controlador la usa para hacer zoom al punto tocado.
  signal doubleClicked( point p )

  // Emitida al girar la rueda del ratón. 'angle' es el ángulo de giro en
  // unidades de "notches" (positivo = hacia arriba = acercar).
  signal wheelTurned( point p, double angle )

  // Emitida durante un arrastre del mapa, con la posición anterior y la nueva.
  // El controlador la usa para desplazar el encuadre del mapa (pan).
  signal dragged( point oldPoint, point newPoint )

  // Emitida cuando el dedo/botón se suelta después de un arrastre.
  // Permite al controlador realizar ajustes finales (ej. inercia).
  signal dragReleased( point p )

  // Emitida cada vez que el usuario interactúa activamente con el mapa
  // (pan o zoom). El controlador la usa para desactivar el centrado
  // automático en la posición GPS mientras el usuario navega manualmente.
  signal userInteractedWithMap()

  // ── Alias a propiedades del renderizador ────────────────────────────────────

  // Expone la configuración del mapa (CRS, extensión, escala, etc.) del
  // renderizador para que el padre pueda leerla y modificarla directamente.
  property alias mapSettings: mapRenderer.mapSettings

  // Expone el estado de renderizado del motor: true mientras hay tiles/capas
  // que aún no han terminado de dibujarse. Útil para mostrar un indicador
  // de carga (spinner) en la UI.
  property alias isRendering: mapRenderer.isRendering

  // ── Funciones públicas ──────────────────────────────────────────────────────

  // Limpia la caché de tiles del renderizador y solicita un nuevo dibujado
  // completo. Se llama, por ejemplo, tras cambiar la simbología de una capa.
  function refresh() {
    mapRenderer.clearCache()
    mapRenderer.refresh()
  }

  // Anima el desplazamiento del mapa desde el centro actual hasta 'newPos'
  // (en coordenadas de pantalla). Usa una animación suavizada (OutQuart)
  // de 500 ms para que el movimiento se vea natural.
  function jumpTo( newPos )
  {
    // Congela el renderizador durante la configuración inicial del animador
    // para evitar fotogramas intermedios no deseados.
    rendererPrivate.freeze('jumpTo')

    // Convierte la posición destino de pantalla → CRS del mapa
    let newPosMapCRS = mapRenderer.mapSettings.screenToCoordinate( newPos )
    // Obtiene el centro actual del mapa en coordenadas del CRS del mapa
    let oldPosMapCRS = mapRenderer.mapSettings.center

    // Desactiva temporalmente el Behavior (animación) para poder asignar
    // la posición de inicio sin que se dispare una animación desde (0,0).
    jumpAnimator.enabled = false
    jumpAnimator.startX = oldPosMapCRS.x
    jumpAnimator.startY = oldPosMapCRS.y
    jumpAnimator.endX = newPosMapCRS.x
    jumpAnimator.endY = newPosMapCRS.y

    // Fija el porcentaje a 0 (posición inicial) sin animación
    jumpAnimator.percentage = 0
    // Reactiva el Behavior para que el siguiente cambio de percentage animage
    jumpAnimator.enabled = true
    // Al asignar 100 se dispara la animación hasta la posición final
    jumpAnimator.percentage = 100
    // Descongela el renderizador para que empiece a pintar los fotogramas
    rendererPrivate.unfreeze('jumpTo')
  }

  // Hace zoom en el punto 'center' (coordenadas de pantalla) aplicando el
  // factor 'scale'. Un scale < 1 acerca; un scale > 1 aleja.
  // Delega directamente en el motor de renderizado.
  function zoom( center, scale )
  {
    mapRenderer.zoom( center, scale )
  }

  // Desplaza el mapa (pan) trasladando el encuadre de 'oldPos' a 'newPos'
  // en coordenadas de pantalla. Delega en el motor de renderizado.
  function pan( oldPos, newPos )
  {
    mapRenderer.pan( oldPos, newPos )
  }

  // ── Animador de salto (jumpTo) ──────────────────────────────────────────────
  // Item invisible que calcula el trayecto geodésico entre dos puntos del mapa
  // e interpolación el recorrido usando un porcentaje (0 → 100).
  Item {
    id: jumpAnimator

    // Coordenadas de inicio y fin del salto en el CRS del mapa
    property double startX
    property double startY
    property double endX
    property double endY

    // Porcentaje del recorrido completado (0 = inicio, 100 = destino).
    // Al cambiar este valor se mueve el mapa proporcionalmente.
    property double percentage: 0

    // Acimut (ángulo de dirección) del vector de desplazamiento, en radianes.
    // Se calcula una sola vez como propiedad derivada (readonly).
    readonly property double azimuth: Math.atan2( startX - endX, startY - endY )

    // Distancia euclidiana entre inicio y fin, en unidades del CRS del mapa.
    readonly property double distance: Math.sqrt( ( startX - endX ) * ( startX - endX ) + ( startY - endY ) * ( startY - endY ) )

    // Behavior: cada vez que 'percentage' cambia, lo anima con una curva
    // OutQuart (rápida al principio, suave al final) en 500 ms.
    // Se puede deshabilitar (enabled: false) para asignar valores sin animar.
    Behavior on percentage {
      NumberAnimation {
        easing.type: Easing.OutQuart // Aceleración inicial, frenado suave al llegar
        duration: 500                // Duración total de la animación en ms
      }
      enabled: jumpAnimator.enabled  // Solo anima si el animador está activo
    }

    // Cada vez que 'percentage' cambia (por la animación o por código),
    // recalcula la posición actual en el trayecto y la aplica al mapa.
    onPercentageChanged: {
      if ( enabled ) {
        // Interpola la posición X usando trigonometría polar:
        // avanza (percentage * 0.01) fracción del total en la dirección del acimut
        let tmpX = startX - percentage * 0.01 * distance * Math.sin( azimuth )
        let tmpY = startY - percentage * 0.01 * distance * Math.cos( azimuth )
        // Convierte las coordenadas interpoladas a QgsPoint y las asigna
        // como nuevo centro del mapa (el renderizador actualizará la vista)
        mapRenderer.mapSettings.center = mapRenderer.mapSettings.toQgsPoint( Qt.point( tmpX, tmpY ) )
      }
    }
  }

  // ── Motor de renderizado del mapa ───────────────────────────────────────────
  // MM.MapCanvasMap es el tipo C++ (QQuickItem) que integra el motor QGIS
  // para renderizar las capas del proyecto activo sobre este Item de QML.
  MM.MapCanvasMap {
    id: mapRenderer

    // El lienzo ocupa todo el área del Item padre (mapRoot)
    width: mapRoot.width
    height: mapRoot.height

    // freeze: cuando es true, el motor no vuelve a renderizar aunque cambien
    // las propiedades del mapa. Se activa durante gestos (pan/pinch/jumpTo)
    // para evitar renders intermedios innecesarios y mejorar la fluidez.
    freeze: false

    // incrementalRendering: muestra los tiles/capas conforme se van generando,
    // en lugar de esperar a que todo el mapa esté listo. Mejora la percepción
    // de rendimiento en mapas con capas pesadas.
    incrementalRendering: true // para que se vaya pintando conforme se va cargando

    // ── Estado privado del renderizador ──────────────────────────────────────
    // QtObject interno que gestiona un mapa de "congeladores" activos.
    // Permite que múltiples gestores (pan, pinch, jumpTo) congelen y
    // descongelen el renderizador de forma independiente y segura:
    // solo se descongela cuando TODOS han llamado a unfreeze().
    QtObject {
      id: rendererPrivate

      // Diccionario (objeto JS) que registra qué gestores tienen el mapa
      // congelado. Clave = identificador del gestor (string), valor = true.
      property var _freezeMap: ({})

      // Registra 'id' como congelador activo y congela el renderizador.
      function freeze( id ) {
        _freezeMap[ id ] = true
        mapRenderer.freeze = true
      }

      // Elimina 'id' del registro. Solo descongela el renderizador si
      // ningún otro gestor sigue congelando (diccionario vacío).
      function unfreeze( id ) {
        delete _freezeMap[ id ]
        mapRenderer.freeze = Object.keys( _freezeMap ).length !== 0
      }

      // Calcula la distancia euclidiana entre dos puntos de pantalla 'a' y 'b'.
      // Se usa para determinar si el desplazamiento supera el umbral de arrastre.
      function vectorDistance( a, b ) {
        return Math.sqrt( Math.pow( b.x - a.x, 2 ) + Math.pow( b.y - a.y, 2 ) )
      }
    }
  }

  // ── Área de gestos multitáctiles (pinch) ────────────────────────────────────
  // PinchArea intercepta los gestos de dos dedos (pellizco) para zoom y pan
  // simultáneo. Envuelve al MouseArea para que ambos coexistan correctamente.
  PinchArea {
    id: pinchArea

    // Identificador usado al congelar/descongelar el renderizador durante pinch
    property string freezeId: 'pinch'

    // Ocupa todo el área del componente padre (mapRoot)
    anchors.fill: parent

    // Al iniciar el pellizco: notifica al padre que el usuario interactúa
    // con el mapa (para desactivar el centrado GPS) y congela el renderizador.
    onPinchStarted: {
      mapRoot.userInteractedWithMap()
      rendererPrivate.freeze( freezeId )
    }

    // Al terminar el pellizco: descongela el renderizador para que vuelva
    // a pintar el resultado final del zoom/pan.
    onPinchFinished: {
      rendererPrivate.unfreeze( freezeId )
    }

    // Durante el pellizco: aplica pan (movimiento del centro) y zoom
    // (factor de escala relativo al fotograma anterior) en cada actualización.
    onPinchUpdated: function ( pinch ) {
      // Pan: desplaza el mapa entre el centro anterior y el actual del pellizco
      mapRenderer.pan( pinch.center, pinch.previousCenter )
      // Zoom: previousScale/scale > 1 cuando los dedos se acercan (zoom out),
      //       < 1 cuando se alejan (zoom in). El motor invierte la lógica internamente.
      mapRenderer.zoom( pinch.center, pinch.previousScale / pinch.scale )
    }

    // ── Área de interacción de ratón / toque individual ─────────────────────
    // Gestiona todos los eventos de un solo puntero: clic, doble clic,
    // mantener presionado, arrastre y rueda del ratón.
    MouseArea {
      id: mouseArea

      // Posición donde comenzó el toque/clic actual (para medir distancia de arrastre)
      property var initialPosition

      // Posición del evento anterior (para calcular el delta de pan en cada frame)
      property var previousPosition

      // true mientras el gesto activo se ha clasificado como arrastre (pan).
      // Una vez true, se suprime la emisión de señales de clic.
      property bool isDragging: false

      // Identificador para el sistema de congelado del renderizador durante el drag
      property string freezeId: 'drag'

      // Ocupa todo el área del PinchArea padre
      anchors.fill: parent

      // Deshabilita el MouseArea mientras un pellizco está activo para evitar
      // que ambos gestores procesen el mismo evento simultáneamente.
      enabled: !pinchArea.pinch.active

      // Desactiva la interpretación de gestos del touchpad como scroll para
      // que solo la rueda física del ratón dispare onWheel (evita doble trigger
      // en laptops con trackpad que también generan eventos de ratón).
      scrollGestureEnabled: false

      // ── Inicio del toque/clic ────────────────────────────────────────────
      onPressed: function ( mouse ) {
        // Guarda la posición inicial para poder calcular más tarde si hubo arrastre
        initialPosition = Qt.point( mouse.x, mouse.y )
        // Congela el renderizador: durante el pan, no interesa re-renderizar en cada pixel
        rendererPrivate.freeze( mouseArea.freezeId )

        // Inicia el temporizador que decide si el gesto es "press breve" o
        // "press largo" (presAndHold). Si expira antes de soltar, se marca
        // como arrastre incluso si no hubo movimiento.
        dragDifferentiatorTimer.start()
      }

      // ── Fin del toque/clic (al soltar el dedo o el botón) ───────────────
      onReleased: function ( mouse ) {
        let clickPosition = Qt.point( mouse.x, mouse.y )

        if ( clickDifferentiatorTimer.running ) {
          //
          // El temporizador de clic ya está corriendo, lo que significa que
          // este es el segundo (o posterior) toque rápido consecutivo.
          // Hay que comprobar si es un doble clic (mismo punto) o simplemente
          // otro clic independiente.
          //

          let isDoubleClick = false
          let previousTapPosition = clickDifferentiatorTimer.clickedPoint

          if ( previousTapPosition ) {
            // Mide la distancia entre el toque anterior y el actual
            let tapDistance = rendererPrivate.vectorDistance( clickPosition, previousTapPosition )
            // Es doble clic si la distancia es menor que el umbral de arrastre del sistema
            isDoubleClick = tapDistance < mouseArea.drag.threshold
          }

          if ( isDoubleClick ) {
            // Es doble clic: marcar para que el temporizador no emita 'clicked'
            // cuando expire (ya que se va a emitir 'doubleClicked' aquí)
            clickDifferentiatorTimer.ignoreNextTrigger = true

            mapRoot.doubleClicked( Qt.point( mouse.x, mouse.y ) )
          }

          // Reinicia el temporizador para detectar posibles triples clics
          clickDifferentiatorTimer.restart()
        }
        else if ( !isDragging && !clickDifferentiatorTimer.ignoreNextTrigger )
        {
          // Primer clic limpio (sin arrastre y sin que el timer esté en marcha):
          // guardar la posición y arrancar el temporizador de diferenciación.
          // Si en el intervalo de doble clic no llega otro toque, se emitirá 'clicked'.

          clickDifferentiatorTimer.clickedPoint = clickPosition
          clickDifferentiatorTimer.ignoreNextTrigger = false // precaución: resetear flag
          clickDifferentiatorTimer.start()
        }
        else
        {
          // El gesto fue un pressAndHold o una liberación de arrastre:
          // ninguno de los dos debe emitir 'clicked'.

          clickDifferentiatorTimer.ignoreNextTrigger = false

          // Notifica al padre que el arrastre terminó en esta posición
          mapRoot.dragReleased( clickPosition )
        }

        // Limpia el estado de rastreo de posición para el siguiente gesto
        previousPosition = null
        initialPosition = null
        isDragging = false

        // Descongela el renderizador ahora que el pan ha terminado
        rendererPrivate.unfreeze( mouseArea.freezeId )

        // Detiene el temporizador de diferenciación de arrastre
        dragDifferentiatorTimer.stop()
      }

      // ── Toque prolongado (pressAndHold) ──────────────────────────────────
      onPressAndHold: function ( mouse ) {
        // Solo emite longPressed si el usuario no estaba arrastrando
        // (un arrastre largo no debe confundirse con un long press)
        if ( !isDragging ) {
          mapRoot.longPressed( Qt.point( mouse.x, mouse.y ) )
        }

        // Marca para que al soltar no se emita también 'clicked'
        clickDifferentiatorTimer.ignoreNextTrigger = true
      }

      // ── Rueda del ratón ──────────────────────────────────────────────────
      onWheel: function ( wheel ) {
        // Retransmite el evento de rueda al padre con la posición del cursor
        // y el ángulo de giro (wheel.angleDelta.y: positivo = scroll arriba = zoom in)
        mapRoot.wheelTurned( Qt.point( wheel.x, wheel.y), wheel.angleDelta.y )
      }

      // ── Movimiento del puntero (pan del mapa) ────────────────────────────
      onPositionChanged: function ( mouse ) {
        let target = Qt.point( mouse.x, mouse.y )

        if ( !previousPosition ) {
          // Primer evento de movimiento: inicializar ambas posiciones de referencia
          previousPosition = target
          initialPosition = target
          return
        }

        // Calcula la posición "reflejada" para simular un desplazamiento natural
        // (como arrastrar el papel bajo el mapa): si el dedo va a la derecha,
        // el mapa debe ir a la izquierda, por eso se invierte el delta.
        let reverted_x = previousPosition.x - ( mouse.x - previousPosition.x )
        let reverted_y = previousPosition.y - ( mouse.y - previousPosition.y )

        // Notifica al padre el arrastre para que el controlador mueva el mapa
        mapRoot.dragged( previousPosition, Qt.point( reverted_x, reverted_y ) )

        // Actualiza la posición anterior para el siguiente evento de movimiento
        previousPosition = target

        if ( !isDragging ) {
          // Todavía no se ha confirmado que sea un arrastre; comprobar umbrales

          let dragDistance = rendererPrivate.vectorDistance( initialPosition, target )

          if ( dragDistance > Application.styleHints.startDragDistance ) {
            // El dedo se ha movido más allá del umbral de distancia del sistema:
            // clasificar como arrastre.
            isDragging = true
          }

          if ( !dragDifferentiatorTimer.running ) {
            // El temporizador ya expiró (el usuario lleva demasiado tiempo
            // presionando): clasificar como arrastre igualmente.
            isDragging = true
          }

          if ( isDragging ) {
            // Ahora que es un arrastre confirmado, cancelar cualquier clic
            // pendiente para que no se emita 'clicked' al soltar.
            clickDifferentiatorTimer.stop()
            clickDifferentiatorTimer.ignoreNextTrigger = false
          }
        }
      }

      // ── Cambio de estado de arrastre ─────────────────────────────────────
      onIsDraggingChanged: {
        if ( isDragging ) {
          // Notifica al padre que el usuario interactúa con el mapa (pan activo)
          mapRoot.userInteractedWithMap()
        }
      }

      // ── Cancelación del gesto (el PinchArea tomó el control) ────────────
      onCanceled: {
        // El PinchArea ha reclamado los eventos; resetear todo el estado del
        // MouseArea sin emitir señales de clic ni arrastre.
        previousPosition = null
        initialPosition = null
        isDragging = false

        rendererPrivate.unfreeze( mouseArea.freezeId )
        dragDifferentiatorTimer.stop()
      }

      // ── Temporizador de diferenciación de clic / doble clic ─────────────
      // Espera el intervalo de doble clic del sistema antes de emitir 'clicked'.
      // Si en ese tiempo llega otro toque, se cancela o se reclasifica como
      // doble clic (lógica en onReleased).
      Timer {
        id: clickDifferentiatorTimer

        // Coordenadas del toque que inició este ciclo de detección
        property var clickedPoint

        // Si true, al expirar el timer no se emite 'clicked' (ej. tras un
        // doble clic o un pressAndHold que ya fue procesado)
        property bool ignoreNextTrigger

        // Usa el intervalo de doble clic definido por el sistema operativo
        // para que el comportamiento sea coherente con el resto de la UI.
        interval: Application.styleHints.mouseDoubleClickInterval

        // Al expirar sin que llegara un segundo toque: confirmar clic simple.
        onTriggered: {
          if ( !ignoreNextTrigger ) {
            mapRoot.clicked( clickedPoint )  // emitir clic simple al padre
          }
          // Resetear para el siguiente ciclo de detección
          ignoreNextTrigger = false
          clickedPoint = null
        }
      }

      // ── Temporizador de diferenciación de arrastre / press breve ────────
      // Si el usuario presiona y suelta antes de que este timer expire,
      // el gesto se considera un toque simple (clic o long press).
      // Si el timer expira mientras el dedo sigue presionado y moviéndose,
      // el gesto se reclasifica como arrastre (pan).
      Timer {
        id: dragDifferentiatorTimer

        // Usa el umbral de tiempo de arrastre definido por el sistema operativo
        interval: Application.styleHints.startDragTime
      }
    }
  }
}
