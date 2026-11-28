/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "layerGeometry.js" as LayerGeometry

// The window layers of ONE face (ADR-028 model H, as amended 2026-11-27:
// the stack travels OUTWARDS, +z along the face normal).
//
// The face itself does not move: it stays the surface of the shell, and its
// grab releases (wId = "", the null QUuid of KWin 6 — an integer 0 does NOT
// detach a thumbnail, doc/trucos-aprendidos.md section N) exactly the windows
// that win a quad here, leaving a transparent hole where each window used to
// be. The hole stays on purpose: without it the flat window in the grab and
// its quad would render twice.
//
// Why outwards (measured in the nested session, 3 desks, pitch=30, yaw=71,
// opacity 1.00, gap 120): with the stack pushed INWARDS the holes of the
// face showed the INTERIOR of the solid — white wedges of far quads/faces
// and the wallpaper label "ABA" mirrored through the gaps — and the windows
// read as sunk inside the cube. Outwards is the desk metaphor: every quad
// floats in front of its hole, the window with the HIGHEST stackingOrder is
// the CLOSEST to the observer. Accepted trade-off: orbiting, a quad can
// leave the silhouette of its face (windows floating over the desk — the
// requested look; the earlier exploration discarded outward quads only
// because that model had no holes and no veil to cross).
//
// Each quad is a "#Rectangle" Model scaled by the WINDOW size / 100, so one
// unit is one pixel (the same convention as the flat face, ARQUITECTURA 2.4
// "Units") and every quad covers exactly its own hole. Depth counts
// OUTWARDS and the WHOLE stack floats (third amendment, measured
// 2026-11-27: parking rank 0 at bare +epsilon made the maximized window
// read as "glued to the desktop all the time"): rank = how many windows of
// this face have a smaller stackingOrder, the bottom of the pile floats one
// fitted step off the face and every rank above rises one more step. The
// step is fitted (never clamped per layer): a stack that does not fit the
// cap keeps its order and the outermost layer lands EXACTLY on the cap;
// the step also separates the layers from the face itself. Only gap 0
// collapses everything back onto +epsilon (flat parity).
//
// The plate is the optional dark veil (WindowLayerPlateOpacity) just BEHIND
// the face plane (z = -2), in front of the interior: through the holes it is
// what the windows read against, and it is what stops the inside of the cube
// from showing through them.
//
// The slab (fourth amendment, FINAL design): with an effective thickness
// above 0 a layer is ONE closed ProceduralMesh box (SlabMesh.qml, shared
// unit box, scaled to win.width x win.height x eff) instead of the flat
// quad: subset 0 is the FRONT with the textured material and the proven
// #Rectangle UVs, subset 1 the four sides plus the back with the edge
// colour. The front stays exactly on the ladder - the cap is marked by
// the FRONT, not by the centre - and eff is clipped to half the fitted
// step (layerGeometry.thicknessEffective), so the back of one box never
// reaches the front of the next: two layers can never intersect. Both
// materials use BackFaceCulling on the box: the first attempt (a separate
// solid #Cube behind a Mask quad, NoCulling everywhere) let the
// TRANSPARENT shadow margins of the thumbnail show the box's inner black
// side - a giant bezel, measured 2026-11-28; a closed culled box cannot
// leak, and the margin pixels fall through to the plate/interior exactly
// as before. With eff 0 (or the Helpers module missing, where the Loader
// degrades to a null mesh) the Model keeps the built-in #Rectangle with
// NoCulling: pixel-for-pixel the flat quad model.
//
// Quads and plate fade with the LAYER opacity
// (WindowLayerRotationOpacity while rotating, 1 at rest) instead of the face
// opacity: with the default 0.7 equal to the face rotation default the whole
// pile fades exactly like the face while turning (the ADR-021 behaviour),
// and with the flag off the key is inert — the windows are pixels of the
// face grab and share the desktop's transparency exactly.
//
// Discards (ADR-028 rule 4): minimized windows do not exist (same as the
// flat grab) and docks/panels plus the desktop (wallpaper) window stay
// FLAT in the grab — releasing one of those would open a hole with no quad
// behind it (a hole in the shell). A window whose wrapper exposes no
// width/height (an unexpected older KWin) fails the width > 0 test and is
// NOT layered either: the safe side of the model is always "fewer holes,
// never a hole without a quad". The KWin 6.8 scripting Window is measured
// to expose x/y/width/height/internalId/stackingOrder/minimized/dock/
// desktopWindow; only the first five are guaranteed here (the existing
// DesktopView reads x/y/minimized/internalId/stackingOrder), the rest are
// read as optional booleans where undefined simply means "not set".
//
// Deterministic order (ARQUITECTURA 2.4 "Consejos"): ranks never depend on
// the completion order of the delegates. The component keeps a map
// internalId -> stackingOrder plus a revision counter, and every depth
// binding re-evaluates through that counter; the delegates feed the map
// (on completion, on stackingOrderChanged and on show/hide transitions).
// Closed windows MUST leave the map: internalId values are recycled, and a
// stale entry would hand the next window with that id a wrong rank — so the
// id is captured at completion (the row's window may already be null when
// the delegate is destroyed) and pruned in onDestruction.
//
// layeredIds is published as a data-derived snapshot (an object id -> true,
// rebuilt inside noteOrder/forgetOrder, never read back from the grab), so
// CubeFace can bind the face DesktopView to it without creating a binding
// cycle: grab holes follow the model data, never the other way around.
//
// LOD (ADR-028 rule 3): the Cube resolves the per-face decision into
// `active`. Inactive faces instantiate NO quads (Repeater3D model 0 — the
// delegates die, the map empties and the grab keeps every window: pixel
// parity with the cube of before) and hide the plate. The face grab itself
// is NEVER reduced by the LOD (ADR-023 stands): an instantiated quad costs
// one capture per frame even when culled, which is exactly why the LOD
// gates instantiation and not painting.
Node {
  // The id is deliberately NOT "layers": QtQuick3D Node carries an
  // int member named layers (rendering layer, default 1) and unqualified
  // references inside a component resolve MEMBERS BEFORE IDS, so an id
  // layers would silently become the number 1 in every delegate binding
  // (measured: "Property 'rankOf' of object 1 is not a function").
  id: root

  // The desktop this face shows (required by WindowFilterModel) and the
  // 2D identity the quads need to turn global window rects into face-local
  // px (the same screenGeometry the face grab uses).
  required property QtObject desktop
  required property size faceSize
  property rect screenGeometry: Qt.rect(0, 0, faceSize.width, faceSize.height)
  property string screenName: ""
  // Instantiate quads at all? Resolved by Cube from WindowLayering and the
  // WindowLayerLodFaces distance (false => zero nodes with a visible effect).
  property bool active: false
  // Resolved by Cube through layerGeometry.js: the requested step in px
  // (already clamped 0-600) and the plate alpha (0-1). Raw kwinrc values
  // never reach this component. The budget needs no wiring any more: since
  // the amendment the stack travels outwards and the cap (LAYER_DEPTH_CAP)
  // is the same fixed budget for every shape.
  property real layerGap: LayerGeometry.GAP_DEFAULT
  property real plateOpacity: LayerGeometry.PLATE_OPACITY_DEFAULT
  // Slab box (fourth amendment): the thickness REQUEST (clamped 0-300 with
  // the schema default 24 - measured, the first default 2 never read - and
  // then clipped to half the fitted STEP inside thicknessEffective, the
  // step being per face) and the resolved edge colour. raw 0 = flat quads
  // exactly as before (pixel parity).
  // var, not real: undefined (kwinrc key never saved, ScreenView passes
  // it raw through Cube and CubeFace) must survive to
  // thicknessEffective below - a typed property would coerce it to 0 and
  // silently flatten the slab (the measured unset-key bug 2026-11-28).
  property var layerThickness: LayerGeometry.THICKNESS_DEFAULT
  property color edgeColor: LayerGeometry.EDGE_COLOR_DEFAULT
  readonly property real layerSlabEff: LayerGeometry.thicknessEffective(root.layerThickness, root.fittedGap)
  // The shared unit box mesh via a runtime Loader (the arc/cap isolation
  // pattern): without QtQuick3D.Helpers the Loader simply fails to load,
  // slabBox stays null and every layer keeps the flat #Rectangle - the
  // thickness degrades, the effect does not.
  readonly property Geometry slabBox: slabMeshLoader.status === Loader.Ready && slabMeshLoader.item !== null && slabMeshLoader.item !== undefined ? slabMeshLoader.item.mesh : null
  // The EFFECTIVE opacity of the pile, animated by ScreenView with the very
  // faceOpacity mechanism (Constants.faceOpacity(1, resolved
  // WindowLayerRotationOpacity, cubeMoving) + FaceFadeMs): 1 at rest, the
  // key's value while turning (0.7 default == the face rotation default).
  // The alphaMode threshold reads THIS value: at >= 0.99 (rest, or the key
  // at 1.0 even while turning) the quads are Mask; below, Blend — the face
  // opacity no longer fades the pile (the key owns that). Inert while the
  // flag is off: no quads exist and the face materials never read it.
  property real layerOpacity: 1

  // internalId -> stackingOrder over the layered windows of THIS face only.
  property var orderById: ({})
  // The revision counter every depth binding reads to re-evaluate when the
  // map changes (the delegates' own bindings would otherwise cache a rank
  // computed from a half-filled map).
  property int revision: 0
  // Snapshot id -> true of the windows that have a quad: CubeFace feeds it
  // to the face grab so exactly these ids are released with wId = "".
  property var layeredIds: ({})

  // The `root.revision >= 0` term is not a condition: it is the read that
  // registers the dependency on the in-place map (revision only counts up),
  // so every binding here re-evaluates when any delegate notes/forgets an
  // order — ranks never depend on the completion order of the delegates.
  readonly property int maxRank: root.revision >= 0 ? Math.max(0, Object.keys(root.orderById).length - 1) : 0
  readonly property real fittedGap: LayerGeometry.fittedGap(root.layerGap, root.maxRank)

  function noteOrder(id, order) {
    if (id === null || id === undefined || order === undefined || order === null) {
      return;
    }
    if (root.orderById[id] === order) {
      return;
    }
    root.orderById[id] = order;
    root.revision += 1;
    root.refreshLayeredIds();
  }

  function forgetOrder(id) {
    if (id === null || id === undefined || !(id in root.orderById)) {
      return;
    }
    delete root.orderById[id];
    root.revision += 1;
    root.refreshLayeredIds();
  }

  function refreshLayeredIds() {
    // A fresh object every time: assigning a new identity emits the change
    // signal the face grab binding listens to (mutating in place would not).
    const next = {};
    for (const id in root.orderById) {
      next[id] = true;
    }
    root.layeredIds = next;
  }

  // rank = how many layered windows of this face stack BELOW the given id.
  function rankOf(id) {
    const mine = root.orderById[id];
    if (mine === undefined) {
      return 0;
    }
    let rank = 0;
    for (const other in root.orderById) {
      if (root.orderById[other] < mine) {
        rank += 1;
      }
    }
    return rank;
  }

  // The one window source of the effect (same three filters as the face
  // grab: activity, desktop, screen). The discards are NOT here: they are
  // per-delegate (showLayer), because the grab must keep showing them.
  KWinComponents.WindowFilterModel {
    id: windowFilter
    // Localized disable, NOT file-wide: org.kde.kwin registers its types at
    // RUNTIME inside the kwin binary (there are no static .qmltypes for a
    // standalone qmllint), so "Type not found in namespace" on
    // KWinComponents.Workspace is the documented noise class of the Makefile
    // QMLLINT_ALLOWED list — here only to keep the new-code Sonar gate clean
    // without flagging the sibling lines (identical warnings in main.qml,
    // ScreenView.qml and DesktopView.qml stay untouched as old code).
    // qmllint disable unresolved-type
    activity: KWinComponents.Workspace.currentActivity
    // qmllint enable unresolved-type
    desktop: root.desktop
    screenName: root.screenName
    windowModel: KWinComponents.WindowModel {}
  }

  // The slab unit box (fourth amendment): reached through a runtime
  // Loader exactly like the arc and the caps — QtQuick3D.Helpers missing
  // only ever fails THIS loader (slabBox stays null, every layer keeps the
  // flat quad); the file itself is static-import-safe. Active whenever a
  // slab could be needed on this face (an effective thickness above 0 -
  // fitted-step changes re-evaluate it, the unit geometry itself never
  // changes once loaded).
  Loader {
    id: slabMeshLoader
    active: root.layerSlabEff > 0
    source: "SlabMesh.qml"
  }

  // The veil just behind the face plane (z = -2, the amended ARQUITECTURA
  // 2.4 rule): it veils the grab holes so the interior of the solid never
  // shows through them, and it stays strictly behind every quad (those start
  // at +epsilon). Plain dark colour, two-sided like the face it backs;
  // visible only while the face instantiates layers at all.
  Model {
    id: plate
    visible: root.active && root.plateOpacity > 0.001
    source: "#Rectangle"
    position: Qt.vector3d(0, 0, -LayerGeometry.plateDepth())
    scale: Qt.vector3d(root.faceSize.width / 100, root.faceSize.height / 100, 1)
    castsShadows: false
    receivesShadows: false
    materials: [
      PrincipledMaterial {
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.NoCulling
        // Blend ALWAYS by design: a uniform veil colour with no content to
        // order, so the opaque-pass trick the quads use (threshold + depth
        // writes) buys nothing here and Mask would snap the veil opaque over
        // its own alpha. Fades with the pile (layerOpacity), never with the
        // face: plateOpacity x layerOpacity.
        alphaMode: PrincipledMaterial.Blend
        baseColor: LayerGeometry.PLATE_COLOR
        opacity: root.plateOpacity * root.layerOpacity
      }
    ]
  }

  Repeater3D {
    id: quads
    // model 0 while the face does not layer (flag off or outside the LOD):
    // zero quads, zero captures, and the map/prune paths leave layeredIds
    // empty, so the face grab re-attaches every window (pixel parity).
    model: root.active ? windowFilter : 0
    delegate: Model {
      id: layer

      required property var model
      required property int index

      readonly property QtObject win: model.window !== null && model.window !== undefined ? model.window : null
      // The window rect in face-local pixels: centred like the face grab
      // (Y flipped, QML down -> +Y up in the scene).
      readonly property real localX: win !== null ? win.x - root.screenGeometry.x + win.width / 2 - root.faceSize.width / 2 : 0
      readonly property real localY: win !== null ? root.faceSize.height / 2 - (win.y - root.screenGeometry.y + win.height / 2) : 0
      // Raw stacking order; the ROW index is only the tie-breaker of a
      // wrapper without the property (never expected, never hole-y: the
      // rank math below still produces distinct depths per order).
      readonly property int order: win !== null && win.stackingOrder !== undefined && win.stackingOrder !== null ? win.stackingOrder : index
      // Discards (ADR-028 rule 4): minimized does not exist, docks/panels
      // and the desktop window stay flat in the grab, an empty window
      // cannot win a hole. Optional flags are tested "not equal to true": a
      // wrapper without the property behaves as not-a-dock, and width/height
      // (undefined > 0 is false) then fail the size test — the safe side.
      readonly property bool showLayer: win !== null && win.minimized !== true && win.width > 0 && win.height > 0 && win.dock !== true && win.desktopWindow !== true
      // Guard-read on root.revision (same pattern as maxRank): the binding
      // re-evaluates whenever the rank map changes, keeping the fitted step
      // and the depth of THIS quad in sync with the others without a bare
      // statement qmllint would flag.
      readonly property real layerDepthOut: root.revision >= 0 ? LayerGeometry.layerDepthOut(root.rankOf(layer.winnerId()), root.fittedGap) : LayerGeometry.LAYER_EPSILON
      // Effective slab thickness for THIS delegate (per face, same fitted
      // step as the ladder): 0 (or a missing Helpers module) keeps the
      // built-in flat quad.
      readonly property real slabEff: root.layerSlabEff
      // The layer renders as the closed box only when there is real depth
      // AND the mesh loaded; otherwise it is the flat #Rectangle of the
      // original model (NoCulling, parity).
      readonly property bool boxActive: root.slabBox !== null && root.slabBox !== undefined && layer.slabEff > 0
      // Captured while the window still exists: onDestruction may already
      // face a null row, and the id is still needed to prune the map.
      property var trackedId: null
      // The face desktop re-exposed for picking: a click on a quad selects
      // the desktop of its face (ADR-028 rule 5; activating the clicked
      // window itself is future work of the native module).
      readonly property QtObject desktop: root.desktop

      function winnerId() {
        if (layer.win !== null) {
          layer.trackedId = layer.win.internalId;
        }
        return layer.trackedId;
      }

      function syncOrder() {
        const id = layer.winnerId();
        if (layer.showLayer) {
          root.noteOrder(id, layer.order);
        } else {
          root.forgetOrder(id);
        }
      }

      visible: showLayer
      pickable: true
      castsShadows: false
      receivesShadows: false
      // One Model per layer: the flat built-in quad, or the shared unit
      // box scaled to this window when the slab is active (a custom
      // geometry requires source "" - the CubeFace/arc rule).
      source: layer.boxActive ? "" : "#Rectangle"
      geometry: layer.boxActive ? root.slabBox : null
      // Exactly the window size in face units (1 unit = 1 px); the box's
      // z scale turns the unit depth 100 into the EFFECTIVE thickness (a
      // raw request beyond half the step is clipped, never obeyed).
      scale: Qt.vector3d(win !== null && win.width > 0 ? win.width / 100 : 1, win !== null && win.height > 0 ? win.height / 100 : 1, layer.boxActive ? layer.slabEff / 100 : 1)
      // Outwards (+z is the face normal), the whole stack floating: the
      // bottom sits one fitted step + epsilon off the face, the top window
      // is the outermost (exactly cap + epsilon when the stack overflows).
      // The epsilon inside layerDepthOut keeps every quad strictly in
      // front of the face plane even at gap 0. The box CENTRES on that
      // rule: its FRONT (local +50 z, scaled) lands exactly back on the
      // ladder, so the cap and the no-crossing guarantee are all measured
      // at the front face, never at the centre.
      position: Qt.vector3d(localX, localY, layer.boxActive ? layerDepthOut - layer.slabEff / 2 : layerDepthOut)
      materials: [
        PrincipledMaterial {
          lighting: PrincipledMaterial.NoLighting
          // Subset 0 (front): NoCulling keeps the proven two-sided rule of
          // the FLAT quad (the ADR-025 look when the box is off); the box
          // itself must be culled — NoCulling on a closed box showed its
          // inner black side through the thumbnail's transparent shadow
          // margins (the measured bezel, 2026-11-28).
          cullMode: layer.boxActive ? Material.BackFaceCulling : Material.NoCulling
          // The ADR-026 threshold over the LAYER opacity (measured, the
          // amendment to the amendment): a quad's sort centroid carries the
          // window's lateral offset, so the transparent-pass centroid order
          // does NOT follow the rank — at oblique angles at rest a lower
          // rank painted over the top one. While the pile is effectively
          // opaque (rest, or WindowLayerRotationOpacity 1.0 turning) the
          // quad joins the OPAQUE pass with depth writes: real geometry
          // settles the overlap (the outermost wins the pixel). Below
          // 0.99 it is Blend again with the fade, and the residual centroid
          // swaps last only WHILE turning (documented accepted behaviour).
          // Unlike the face Mask (bounded to the cylinder, where the flat
          // pile never overlapped), the quads always overlap each other at
          // oblique angles, so the threshold applies on every shape.
          alphaMode: layerOpacity < 0.99 ? PrincipledMaterial.Blend : PrincipledMaterial.Mask
          // Pinned explicitly (the face argument: never rely on a Qt
          // default moving the hard/soft edge). Trade-off measured: at rest
          // the AA window edge/shadow cuts hard at the cutoff, same class
          // as the cylinder face holes (ADR-026).
          alphaCutoff: 0.5
          opacity: root.layerOpacity
          baseColorMap: Texture {
            sourceItem: KWinComponents.WindowThumbnail {
              // A dropped window (hidden while the delegate still exists,
              // e.g. it just became a dock) releases the capture too: the
              // null QUuid as the EMPTY STRING, never an integer 0.
              wId: layer.showLayer && layer.win !== null ? layer.win.internalId : ""
              width: layer.win !== null && layer.win.width > 0 ? layer.win.width : 1
              height: layer.win !== null && layer.win.height > 0 ? layer.win.height : 1
            }
          }
        },
        // Subset 1 (the four sides + the back): the uniform edge colour.
        // BackFaceCulling always on the box — through the back you must
        // see the plate/interior (the flat-model behaviour), never the
        // inside of the box. Same threshold and opacity as the front: the
        // rim joins the opaque depth-writing pass exactly when the pile
        // is solid. The colour is baseColor: PrincipledMaterial has no
        // diffuseColor (that name belongs to DefaultMaterial; assigning
        // it here was a "non-existent property" load error, measured).
        // While the layer is flat this material simply never binds a
        // subset (the #Rectangle has one) - harmless, and it keeps the
        // materials list shape constant for the gate.
        PrincipledMaterial {
          // FRAGMENT lighting on the edge only (measured 2026-11-28: the
          // unlit flat colour "reads as a shadow, not a solid" - there was
          // a band but no volume). The camera-anchored headlight of
          // ScreenView (present iff WindowLayering) shades the four edge
          // orientations differently; roughness keeps it a matte plastic,
          // never a mirror. The TEXTURED front and every face of the cube
          // stay NoLighting - the ADR-026 grab contract never gets
          // re-illuminated.
          lighting: PrincipledMaterial.Fragment
          roughness: 0.7
          // (metalness, not "metallic": the Qt6 PrincipledMaterial spelling
          // - the live loader rejects "metallic", measured.)
          metalness: 0.0
          cullMode: Material.BackFaceCulling
          alphaMode: root.layerOpacity < 0.99 ? PrincipledMaterial.Blend : PrincipledMaterial.Mask
          alphaCutoff: 0.5
          baseColor: root.edgeColor
          opacity: root.layerOpacity
        }
      ]

      Connections {
        target: layer.win

        function onStackingOrderChanged() {
          layer.syncOrder();
        }
      }

      onShowLayerChanged: layer.syncOrder()

      Component.onCompleted: layer.syncOrder()
      Component.onDestruction: root.forgetOrder(layer.trackedId)
    }
  }

  // --- gate accessors (scripts/check-root.py reads the live tree) --------
  readonly property int quadCount: quads.count
  function quadAt(i) {
    return quads.objectAt(i);
  }
  readonly property bool plateVisibleNow: plate.visible
  readonly property real plateZNow: plate.position.z
  // Material contract reads (live engine values, not the bindings): the
  // plate must stay Blend always and fade as plateOpacity x layerOpacity.
  readonly property string plateAlphaModeNow: plate.materials[0].alphaMode === PrincipledMaterial.Mask ? "mask" : plate.materials[0].alphaMode === PrincipledMaterial.Opaque ? "opaque" : plate.materials[0].alphaMode === PrincipledMaterial.Blend ? "blend" : "unknown"
  readonly property string plateLightingNow: plate.materials[0].lighting === PrincipledMaterial.NoLighting ? "none" : plate.materials[0].lighting === PrincipledMaterial.Fragment ? "fragment" : "other"
  // Slab loader visibility (the never-relax gate + the debug overlay):
  // the raw Loader.Status int (Null 0 / Ready 1 / Loading 2 / Error 3) and
  // its errorString, so the check-layers oracle can tell "the box loaded"
  // from "the Loader failed because the file is broken" (a measured
  // incident: invented subset bounds made this Loader an ERROR forever
  // while the gate relaxed on a false "Helpers missing") and the
  // DebugOverlay can show slab=N/N with the layers alive on screen.
  readonly property int slabLoaderStatus: slabMeshLoader.status
  readonly property string slabLoaderError: slabMeshLoader.errorString
  // Layers currently rendered as a real box (all delegates of an active
  // face with the mesh loaded and an effective thickness above 0).
  readonly property int boxLiveCount: root.active && root.slabBox !== null && root.slabBox !== undefined && root.layerSlabEff > 0 ? quads.count : 0

  Connections {
    target: slabMeshLoader

    function onStatusChanged() {
      // ONE warning per component (nested.log captures the console - the
      // diagnostic channel of the learned-tricks section D): a failed
      // SlabMesh load must NEVER look like a silent flat fallback.
      if (slabMeshLoader.status === Loader.Error && !root.slabLoadWarned) {
        root.slabLoadWarned = true;
        console.warn("kube-effect WindowLayers: SlabMesh.qml Loader failed - layers stay FLAT:", slabMeshLoader.errorString);
      }
    }
  }
  property bool slabLoadWarned: false
  readonly property real plateOpacityNow: plate.materials[0].opacity
}
