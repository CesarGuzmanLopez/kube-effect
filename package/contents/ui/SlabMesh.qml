/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The window-slab box mesh (ADR-028 fourth amendment).
//
// ONE shared ProceduralMesh (like the arc and the caps): a closed unit box
// (100 x 100 x 100 - the "#Rectangle" pixel convention; per-window size and
// the EFFECTIVE thickness arrive through the Model scale, never through
// vertices) with THREE material subsets splitting the one indexes list, so
// their order IS the Model.materials order:
//   subset 0 = FRONT   (indexes 0..5)   -> materials[0]: textured
//   subset 1 = BACK    (indexes 6..11)  -> materials[1]: the SAME textured
//             material object - the glass-like mirror comes from the
//             per-position UVs and the viewpoint, never from a second
//             capture (a coloured back read as a dark slab - measured
//             2026-11-28 - which is why the back left the sides subset)
//   subset 2 = SIDES   (indexes 12..35) -> materials[2]: the lit edge
//             colour
// "Which index is the front" is built here, not guessed: Model has NO
// customMaterials in Qt 6.12 (verified against the live engine) and the
// built-in #Cube is a single subset; ProceduralMeshSubset only carries
// offset/count/name (its boundsMin/boundsMax once made this file a
// permanent Loader.Error - also measured).
//
// The frame's sub-rect of the grab texture lives on the per-layer Texture
// (positionU/scaleU/positionV/scaleV - the documented Texture coordinate
// transform, bottom-left origin like these UVs), NOT here: the mesh stays
// static and shared, no per-window rebuilds at all.
//
// Like CylinderArcMesh.qml and CapMesh.qml this is one of the ONLY files
// importing QtQuick3D.Helpers, reached through a Loader source URL
// compiled at RUNTIME: a system without the module fails only this Loader
// - slabBox stays null and every layer keeps the flat built-in #Rectangle
// (the thickness degrades, the effect survives). The root is a zero-size
// holder Item because a Loader can only load Item-based components.
//
// Culling (see WindowLayers): all three materials are BackFaceCulling on
// the box; from outside you see the textured front (or, from behind, the
// mirrored back), never the box's inner walls - the NoCulling variant
// showed the black interior through the thumbnail's transparent shadow
// margins (the measured bezel, 2026-11-28).

import QtQuick
import QtQuick3D.Helpers

import "layerGeometry.js" as LayerGeometry

Item {
  id: slabHolder

  visible: false
  width: 0
  height: 0

  // The unit box: rebuilt never (the numbers are constants).
  readonly property var box: LayerGeometry.slabVertices(100, 100, 100)

  property ProceduralMesh mesh: ProceduralMesh {
    primitiveMode: ProceduralMesh.Triangles
    positions: slabHolder.box.positions
    normals: slabHolder.box.normals
    uv0s: slabHolder.box.uvs
    indexes: slabHolder.box.indexes
    subsets: [
      ProceduralMeshSubset {
        offset: 0
        count: slabHolder.box.frontCount
        name: "front"
      },
      ProceduralMeshSubset {
        offset: slabHolder.box.frontCount
        count: slabHolder.box.backCount
        name: "back"
      },
      ProceduralMeshSubset {
        offset: slabHolder.box.frontCount + slabHolder.box.backCount
        count: slabHolder.box.sideCount
        name: "sides"
      }
    ]
  }
}
