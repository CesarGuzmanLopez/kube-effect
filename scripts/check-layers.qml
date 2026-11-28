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
//   stubThickness      the raw WindowLayerThickness Int request: the
//     effective value is clipped per face to half the fitted step in
//     layerGeometry.thicknessEffective (the oracle mirrors both steps).
//   stubEdgeColor      the raw WindowLayerEdgeColor string (garbage must
//     fall back to the schema default through layerGeometry.edgeColor).
Item {
  id: harness

  readonly property bool knobLayering: typeof stubLayering === "boolean" && stubLayering
  readonly property var rawGap: typeof stubGap === "number" ? stubGap : null
  readonly property var rawLod: typeof stubLod === "number" ? stubLod : null
  readonly property var rawPlate: typeof stubPlate === "number" ? stubPlate : null
  readonly property var rawLayerRotation: typeof stubLayerRotation === "number" ? stubLayerRotation : null
  readonly property bool knobRotating: typeof stubRotating === "boolean" && stubRotating
  // Every knob unset from the context arrives as a real undefined when
  // this flag is on - the exact value KWin's scripted effect.configuration
  // returns for a kwinrc key that was never saved (the measured bug that
  // made int/real properties coerce undefined to 0 before the resolvers;
  // see ADR-028 fourth amendment note). The python side mirrors the
  // schema defaults from these undefined raws.
  readonly property bool knobDefaultsUnset: typeof stubDefaultsUnset === "boolean" && stubDefaultsUnset
  readonly property real knobFaceOpacity: typeof stubFaceOpacity === "number" ? stubFaceOpacity : 1
  readonly property int rawCurrent: typeof stubCurrentNumber === "number" ? stubCurrentNumber : 0
  readonly property var rawThickness: typeof stubThickness === "number" ? stubThickness : null
  readonly property string rawEdgeColor: typeof stubEdgeColor === "string" ? stubEdgeColor : "#141719"
  // Whether the runtime module set (QtQuick3D.Helpers behind SlabMesh.qml)
  // loaded: without it the box degrades to the flat quad and the oracle
  // relaxes the box clauses exactly like the effect does. (A probe
  // Loader, not a Component: Component elements take no properties
  // besides id, the loader is the URL-based compile path.)
  readonly property bool helpersOk: slabProbe.status === Loader.Ready
  // Distinguishes the two Loader.Error causes (measured incident: an
  // invented subset property gave Error FOREVER while the gate wrongly
  // relaxed as if the module were absent). The module is genuinely absent
  // only when its error says "not installed"; a compile error keeps every
  // box clause HARD.
  readonly property bool helpersInstalled: slabProbe.status === Loader.Ready || !/not installed/i.test(slabProbe.errorString)
  Loader {
    id: slabProbe
    source: "../package/contents/ui/SlabMesh.qml"
  }

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

  // The headlight gate, MIRRORED exactly as ScreenView.qml declares it
  // (a Repeater3D riding on the camera, model 1 iff WindowLayering, the
  // same euler (25, -35) and brightness 0.8): ScreenView itself cannot be
  // instantiated here
  // (it needs the live effect context), so this is the same trade-off the
  // scene-environment gate documents - the MECHANISM is exercised (a
  // Repeater3D under a camera node instantiates zero delegates with
  // model 0), the constants are pinned by the python mirror.
  PerspectiveCamera {
    id: headlightCamera
    Repeater3D {
      id: headlightRepeater
      model: harness.knobLayering ? 1 : 0
      DirectionalLight {
        eulerRotation: Qt.vector3d(25, -35, 0)
        color: "#ffffff"
        brightness: 0.8
        castsShadow: false
      }
    }
  }
  readonly property int headlightCount: headlightRepeater.count

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
    windowLayerGap: harness.knobDefaultsUnset ? undefined : harness.rawGap
    windowLayerLodFaces: harness.knobDefaultsUnset ? undefined : harness.rawLod
    windowLayerPlateOpacity: harness.knobDefaultsUnset ? undefined : harness.rawPlate
    // var chain end to end: the raw (possibly undefined) reaches
    // layerGeometry.thicknessEffective untouched, exactly as in runtime.
    windowLayerThickness: harness.knobDefaultsUnset ? undefined : harness.rawThickness
    windowLayerEdgeColor: harness.knobDefaultsUnset ? "" : harness.rawEdgeColor
    currentDesktop: harness.currentStub
    faceOpacity: harness.knobFaceOpacity
    // The runtime ScreenView chain, mirrored (see the knob comment): the
    // layerGeometry resolver clamps the raw key and Constants.faceOpacity
    // picks rest=1 vs the key by the moving signal. With the flag off this
    // binding still runs but reaches NOTHING visible (no quads, plate
    // hidden, face materials never read layerOpacity) — the parity clause
    // pins exactly that.
    layerOpacity: Constants.faceOpacity(1, LayerGeo.rotationOpacity(harness.knobDefaultsUnset ? undefined : harness.rawLayerRotation), harness.knobRotating)
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
    // Material.CullMode on Qt 6.12: BackFace=1, Front=2, None=3 (the enum
    // note in Cube.qml) - name it for the oracle instead of an int.
    function cullName(c) {
      if (c === Material.BackFaceCulling) {
        return "back";
      }
      if (c === Material.FrontFaceCulling) {
        return "front";
      }
      if (c === Material.NoCulling) {
        return "none";
      }
      return "unknown";
    }
    // PrincipledMaterial.Lighting by VALUE: NoLighting=0 is reachable by
    // name, but this Qt build leaves the name PrincipledMaterial.Fragment
    // undefined in value position (the ASSIGNMENT still works - verified:
    // the material reads back 1). Pin the numbers with the comment.
    function lightingName(l) {
      if (l === PrincipledMaterial.NoLighting || l === 0) {
        return "none";
      }
      if (l === 1) {
        return "fragment";
      }
      return "other";
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
          materialOpacity: quad.materials[0].opacity,
          // Slab (fourth amendment, FINAL single-box design): one Model
          // per layer; flat = built-in #Rectangle, boxed = the shared
          // unit ProceduralMesh (two subsets) scaled to the window.
          boxMode: quad.geometry !== null && quad.geometry !== undefined ? "box" : "flat",
          boxSubsets: quad.geometry !== null && quad.geometry !== undefined ? quad.geometry.subsets.length : 0,
          scaleX: quad.scale.x,
          scaleY: quad.scale.y,
          scaleZ: quad.scale.z,
          frontCull: cullName(quad.materials[0].cullMode),
          edgeCull: cullName(quad.materials[1].cullMode),
          frontHasMap: quad.materials[0].baseColorMap !== null && quad.materials[0].baseColorMap !== undefined,
          frontLighting: lightingName(quad.materials[0].lighting),
          edgeLighting: lightingName(quad.materials[1].lighting),
          edgeRoughness: quad.materials[1].roughness,
          edgeMetallic: quad.materials[1].metalness,
          edgeAlphaMode: modeName(quad.materials[1].alphaMode),
          edgeOpacity: quad.materials[1].opacity,
          edgeR: quad.materials[1].baseColor.r,
          edgeG: quad.materials[1].baseColor.g,
          edgeB: quad.materials[1].baseColor.b,
          edgeA: quad.materials[1].baseColor.a
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
        plateLighting: wl.plateLightingNow,
        slabLoaderStatus: wl.slabLoaderStatus,
        slabLoaderError: wl.slabLoaderError,
        boxLiveCount: wl.boxLiveCount,
        faceLighting: face.faceMatLightingNow,
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
      gapRaw: harness.knobDefaultsUnset ? undefined : harness.rawGap,
      lodRaw: harness.knobDefaultsUnset ? undefined : harness.rawLod,
      plateRaw: harness.knobDefaultsUnset ? undefined : harness.rawPlate,
      thicknessRaw: harness.knobDefaultsUnset ? undefined : harness.rawThickness,
      edgeRaw: harness.knobDefaultsUnset ? "" : harness.rawEdgeColor,
      helpers: harness.helpersOk,
      helpersInstalled: harness.helpersInstalled,
      headlightCount: harness.headlightCount,
      layerRotationRaw: harness.knobDefaultsUnset ? undefined : harness.rawLayerRotation,
      rotating: harness.knobRotating,
      faceOpacityLive: cube.faceOpacity,
      layerOpacityLive: cube.layerOpacity,
      faces: faces
    });
  }
}
