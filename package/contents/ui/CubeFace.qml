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
    // Material opacity (ADR-021), animated by ScreenView between the rest and
    // rotation values. Below 1 the material joins QtQuick3D's transparent
    // pass, which sorts blended faces back-to-front (Wayfire's two-pass
    // equivalent); the future cylinder mesh inherits this without changes.
    property real faceOpacity: 1

    pickable: true
    source: "#Rectangle"
    materials: [
        DefaultMaterial {
            cullMode: Material.NoCulling
            lighting: DefaultMaterial.NoLighting
            opacity: face.faceOpacity
            diffuseMap: Texture {
                sourceItem: DesktopView {
                    desktop: face.desktop
                    width: faceSize.width
                    height: faceSize.height
                }
            }
        }
    ]
}
