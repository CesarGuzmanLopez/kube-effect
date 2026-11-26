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
    // rotation values. Below 1 the material joins QtQuick3D's transparent
    // pass, which sorts blended faces back-to-front (Wayfire's two-pass
    // equivalent); the cylinder arc uses the very same material, unchanged
    // (ADR-025).
    property real faceOpacity: 1
    // Curved geometry for the cylinder shape (ADR-025): the ONE ProceduralMesh
    // shared by every face (same arc, different rotation), or null for the
    // flat built-in rectangle. Qt requires an empty source when a custom
    // geometry is used, hence the switch in both properties.
    property Geometry cylinderMesh: null
    // Material culling (ADR-025 point 12): the cube passes Material enum
    // values already — BackFaceCulling on cylinder faces while the camera
    // stays outside R (the mirrored inner wall no longer covers the front
    // faces), NoCulling everywhere else (polygon, sheet, the drum seen
    // from within): the virgin look of ADR-023 needs no culling and this
    // default keeps it byte-identical for those shapes.
    property int cullMode: Material.NoCulling

    pickable: true
    source: cylinderMesh === null ? "#Rectangle" : ""
    geometry: cylinderMesh
    materials: [
        DefaultMaterial {
            cullMode: face.cullMode
            lighting: DefaultMaterial.NoLighting
            opacity: face.faceOpacity
            diffuseMap: Texture {
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
