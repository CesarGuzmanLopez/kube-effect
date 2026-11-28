import QtQuick
import QtQuick3D

// Directory of the real effect components: this harness instantiates the
// SAME Cube.qml that ScreenView.qml builds at runtime — and through it
// CubeFace, WindowLayers and the face DesktopView — exactly like
// check-cylinder-wiring.qml, so a broken import, property name or binding
// fails THIS gate, not the cube. Nothing is rendered: the Python side
// (check-layers.py) validates the dumped object tree against an
// independent oracle (layers_contract.py).
import "../package/contents/ui" as UI
import "../package/contents/ui/constants.js" as Constants
import "../package/contents/ui/layerGeometry.js" as LayerGeo

// Scenario knobs arrive as context properties from check-layers.py:
//   stubDesktopCount   the stub VirtualDesktopModel size (shared harness)
//   stubLayering       the WindowLayering bool (raw kwinrc meaning)
//   stubGap / stubLod / stubPlate   the raw Int/Int/Double values — they
//     cross the gate UNRESOLVED on purpose: Cube must clamp them through
//     layerGeometry.js, and the Python oracle mirrors that resolution.
//   stubCurrentNumber  x11DesktopNumber of the fake current desktop
//     (drives Cube.currentFaceIndex and the LOD decision per face).
//   stubLayerRotation  the raw WindowLayerRotationOpacity Double (None =
//     never saved; the schema default 0.7 must answer through the
//     layerGeometry resolver).
//   stubRotating       simulates ScreenView's root.cubeMoving: the harness
//     then drives cube.layerOpacity through the EXACT runtime chain
//     (LayerGeo.rotationOpacity + Constants.faceOpacity(1, v, true)), the
//     same composition ScreenView.qml holds (ScreenView itself needs the
//     whole effect context, so the chain is mirrored here line for line;
//     the oracle re-derives it independently in Python).
//   stubFaceOpacity    the cube's face material opacity (default 1): the
//     parity clause reads the live FACE materials and expects them to
//     follow ONLY this value, never layerOpacity.
Item {
  id: harness

  readonly property bool knobLayering: typeof stubLayering === "boolean" && stubLayering
  readonly property var rawGap: typeof stubGap === "number" ? stubGap : null
  readonly property var rawLod: typeof stubLod === "number" ? stubLod : null
  readonly property var rawPlate: typeof stubPlate === "number" ? stubPlate : null
  readonly property var rawLayerRotation: typeof stubLayerRotation === "number" ? stubLayerRotation : null
  readonly property bool knobRotating: typeof stubRotating === "boolean" && stubRotating
  readonly property real knobFaceOpacity: typeof stubFaceOpacity === "number" ? stubFaceOpacity : 1
  readonly property int rawCurrent: typeof stubCurrentNumber === "number" ? stubCurrentNumber : 0

  // The fake current desktop: a real QObject with the number Cube
  // compares (identity across model wrappers is not guaranteed; the
  // NUMBER is the contract, x11DesktopNumber, the same role the
  // VirtualDesktopModel stub fills).
  property var currentStub: null
  Component.onCompleted: {
    if (harness.rawCurrent > 0) {
      const obj = Qt.createQmlObject("import QtQuick; QtObject { property int x11DesktopNumber }", harness);
      obj.x11DesktopNumber = harness.rawCurrent;
      harness.currentStub = obj;
    }
  }

  UI.Cube {
    id: cube
    // A small synthetic screen (1000x700): since the amendment the budget is
    // the FIXED cap (150 px) for every shape — polygon, sheet and drum alike
    // — so the gap-600 scenarios must land the outermost quad exactly on
    // cap + epsilon on the 3-face polygon AND on the 2-face sheet, which is
    // what clause (b) pins.
    faceSize: Qt.size(1000, 700)
    screenName: ""
    screenGeometry: Qt.rect(0, 0, 1000, 700)
    windowLayering: harness.knobLayering
    windowLayerGap: harness.rawGap
    windowLayerLodFaces: harness.rawLod
    windowLayerPlateOpacity: harness.rawPlate
    currentDesktop: harness.currentStub
    faceOpacity: harness.knobFaceOpacity
    // The runtime ScreenView chain, mirrored (see the knob comment): the
    // layerGeometry resolver clamps the raw key and Constants.faceOpacity
    // picks rest=1 vs the key by the moving signal. With the flag off this
    // binding still runs but reaches NOTHING visible (no quads, plate
    // hidden, face materials never read layerOpacity) — the parity clause
    // pins exactly that.
    layerOpacity: Constants.faceOpacity(1, LayerGeo.rotationOpacity(harness.rawLayerRotation), harness.knobRotating)
  }

  // The live tree, serialised for the Python oracle. The reads below also
  // register the binding dependencies (faceCount, revision, layeredIds...
  // every quad position), so the value stays current after the
  // Repeater3D settles.
  readonly property string dumpJson: buildDump()

  function buildDump() {
    const count = cube.faceCount;
    const currentIdx = cube.currentFaceIndex;
    // Enum -> name for the live quad materials (the face/plate enums are
    // already stringified by the components' own gate accessors).
    function modeName(m) {
      if (m === PrincipledMaterial.Mask) {
        return "mask";
      }
      if (m === PrincipledMaterial.Opaque) {
        return "opaque";
      }
      if (m === PrincipledMaterial.Blend) {
        return "blend";
      }
      return "unknown";
    }
    const faces = [];
    for (let i = 0; i < count; ++i) {
      const face = cube.faceNodeAt(i);
      if (face === null || face === undefined) {
        continue;
      }
      const wl = face.windowLayers;
      const grabView = face.grab;
      const quads = [];
      const revision = wl.revision;
      for (let q = 0; q < wl.quadCount; ++q) {
        const quad = wl.quadAt(q);
        if (quad === null || quad === undefined) {
          continue;
        }
        quads.push({
          id: quad.win !== null ? String(quad.win.internalId) : null,
          order: quad.order,
          x: quad.position.x,
          y: quad.position.y,
          z: quad.position.z,
          visible: quad.visible,
          showLayer: quad.showLayer,
          pickable: quad.pickable,
          desktopOk: quad.desktop === face.desktop,
          alphaMode: modeName(quad.materials[0].alphaMode),
          alphaCutoff: quad.materials[0].alphaCutoff,
          materialOpacity: quad.materials[0].opacity
        });
      }
      const grabs = [];
      for (let t = 0; t < grabView.thumbnailCount; ++t) {
        const thumb = grabView.thumbnailAt(t);
        if (thumb === null || thumb === undefined) {
          continue;
        }
        const win = thumb.srcWindow;
        grabs.push({
          id: win !== null && win !== undefined ? String(win.internalId) : null,
          wId: thumb.wId === null || thumb.wId === undefined ? null : String(thumb.wId)
        });
      }
      faces.push({
        index: i,
        desktopNumber: face.desktop !== null && face.desktop !== undefined ? face.desktop.x11DesktopNumber : -1,
        active: wl.active,
        revision: revision,
        maxRank: wl.maxRank,
        fittedGap: wl.fittedGap,
        layeredIds: Object.keys(wl.layeredIds),
        quads: quads,
        grabs: grabs,
        plateVisible: wl.plateVisibleNow,
        plateZ: wl.plateZNow,
        plateAlphaMode: wl.plateAlphaModeNow,
        plateOpacityLive: wl.plateOpacityNow,
        faceAlphaMode: face.faceMatModeNow,
        faceOpacityLive: face.faceMatOpacityNow,
        faceCutoffLive: face.faceMatCutoffNow
      });
    }
    return JSON.stringify({
      layering: cube.windowLayering,
      faceCount: count,
      currentFaceIndex: currentIdx,
      currentStubNumber: harness.rawCurrent,
      faceWidth: 1000,
      faceHeight: 700,
      gapRaw: harness.rawGap,
      lodRaw: harness.rawLod,
      plateRaw: harness.rawPlate,
      layerRotationRaw: harness.rawLayerRotation,
      rotating: harness.knobRotating,
      faceOpacityLive: cube.faceOpacity,
      layerOpacityLive: cube.layerOpacity,
      faces: faces
    });
  }
}
