/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import "constants.js" as Constants

// Hull gradient layer (Background == Gradient).
//
// Linear orientations are a plain Rectangle + Gradient, which QtQuick paints
// without any shader. Radial has no gradient primitive in QtQuick, so it is
// painted with QtQuick.Shapes: one ShapePath filled with a RadialGradient
// (centerX/centerY/centerRadius + stops, available since Qt 6).
//
// Shapes is OPTIONAL (ADR-022): the radial lives in HullRadial.qml behind a
// Loader, exactly like the video behind HullVideo.qml for QtMultimedia. If the
// module is missing only that Loader errors; this layer falls back to the
// linear gradient and warns once. Before that, the import here made Shapes a
// hard dependency of the whole effect (no placeholder without it).
//
// Why Shapes and not a shader (ADR-013): a ShaderEffect would break the "QML
// only" contract, needs recompilation at KWin start and a GL context the
// effect does not own, while QtQuick.Shapes is a shipped QML module that just
// works in the offscreen view. Beyond centerRadius the last stop keeps
// painting, so the radius is chosen to cover the screen corners.
//
// Rotation (ADR-017, BackgroundGradientRotation): the layer can stay still
// (Fixed, default), turn with the cube (FollowCube) or against it
// (FollowCubeInverse). The linear layer is turned with a Rotation transform
// over an oversized Rectangle, so no item is created per frame; a centred
// radial gradient cannot be seen turning, so the radial moves its focal point
// over a small circle instead (see focalDistance).
Item {
    id: root

    property color firstColor: "#000000"
    property color secondColor: "#000000"
    property int gradientStop: 50
    property int gradientType: Constants.BackgroundGradientType.LinearVertical
    property int gradientRotation: Constants.BackgroundGradientRotation.Fixed
    // Camera yaw in degrees, pushed by ScreenView as a plain property: the
    // layer must not walk up the scene graph itself (no expensive bindings).
    property real yaw: 0

    // Angle the gradient turns with (ADR-017). 0 keeps the layer still, so
    // Fixed paints exactly what it painted before this option existed. A yaw
    // that jumps +180 -> -180 is harmless: the pattern is invariant under 360°.
    readonly property real rotationAngle: Constants.gradientRotationAngle(root.gradientRotation, root.yaw)
    readonly property real rotationRadians: root.rotationAngle * Math.PI / 180

    // One warning per session is enough: Loader.Error sticks anyway.
    property bool radialWarned: false

    // Linear layer: a Rectangle + Gradient turned with a Rotation transform
    // (never re-created per frame). Turning a w x h rectangle exposes corners,
    // so it is enlarged to the screen diagonal and centred on the hull. At
    // non-zero angles that oversizing costs fill rate: it covers more pixels
    // than the screen.
    readonly property real diagonal: Math.hypot(root.width, root.height)
    readonly property bool horizontalGradient: root.gradientType === Constants.BackgroundGradientType.LinearHorizontal
    // Gradient maths live in constants.js so they can be unit-tested
    // (scripts/check-constants): the visible span of the turned layer sets the
    // stop margin that keeps Fixed's look instead of showing only the middle
    // band.
    readonly property real stopMargin: Constants.gradientStopMargin(root.width, root.height, root.rotationAngle, root.horizontalGradient)

    // Radial: turning a centred radial gradient around its own centre is
    // visually null (it is rotationally symmetric), so FollowCube/Inverse move
    // the FOCAL point instead: it orbits the centre over a circle of
    // 0.25 * max(w, h). Fixed leaves it dead centre, as before, and so does an
    // unknown mode (hand-edited kwinrc) instead of off-centring the radial.
    readonly property bool gradientFollows: Constants.gradientFollows(root.gradientRotation)
    readonly property real focalDistance: root.gradientFollows ? 0.25 * Math.max(root.width, root.height) : 0

    // Same clamp as KConfigXT (0..100), applied by constants.js so it can be
    // unit-tested and both gradients share it: a hand-edited kwinrc value
    // cannot invert the gradient, and a non-finite one falls back to the schema
    // default (50) instead of poisoning the stop with NaN.
    readonly property real stopPosition: Constants.gradientStopPosition(root.gradientStop)

    Rectangle {
        id: linearBackground
        anchors.centerIn: parent
        width: root.diagonal
        height: root.diagonal
        // Also the fallback while/after a failed HullRadial load (no Shapes).
        visible: root.gradientType !== Constants.BackgroundGradientType.Radial || radialLoader.status === Loader.Error
        gradient: Gradient {
            orientation: root.horizontalGradient ? Gradient.Horizontal : Gradient.Vertical
            // Stops live in 0..1 of the oversized rectangle: the visible area is
            // the middle band [stopMargin, 1 - stopMargin], so the three stops
            // are mapped into it (outside the band the first/last colour stays).
            GradientStop {
                position: root.stopMargin
                color: root.firstColor
            }
            GradientStop {
                position: root.stopMargin + (1 - 2 * root.stopMargin) * root.stopPosition
                color: root.secondColor
            }
            GradientStop {
                position: 1 - root.stopMargin
                color: root.secondColor
            }
        }
        transform: Rotation {
            origin.x: linearBackground.width / 2
            origin.y: linearBackground.height / 2
            angle: root.rotationAngle
        }
    }

    Loader {
        id: radialLoader
        anchors.fill: parent
        // The radial type is the only Shapes consumer (ADR-022): loaded lazily
        // through its own file, never imported at this level, because a failed
        // top-level import would take the whole effect down with it. On
        // Loader.Error (module missing) linearBackground stays visible and
        // paints the linear gradient instead, warning once.
        active: root.gradientType === Constants.BackgroundGradientType.Radial
        source: "HullRadial.qml"
        onStatusChanged: {
            if (status === Loader.Error && !root.radialWarned) {
                root.radialWarned = true;
                console.warn("kube-effect: QtQuick.Shapes unavailable; painting the linear gradient instead of the radial one");
            }
        }
        onLoaded: {
            // Bindings on the created item (the video loader's pattern): the
            // KCM can change colours or rotation while the effect is loaded.
            item.firstColor = Qt.binding(() => root.firstColor);
            item.secondColor = Qt.binding(() => root.secondColor);
            item.stopPosition = Qt.binding(() => root.stopPosition);
            item.focalDistance = Qt.binding(() => root.focalDistance);
            item.rotationRadians = Qt.binding(() => root.rotationRadians);
        }
    }
}
