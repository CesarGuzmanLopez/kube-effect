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
    readonly property real faceDistance: 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement
    readonly property real angleTick: 360 / faceRepeater.count

    function desktopAt(azimuth) {
        let index = Math.round(azimuth / angleTick) % faceRepeater.count;
        if (index < 0) {
            index += faceRepeater.count;
        }
        return faceRepeater.objectAt(index).desktop;
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
