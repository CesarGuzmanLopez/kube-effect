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
    // Camera yaw in degrees, bound by ScreenView. The face LOD was retired
    // (ADR-023), so only the debug overlay reads it; ScreenView feeds it from
    // a single DebugOverlay-gated toEulerAngles() (the gradient-yaw pattern,
    // ADR-022), so no decomposition is paid while the overlay is off.
    property real cameraYaw: 0
    // The repeater count can transiently be 0, 1 or 2 (desktops are being
    // added/removed while the model syncs). angleTick = 360/count then yields
    // Infinity (NaN flood, doc/trucos-aprendidos.md section C), a huge negative
    // faceDistance (tan(pi) ~ 0⁻) or a ~0 tick. The polygon with fewer than 3
    // sides is degenerate anyway: clamp the geometry to a triangle so every
    // derived value stays finite and positive (ADR-022).
    readonly property int geometryCount: Math.max(3, faceRepeater.count)
    // Raw delegate count, for the debug overlay only (ADR-023): it can briefly
    // be 0..2 mid-sync and then differs from geometryCount. Faces themselves
    // never branch on it — the LOD is retired, every face renders always.
    readonly property int faceCount: faceRepeater.count
    readonly property real angleTick: 360 / geometryCount
    readonly property real faceDistance: 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement

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
            // Every face renders always (ADR-023): the back-facing ones show
            // their inner side through the gaps between faces, which IS the
            // look of the virgin KDE cube; hiding them opened hull holes.
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
