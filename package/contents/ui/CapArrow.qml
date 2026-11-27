/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Orientation marker painted on the caps (CapContent Arrow, ADR-027
// amendment 2 — the schema default).
//
// WHY THIS EXISTS: a uniform-colour cap cannot show orientation, so the user
// cannot tell "the cap is turned/mirrored" from "the cap paints over the
// faces" (the exact confusion of the overlap report). One asymmetric marker
// makes rotation and mirror readable at a glance — and it is what makes the
// bottom cap's flip testable with pixels (cap pixel gate, removed for cost (doc/trucos-aprendidos.md, section P)
// measures the magenta centroid of each cap against its mirror).
//
// SHAPES IS OPTIONAL (ADR-022 pattern, like HullRadial.qml for the radial
// gradient): this is the ONLY cap file importing QtQuick.Shapes, Cap.qml
// loads it through a Loader, and on a system without the module only this
// item fails — the cap falls back to plain CapColor and warns ONCE. The
// magenta quadrant is a plain Rectangle on purpose: it needs no Shapes.
//
// THE MARKER IS DELIBERATELY THREE-PART (measured classes, matching the
// gate's pixel classifier):
//   * background  = CapColor          (the cap border stays readable)
//   * arrow       = CYAN  (#00ffff)   pointing at the item's TOP edge
//   * corner box  = MAGENTA (#ff00ff) at the item's TOP-LEFT
// With the arrow alone a mirror can look like a rotation (the isosceles
// arrow is left-right symmetric); the corner box breaks that ambiguity —
// a mirror moves it to the OTHER x-side, a rotation moves it to another
// corner. The colours are the gate's classes "C" and "M".
//
// UV CONVENTION (MEASURED against the real ProceduralMesh by the arrow
// scenario of cap pixel gate, removed for cost (doc/trucos-aprendidos.md, section P), not assumed): the mesh maps
// u = 0.5 + x/(2 rho), v = 0.5 + z/(2 rho) over the item's square, and the
// grab places the item's TOP edge at v -> 1 = LOCAL +z = the azimuth of
// face 0 (desktop 1). So the arrow "up" means "toward face 0": both caps
// always point at the desktop-1 face, and turning the solid visibly turns
// the arrow with it. (The gate's numbers: quadrant of the rotated bottom
// cap at (534.2, 272.5) against the unrotated twin at (265.8, 272.5) - the
// SAME row, x mirrored about the arrow axis within 0.6 px: the Z flip
// mirrors u and preserves v, which is why the arrow keeps its azimuth
// while the corner marker changes sides.)
import QtQuick
import QtQuick.Shapes

Item {
  id: capArrow

  // Solid background so the cap border reads against the hull (the KCM
  // "Color de las tapas" value, bound by Cap.qml).
  property color color1: "#1b3fd8"

  Rectangle {
    anchors.fill: parent
    color: capArrow.color1
  }

  // Corner box (handedness marker): a quadrant, not a centred shape, so a
  // horizontal mirror and a 180 rotation land it in DIFFERENT places.
  Rectangle {
    x: 0
    y: 0
    width: capArrow.width * 0.42
    height: capArrow.height * 0.42
    color: "#ff00ff"
  }

  // The arrow: head at the item's top edge, tail centred at the bottom.
  // One closed ShapePath (shaft + barbs), cyan.
  Shape {
    anchors.fill: parent
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: "#00ffff"
      fillRule: ShapePath.WindingFill
      startX: capArrow.width * 0.5
      startY: capArrow.height * 0.08
      PathLine {
        x: capArrow.width * 0.8
        y: capArrow.height * 0.44
      }
      PathLine {
        x: capArrow.width * 0.62
        y: capArrow.height * 0.44
      }
      PathLine {
        x: capArrow.width * 0.62
        y: capArrow.height * 0.82
      }
      PathLine {
        x: capArrow.width * 0.38
        y: capArrow.height * 0.82
      }
      PathLine {
        x: capArrow.width * 0.38
        y: capArrow.height * 0.44
      }
      PathLine {
        x: capArrow.width * 0.2
        y: capArrow.height * 0.44
      }
      PathLine {
        x: capArrow.width * 0.5
        y: capArrow.height * 0.08
      }
    }
  }
}
