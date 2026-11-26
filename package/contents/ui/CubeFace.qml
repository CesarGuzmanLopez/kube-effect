/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

Model {
    id: face

    required property QtObject desktop
    required property int index
    required property size faceSize
    // Screen identity from Cube (ADR-022): DesktopView must not resolve
    // ScreenView.targetScreen through dynamic scope.
    required property string screenName
    required property rect screenGeometry
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
    // (scripts/check-cylinder-overlap): a SetToOpaque/Opaque at rest would
    // instead paint those holes BLACK, which is why the rest branch is
    // Mask, not Opaque.
    // The Mask branch is bounded to the cylinder (re-review): the polygon
    // and the flat sheet NEVER had the overlap (their face positions are
    // already distinct sort centroids, the layout ADR-023 defends as the
    // virgin look) and their rest rendering blends as it always did —
    // a Mask there would hard-cut the ADR-023 look for no proven benefit:
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

    pickable: true
    source: cylinderMesh === null ? "#Rectangle" : ""
    geometry: cylinderMesh
    materials: [
        PrincipledMaterial {
            cullMode: face.cullMode
            lighting: PrincipledMaterial.NoLighting
            alphaMode: face.faceOpacity < 0.99 || face.cylinderMesh === null ? PrincipledMaterial.Blend : PrincipledMaterial.Mask
            alphaCutoff: 0.5
            opacity: face.faceOpacity
            baseColorMap: Texture {
                sourceItem: DesktopView {
                    desktop: face.desktop
                    screenName: face.screenName
                    screenGeometry: face.screenGeometry
                    width: faceSize.width
                    height: faceSize.height
                }
            }
        }
    ]
}
