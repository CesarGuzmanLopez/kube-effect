/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

// One face of the solid (the face node) plus its window layers (ADR-028).
// The root is a plain Node carrying ONLY the placement transform (the
// position/eulerRotation.y the Cube delegate sets, ADR-026: rotate(tick * i)
// translate(0, 0, faceDistance)); the face Model and the layer quads hang
// under it so they inherit exactly that transform — the layer stack sinks
// along the face normal, never in world space.
//
// The SCALE moved from the root to the face Model (faceScale): with a
// unit-scale root the quads can apply their own "#Rectangle" scale in face
// units (1 unit = 1 px) without double-multiplying by the face scale, on
// every representation (polygon/sheet: faceScale = size/100 as before;
// drum: faceScale = 1 because the arc mesh is already in px, but the quads
// are flat and always size/100, ADR-028 rule 6). The composed world
// transform is numerically identical to the old Model-root.
Node {
  id: faceRoot

  required property QtObject desktop
  required property int index
  required property size faceSize
  // Screen identity from Cube (ADR-022): DesktopView must not resolve
  // ScreenView.targetScreen through dynamic scope.
  required property string screenName
  required property rect screenGeometry
  // The face Model's own scale (see the node comment above); the Cube
  // delegate keeps computing it exactly as before.
  property vector3d faceScale: Qt.vector3d(1, 1, 1)
  // Material opacity (ADR-021), animated by ScreenView between the rest and
  // rotation values. ADR-026 made the render pass EXPLICIT instead of
  // accidental: a DefaultMaterial whose diffuseMap is a Texture.sourceItem
  // is flagged transparent by the renderer because the grabbed item's
  // texture has an alpha channel (qssglayerrenderdata.cpp, the Diffuse map
  // check) — so even at opacity 1 every face sat in the transparent pass,
  // where the only ordering is the centroid sort. PrincipledMaterial does
  // not flag transparency from the baseColorMap (the BaseColor type is
  // skipped on purpose there), so the mode below states the intent:
  // Blend while turning (opacity < 0.99, back-to-front by the per-face
  // sort centroids of the polygon-style placement) and Mask at rest ONLY
  // for the curved faces (a discarded below-cutoff pixel keeps the
  // desktop showing through the face's alpha holes, a kept pixel renders
  // as opaque and WRITES DEPTH, so a far arc can never paint over a near
  // face even if a sort tie ever comes back). Measured in the engine
  // (the cylinder pixel gate was retired for cost, doc/trucos-aprendidos.md
  // section P): a SetToOpaque/Opaque at rest would
  // instead paint those holes BLACK, which is why the rest branch is
  // Mask, not Opaque.
  // The Mask branch is bounded to the cylinder (re-review): the polygon
  // and the flat sheet NEVER had the overlap (their face positions are
  // already distinct sort centroids, the layout ADR-023 defends as the
  // virgin look) and their rest rendering blends as it always did — a
  // Mask there would hard-cut the ADR-023 look for no proven benefit:
  // window drop shadows and anti-aliased edges below the cutoff would
  // vanish and semi-transparent windows (alpha < 0.5, blur panels) would
  // snap solid. The cutoff is pinned explicitly: relying on Qt's default
  // would let a future Qt change silently move the hard/soft edge of the
  // face holes.
  property real faceOpacity: 1
  // Curved geometry for the cylinder shape (ADR-025): the ONE ProceduralMesh
  // shared by every face (same arc, different rotation), or null for the
  // flat built-in rectangle. Qt requires an empty source when a custom
  // geometry is used, hence the switch in both properties.
  property Geometry cylinderMesh: null
  // Material culling: ALWAYS Material.NoCulling (ADR-025 point 12 reverted
  // the dynamic BackFaceCulling experiment: it also hid the inner wall that
  // ADR-023 keeps on purpose, the polygon parity). Cube.faceCullMode is the
  // single source; the overlap ADR-025 pointed at is fixed by paint order
  // (sort centroids + the explicit alphaMode above), not by culling, and
  // the cylinderCullMode seed note lives in Cube.qml.
  property int cullMode: Material.NoCulling
  // Window layers (ADR-028), resolved upstream in Cube: whether THIS face
  // instantiates quads (flag AND LOD distance), the fitted-step request in
  // px, the depth budget of the representation and the plate alpha. Raw
  // kwinrc values never reach here. With layersActive false WindowLayers
  // adds zero nodes with a visible effect and layeredIds stays empty:
  // pixel-for-pixel the cube of before.
  property bool layersActive: false
  property real layerGap: 120
  property real layerMaxDepth: 150
  property real layerPlateOpacity: 0.25

  // The face surface: the grab of the whole desktop EXCEPT the windows that
  // won a layer (their ids get wId = "" — the hole is the clip, ADR-028).
  // pickable + desktop stay on the Model that is hit: ScreenView's click
  // handler reads hitResult.objectHit.desktop (the quads re-expose the same
  // desktop themselves).
  Model {
    id: face

    // Re-exposed for picking (the root Node receives the role injection).
    property QtObject desktop: faceRoot.desktop

    scale: faceRoot.faceScale
    pickable: true
    source: faceRoot.cylinderMesh === null ? "#Rectangle" : ""
    geometry: faceRoot.cylinderMesh
    materials: [
      PrincipledMaterial {
        cullMode: faceRoot.cullMode
        lighting: PrincipledMaterial.NoLighting
        alphaMode: faceRoot.faceOpacity < 0.99 || faceRoot.cylinderMesh === null ? PrincipledMaterial.Blend : PrincipledMaterial.Mask
        alphaCutoff: 0.5
        opacity: faceRoot.faceOpacity
        baseColorMap: Texture {
          sourceItem: DesktopView {
            id: faceGrab
            desktop: faceRoot.desktop
            screenName: faceRoot.screenName
            screenGeometry: faceRoot.screenGeometry
            width: faceRoot.faceSize.width
            height: faceRoot.faceSize.height
            // The layer set comes from the layers' MODEL DATA (never from
            // this grab): releasing an id here can never feed back into
            // layeredIds, so no binding cycle is possible.
            layeredIds: faceLayers.layeredIds
          }
        }
      }
    ]
  }

  WindowLayers {
    id: faceLayers
    desktop: faceRoot.desktop
    faceSize: faceRoot.faceSize
    screenName: faceRoot.screenName
    screenGeometry: faceRoot.screenGeometry
    active: faceRoot.layersActive
    layerGap: faceRoot.layerGap
    maxLayerDepth: faceRoot.layerMaxDepth
    plateOpacity: faceRoot.layerPlateOpacity
    faceOpacity: faceRoot.faceOpacity
  }

  // --- gate accessors (scripts/check-layers.py reads the live tree) --------
  readonly property QtObject windowLayers: faceLayers
  readonly property QtObject grab: faceGrab
}
