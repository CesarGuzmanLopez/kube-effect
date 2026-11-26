/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

import "constants.js" as Constants

Item {
    id: root

    readonly property bool busy: status.useMouse

    required property Camera camera

    property quaternion rotation: Quaternion.fromEulerAngles(0, 0, 0)
    property real radius: 2000

    property real xSpeed: 10
    property real ySpeed: 10

    property bool xInvert: false
    property bool yInvert: false

    // Zoom bounds (ADR-022): unclamped wheel steps drove radius under
    // clipNear, where the faces disappear, or off to absurd distances. The
    // defaults are harmless; ScreenView links them to cube.faceDistance so the
    // limits follow the actual solid size. Implicit width/height were dropped:
    // ScreenView anchors this controller, so nothing ever read them.
    property real minRadius: 100
    property real maxRadius: 20000

    // Turn range (ADR-024/ADR-026): ScreenView links these to the live
    // shape and count via Constants.azimuthRangeFor — null/null (no
    // limit) for the two-sided sheet, the polygon and EVERY cylinder with
    // the arc mesh (drum at 3+, three-slot drum at 1-2: free wrap, the
    // capped band was retired by the user); [-80, 80] only for the flat
    // sheet with one desktop (the mirrored back of the single quad must
    // never face the camera) — which also covers the Cylinder-without-
    // mesh fallback. The drag path below clamps the raw sum directly
    // between min and max (no wrap, no normalization — a pull that
    // crossed a bound would otherwise teleport the view); arrows and
    // states clamp through Constants.clampAzimuthRange where they build
    // their target.
    property var azimuthMin: null
    property var azimuthMax: null

    onRotationChanged: root.updateCamera()
    onRadiusChanged: root.updateCamera()

    DragHandler {
        id: dragHandler
        target: null
        acceptedModifiers: Qt.NoModifier
        onCentroidChanged: {
            mouseMoved(Qt.vector2d(centroid.position.x, centroid.position.y), false);
        }

        onActiveChanged: {
            if (dragHandler.active) {
                mousePressed(Qt.vector2d(centroid.position.x, centroid.position.y));
            } else {
                mouseReleased(Qt.vector2d(centroid.position.x, centroid.position.y));
            }
        }
    }

    WheelHandler {
        id: wheelHandler
        orientation: Qt.Vertical
        target: null
        onWheel: event => {
            let delta = (event.inverted ? -1 : 1) * event.angleDelta.y * 0.01;
            // Relative step, clamped (ADR-022): the zoom is proportional, so
            // without limits a few frames of a fast wheel crossed clipNear.
            root.radius = Math.max(root.minRadius, Math.min(root.maxRadius, root.radius + root.radius * 0.1 * delta));
        }
    }

    TapHandler {
        onTapped: root.forceActiveFocus()
    }

    function mousePressed(newPos) {
        root.forceActiveFocus();
        status.currentPos = newPos;
        status.lastPos = newPos;
        status.useMouse = true;
    }

    function mouseReleased(newPos) {
        status.useMouse = false;
    }

    function mouseMoved(newPos: vector2d) {
        status.currentPos = newPos;
    }

    function updateCamera() {
        const eulerRotation = root.rotation.toEulerAngles();
        const theta = (eulerRotation.x + 90) * Math.PI / 180;
        const phi = eulerRotation.y * Math.PI / 180;

        camera.position = Qt.vector3d(radius * Math.sin(phi) * Math.sin(theta), radius * Math.cos(theta), radius * Math.cos(phi) * Math.sin(theta));
        camera.rotation = root.rotation;
    }

    FrameAnimation {
        running: root.busy
        onTriggered: status.processInput(frameTime)
    }

    QtObject {
        id: status

        property bool useMouse: false

        property real minElevation: -30
        property real maxElevation: 30

        property vector2d lastPos: Qt.vector2d(0, 0)
        property vector2d currentPos: Qt.vector2d(0, 0)

        function processInput(dt) {
            if (useMouse) {
                const eulerRotation = root.rotation.toEulerAngles();

                const pixelDelta = Qt.vector2d(lastPos.x - currentPos.x, lastPos.y - currentPos.y);
                lastPos = currentPos;

                let azimuthDelta = pixelDelta.x * xSpeed * dt;
                if (xInvert) {
                    azimuthDelta = -azimuthDelta;
                }
                let azimuth;
                // != null catches undefined too (a not-yet-evaluated binding
                // must read as "no range", never crash the drag branch).
                if (root.azimuthMin != null && root.azimuthMax != null) {
                    // Limited shape (ADR-024/ADR-025): the drag NEVER wraps,
                    // so clamp the raw sum between the bounds instead of
                    // reducing it modulo 360 first — a hard pull crossing a
                    // bound would otherwise reappear on the other side and
                    // teleport the view. No clampAzimuthRange here either:
                    // only arrows and states normalize through that helper
                    // (the helper handles asymmetric bounds generically even
                    // though today's only limited range, the sheet's, is
                    // symmetric).
                    const target = eulerRotation.y + azimuthDelta;
                    azimuth = Math.min(Number(root.azimuthMax), Math.max(Number(root.azimuthMin), target));
                } else {
                    // Two-sided sheet, drum and polygon: full turn, wrap kept.
                    azimuth = (eulerRotation.y + azimuthDelta) % 360;
                }

                let elevationDelta = pixelDelta.y * ySpeed * dt;
                if (yInvert) {
                    elevationDelta = -elevationDelta;
                }

                let elevation = eulerRotation.x + elevationDelta;
                if (elevation < minElevation) {
                    elevation = minElevation;
                } else if (elevation > maxElevation) {
                    elevation = maxElevation;
                }

                root.rotation = Quaternion.fromEulerAngles(elevation, azimuth, 0);
            }
        }
    }
}
