/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

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
            if (active) {
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
                let azimuth = (eulerRotation.y + azimuthDelta) % 360;

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
