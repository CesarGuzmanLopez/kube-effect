/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "constants.js" as Constants

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
    // added/removed while the model syncs). Below 3 the solid is not a polygon
    // at all: it is the sheet (ADR-024), whose tick and radius are fixed values
    // (Infinity/NaN from 360/count can never happen). The polygon branch keeps
    // the old ADR-022 clamp so a mid-sync 0 still yields finite geometry.
    readonly property int geometryCount: Math.max(3, faceRepeater.count)
    // Raw delegate count, for the debug overlay and the sheet rules (ADR-024):
    // it can briefly be 0..2 mid-sync and then differs from geometryCount.
    // Faces themselves never branch on it for LOD — that is retired (ADR-023).
    readonly property int faceCount: faceRepeater.count
    // Sheet mode: 1-2 desktops lay their quads at the centre instead of on a
    // polygon perimeter. Permanent rule before the cylinder: with <3 desktops
    // the shape is ALWAYS the sheet, whatever the future Shape key says, and
    // with 0 faces mid-sync the sheet is just an empty group node (harmless).
    readonly property bool isSheet: faceRepeater.count < 3
    readonly property real angleTick: isSheet ? (faceRepeater.count === 2 ? 180 : 360) : 360 / geometryCount
    // Radius the distant state and the zoom clamps measure against. The sheet
    // has no apothem (its faceDistance is a gap, see below), so it measures
    // against half a face; with >=3 faces this is exactly faceDistance and the
    // polygon behaviour is untouched. It must NOT read faceDistance in sheet
    // mode: faceDistance derives from sheetGap which derives from viewRadius
    // (cycle).
    readonly property real viewRadius: isSheet ? 0.5 * faceSize.width : faceDistance
    // Half-separation of the two sheet quads. Proportional, not a fixed 1 px:
    // with a 24-bit depth buffer and clipNear 10, a 1-unit gap at a ~15k
    // maxRadius is 1-2 quantisation steps and can still Z-fight on 4K, so the
    // gap scales with the solid (0.5 % of viewRadius, floor 1 -> the two faces
    // are always >= 2 units apart). The order viewRadius -> sheetGap ->
    // faceDistance keeps the chain acyclic.
    readonly property real sheetGap: Math.max(1, viewRadius * 0.005)
    // Polygon: apothem + displacement (a hand-edited negative displacement can
    // make it NEGATIVE — see safeViewRadius). Sheet: the distance from centre
    // to the front quad, i.e. sheetGap itself, so the close state
    // (faceDistance + 0.5·h/tan(fov/2)) fills the screen off the actual face
    // plane (ADR-024).
    readonly property real faceDistance: isSheet ? sheetGap : 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement
    // viewRadius pinned positive: CubeFaceDisplacement < -apothem flips the
    // polygon apothem negative (pre-existing ADR-022 range), which fed
    // negative minRadius/maxRadius to the wheel and a negative distant radius
    // — the camera dived inside the solid and the cube vanished.
    readonly property real safeViewRadius: Math.max(1, viewRadius)

    function desktopAt(azimuth) {
        if (cube.isSheet) {
            // sheetDesktopAt answers -1 for a non-finite azimuth or a count
            // that cannot be a face index (0 mid-sync): hand back null, which
            // ScreenView.switchTo already ignores.
            const index = Constants.sheetDesktopAt(azimuth, faceRepeater.count);
            if (index < 0) {
                return null;
            }
            const face = faceRepeater.objectAt(index);
            return face !== null && face !== undefined ? face.desktop : null;
        }
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
        if (cube.isSheet) {
            // Face 1 of a two-sided sheet looks at 180 deg; a single face (or
            // no face mid-sync) always answers 0, which is inside the ±80
            // clamp of the one-desktop sheet.
            const number = desktop !== null && desktop !== undefined ? desktop.x11DesktopNumber : 1;
            return cube.faceCount === 2 && number >= 2 ? 180 : 0;
        }
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
            // Sheet (ADR-024): both quads at the centre, one facing each way
            // (0 deg / 180 deg), separated by +/-sheetGap in z (proportional,
            // >= 2 units total) so the near-coplanar triangles never Z-fight
            // at any depth-buffer precision. With a single desktop only the
            // front one exists; it keeps z = +sheetGap, the side the resting
            // camera looks at, so the close state and the two-desktop front
            // read identically.
            eulerRotation.y: cube.isSheet ? index * 180 : cube.angleTick * index
            position: {
                if (cube.isSheet) {
                    return Qt.vector3d(0, 0, index === 0 ? cube.sheetGap : -cube.sheetGap);
                }
                const transform = Qt.matrix4x4();
                transform.rotate(cube.angleTick * index, Qt.vector3d(0, 1, 0));
                return transform.times(Qt.vector3d(0, 0, cube.faceDistance));
            }
        }
    }
}
