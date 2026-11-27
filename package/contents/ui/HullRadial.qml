/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Radial hull gradient (Background == Gradient, type Radial).
//
// This is the ONLY file of the effect importing QtQuick.Shapes, and it lives in
// its own file on purpose (ADR-022, same isolation pattern as HullVideo.qml for
// QtMultimedia): ScreenView's HullGradient loads it through a Loader, so on a
// system without the module only THIS item fails and the loader falls back to
// the linear gradient. A top-level "import QtQuick.Shapes" in HullGradient made
// Shapes a hard dependency of the WHOLE effect: without it not even the
// placeholder was painted.
//
// QtQuick has no radial gradient primitive, so this is one ShapePath filled
// with a RadialGradient (centerX/centerY/centerRadius + stops, Qt 6.12). Beyond
// centerRadius the last stop keeps painting, so the radius covers the screen
// corners. Turning a centred radial is visually null (rotational symmetry), so
// FollowCube/Inverse move the FOCAL point over a circle instead (focalDistance;
// ADR-017).
import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property color firstColor: "#000000"
  property color secondColor: "#000000"
  // Second stop position in 0..1, already clamped by HullGradient through
  // constants.js (unit-tested there; this item takes the final value).
  property real stopPosition: 0.5
  // Focal offset from the centre in px and the turn angle in radians, pushed
  // by HullGradient (no scene-graph walking from here).
  property real focalDistance: 0
  property real rotationRadians: 0

  Shape {
    anchors.fill: parent
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: RadialGradient {
        centerX: root.width / 2
        centerY: root.height / 2
        // The focal point defaults to the origin (0,0), which pins the
        // gradient to the top-left corner instead of the centre; it is
        // set explicitly, and moved around the centre when the
        // gradient follows the cube (see the header).
        focalX: root.width / 2 + root.focalDistance * Math.cos(root.rotationRadians)
        focalY: root.height / 2 + root.focalDistance * Math.sin(root.rotationRadians)
        // Corner distance from the centre is at most 0.707 * max(w, h);
        // 0.75 covers the whole screen with a small margin.
        centerRadius: Math.max(root.width, root.height) * 0.75
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
        x: root.width
        y: 0
      }
      PathLine {
        x: root.width
        y: root.height
      }
      PathLine {
        x: 0
        y: root.height
      }
      PathLine {
        x: 0
        y: 0
      }
    }
  }
}
