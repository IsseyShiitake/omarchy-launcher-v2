import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// A fullscreen overlay whose surface outlives each open. A fresh surface draws
// its first frames before the compositor sends its fractional scale, so an
// overlay mapped per open flashed blurry until the scale arrived. Closed, the
// surface parks as a 1x1, input-less, content-less layer below windows: small
// enough to cost nothing, off the overlay layer so it never blocks direct
// scanout for fullscreen apps. Opening only resizes and raises it.
PanelWindow {
  id: window

  // Whether the overlay is showing. Drive this instead of visible.
  property bool shown: false
  property int shownLayer: WlrLayer.Overlay
  property int shownKeyboardFocus: WlrKeyboardFocus.Exclusive

  // Fedora port (2026-10-03): hold the fullscreen geometry briefly after
  // shown drops, so a consumer that fades its content out can do so before
  // the surface parks to 1x1.
  //
  // OPT-IN, and OFF by default. The hold keeps the surface fullscreen AND
  // keeps contentItem visible, so a consumer that draws an opaque scrim
  // without binding it to `shown` would leave that scrim on screen for the
  // whole hold. The emoji picker, the clipboard history, the reminder flow
  // and the wifi-QR panel all draw a constant scrim and relied on
  // contentItem.visible going false the instant `shown` dropped — with a
  // global hold they kept a 50-78% black veil for a quarter of a second
  // after they were dismissed. Only the menu fades, so only the menu opts in
  // (Menu.qml sets hideHoldMs on its own instance).
  property int hideHoldMs: 0
  readonly property bool holdGeometry: shown || (hideHoldMs > 0 && hideHold.running)

  // The surface no longer lands on the focused output by being mapped there,
  // so it follows the focused monitor each time it is shown. Unset until the
  // first show lets the compositor choose.
  property var targetScreen: null
  property Region emptyRegion: Region {}

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    }
    return null
  }

  onShownChanged: {
    if (shown) targetScreen = focusedScreen() || targetScreen
    else if (hideHoldMs > 0) hideHold.restart()
  }

  Timer {
    id: hideHold
    interval: window.hideHoldMs
  }

  visible: true
  screen: targetScreen
  anchors { top: true; left: true; bottom: holdGeometry; right: holdGeometry }
  implicitWidth: 1
  implicitHeight: 1
  mask: shown ? null : emptyRegion
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: holdGeometry ? shownLayer : WlrLayer.Bottom
  WlrLayershell.keyboardFocus: shown ? shownKeyboardFocus : WlrKeyboardFocus.None

  // Draw nothing until the surface has actually grown. A frame drawn while it
  // is still 1x1 holds only the scrim's color, which the compositor would
  // stretch across the whole screen until the fullscreen frame arrives.
  Binding {
    target: window.contentItem
    property: "visible"
    value: window.holdGeometry && window.width > 1 && window.height > 1
  }
}
