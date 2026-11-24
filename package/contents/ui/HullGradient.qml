/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

import "constants.js" as Constants

// Hull gradient layer (Background == Gradient).
//
// Linear orientations are a plain Rectangle + Gradient, which QtQuick paints
// without any shader. Radial has no gradient primitive in QtQuick, so it is
// painted with QtQuick.Shapes: one ShapePath filled with a RadialGradient
// (centerX/centerY/centerRadius + stops, available since Qt 6).
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
        visible: root.gradientType !== Constants.BackgroundGradientType.Radial
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

    Shape {
        id: radialBackground
        anchors.fill: parent
        visible: root.gradientType === Constants.BackgroundGradientType.Radial

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: RadialGradient {
                centerX: radialBackground.width / 2
                centerY: radialBackground.height / 2
                // The focal point defaults to the origin (0,0), which pins the
                // gradient to the top-left corner instead of the centre; it is
                // set explicitly, and moved around the centre when the
                // gradient follows the cube (see focalDistance). Turning the
                // gradient itself would be invisible: a centred radial is
                // rotationally symmetric.
                focalX: radialBackground.width / 2 + root.focalDistance * Math.cos(root.rotationRadians)
                focalY: radialBackground.height / 2 + root.focalDistance * Math.sin(root.rotationRadians)
                // Corner distance from the centre is at most 0.707 * max(w, h);
                // 0.75 covers the whole screen with a small margin.
                centerRadius: Math.max(radialBackground.width, radialBackground.height) * 0.75
                GradientStop {
                    position: 0.0
                    color: root.firstColor
                }
                GradientStop {
                    position: root.stopPosition
                    color: root.secondColor
                }
                GradientStop {
                    position: 1.0
                    color: root.secondColor
                }
            }
            startX: 0
            startY: 0
            PathLine {
                x: radialBackground.width
                y: 0
            }
            PathLine {
                x: radialBackground.width
                y: radialBackground.height
            }
            PathLine {
                x: 0
                y: radialBackground.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }
}
