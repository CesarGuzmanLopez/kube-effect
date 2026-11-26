/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

Node {
    id: cube

    property real faceDisplacement: 100
    // Face material opacity (ADR-021); ScreenView animates it with the turn.
    property real faceOpacity: 1
    required property size faceSize
    // Screen identity passed to every DesktopView (ADR-022): no dynamic-scope
    // lookup of ScreenView.targetScreen from inside the face delegates.
    required property string screenName
    required property rect screenGeometry
    // Camera yaw in degrees, bound once by ScreenView from cameraController.
    // Only the face-visibility test (isFacingCamera) reads it.
    property real cameraYaw: 0
    // The repeater count can transiently be 0, 1 or 2 (desktops are being
    // added/removed while the model syncs). angleTick = 360/count then yields
    // Infinity (NaN flood, doc/trucos-aprendidos.md section C), a huge negative
    // faceDistance (tan(pi) ~ 0⁻) or a ~0 tick. The polygon with fewer than 3
    // sides is degenerate anyway: clamp the geometry to a triangle so every
    // derived value stays finite and positive (ADR-022).
    readonly property int geometryCount: Math.max(3, faceRepeater.count)
    readonly property real angleTick: 360 / geometryCount
    readonly property real faceDistance: 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement

    // True when the face at index points towards the camera half-space. Each
    // face holds a Texture.sourceItem, i.e. a full-resolution offscreen capture
    // that renders EVERY frame it is visible; an invisible Model costs zero
    // captures. Faces with a negative projection (cos < 0) turn their back and
    // are fully occluded by the opaque solid, so hiding them is free
    // (ADR-022 LOD). The threshold is 0, NOT a positive margin: a face at 89°
    // is still front-facing (its inner sliver is visible and a > 0 threshold
    // hid it, leaving a hole with the hull peeking through the edge), while a
    // truly back-facing face only reaches cos < 0 past 90°. With translucent
    // faces (ADR-021) ScreenView keeps every face visible: the far ones must
    // be seen through the near ones.
    function isFacingCamera(index) {
        const faceAzimuth = cube.angleTick * index;
        return Math.cos((faceAzimuth - cube.cameraYaw) * Math.PI / 180) >= 0;
    }

    function desktopAt(azimuth) {
        let index = Math.round(azimuth / angleTick) % geometryCount;
        if (index < 0) {
            index += geometryCount;
        }
        // The delegate may not exist yet (model mid-sync): objectAt returns
        // null, and dereferencing it used to throw inside the click handler.
        const face = faceRepeater.objectAt(index);
        return face !== null && face !== undefined ? face.desktop : null;
    }

    function desktopAzimuth(desktop) {
        // x11DesktopNumber es el NOMBRE del rol que expone el modelo de
        // escritorios virtuales de KWin (heredado de X11); en Wayland también es
        // el número de escritorio, 1..N. No es una ruta de compatibilidad X11.
        return cube.angleTick * (desktop.x11DesktopNumber - 1);
    }

    Repeater3D {
        id: faceRepeater
        model: KWinComponents.VirtualDesktopModel {}
        delegate: CubeFace {
            faceSize: cube.faceSize
            faceOpacity: cube.faceOpacity
            screenName: cube.screenName
            screenGeometry: cube.screenGeometry
            // LOD (ADR-022): opaque solid -> hide the faces turned away from
            // the camera (one less full-res capture each); translucent faces
            // (ADR-021) must all stay visible because the far ones show
            // through the near ones.
            visible: cube.faceOpacity < 0.99 || cube.isFacingCamera(index)
            scale: Qt.vector3d(faceSize.width / 100, faceSize.height / 100, 1)
            eulerRotation.y: cube.angleTick * index
            position: {
                const transform = Qt.matrix4x4();
                transform.rotate(cube.angleTick * index, Qt.vector3d(0, 1, 0));
                return transform.times(Qt.vector3d(0, 0, cube.faceDistance));
            }
        }
    }
}
