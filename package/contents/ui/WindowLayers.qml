/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "layerGeometry.js" as LayerGeometry

// The window layers of ONE face (ADR-028, model H).
//
// The face itself does not move: it stays the surface of the shell, and its
// grab releases (wId = "", the null QUuid of KWin 6 — an integer 0 does NOT
// detach a thumbnail, doc/trucos-aprendidos.md section N) exactly the windows
// that win a quad here, leaving a transparent hole behind which the quad
// floats. The hole clips every layer to the face in any view, so nothing
// ever protrudes from the solid: the transparency guarantees it, not the
// distance to the axis.
//
// Each quad is a "#Rectangle" Model scaled by the WINDOW size / 100, so one
// unit is one pixel (the same convention as the flat face, ARQUITECTURA 2.4
// "Units") and every quad covers exactly its own hole. Depth counts
// INWARDS from the top of the stack: rank = how many windows of this face
// have a smaller stackingOrder, the front-most window (rank == maxRank)
// stays at -epsilon and every rank below sinks one fitted step further.
// The step is fitted (never clamped per layer): a stack that does not fit
// the budget keeps its order and the deepest layer lands EXACTLY on
// maxLayerDepth.
//
// The plate is the optional dark veil (WindowLayerPlateOpacity) just behind
// the deepest layer; through the holes it is what the windows read against.
// Quads and plate multiply the FACE opacity (ADR-021): turning fades the
// whole pile, not only the base.
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
  // (already clamped 0-600), the depth budget of this representation and
  // the plate alpha (0-1). Raw kwinrc values never reach this component.
  property real layerGap: LayerGeometry.GAP_DEFAULT
  property real maxLayerDepth: LayerGeometry.LAYER_DEPTH_CAP
  property real plateOpacity: LayerGeometry.PLATE_OPACITY_DEFAULT
  // The face material opacity (ADR-021): the whole pile fades with it.
  property real faceOpacity: 1

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
  readonly property real fittedGap: LayerGeometry.fittedGap(root.layerGap, root.maxLayerDepth, root.maxRank)

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

  // The veil behind the deepest layer (never in front of any quad, the
  // ARQUITECTURA 2.4 trap). Plain dark colour, two-sided like the face it
  // backs; visible only while the face instantiates layers at all.
  Model {
    id: plate
    visible: root.active && root.plateOpacity > 0.001
    source: "#Rectangle"
    position: Qt.vector3d(0, 0, -LayerGeometry.plateDepth(root.maxLayerDepth))
    scale: Qt.vector3d(root.faceSize.width / 100, root.faceSize.height / 100, 1)
    castsShadows: false
    receivesShadows: false
    materials: [
      PrincipledMaterial {
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.NoCulling
        // Blend ALWAYS (ADR-028 rule 5): the plate is translucent by
        // design; Mask would snap it opaque and cover the whole pile.
        alphaMode: PrincipledMaterial.Blend
        baseColor: LayerGeometry.PLATE_COLOR
        opacity: root.plateOpacity * root.faceOpacity
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
      readonly property real layerDepth: root.revision >= 0 ? LayerGeometry.layerDepth(root.maxRank, root.rankOf(layer.winnerId()), root.fittedGap) : 0
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
      source: "#Rectangle"
      // Exactly the window size in face units (1 unit = 1 px).
      scale: Qt.vector3d(win !== null && win.width > 0 ? win.width / 100 : 1, win !== null && win.height > 0 ? win.height / 100 : 1, 1)
      // Inwards, never outwards (+z is the outward normal); the epsilon
      // keeps every quad strictly behind the face plane.
      position: Qt.vector3d(localX, localY, -(layerDepth + LayerGeometry.LAYER_EPSILON))
      materials: [
        PrincipledMaterial {
          lighting: PrincipledMaterial.NoLighting
          cullMode: Material.NoCulling
          // Blend ALWAYS (ADR-028 rule 5): the layers are translucent by
          // design and the transparent-pass centroid rule (ADR-026) orders
          // them; Mask would hard-discard below-cutoff pixels of rounded
          // or semi-transparent windows (and write depth, occluding the
          // layers behind from their own holes).
          alphaMode: PrincipledMaterial.Blend
          opacity: root.faceOpacity
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
}
