/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The window-slab box mesh (ADR-028 fourth amendment, final design after
// the bevel was measured 2026-11-28).
//
// ONE ProceduralMesh, a closed unit box (100 x 100 x 100 — the "#Rectangle"
// pixel convention: per-window dimensions and the effective thickness
// arrive through the Model scale, never through the vertices) with TWO
// material subsets: indexes 0..5 are the FRONT face (subset 0 -> the
// textured WindowThumbnail material, proven #Rectangle UVs from
// layerGeometry.slabVertices), the next 24 are the FOUR SIDES (subset 1 ->
// the uniform edge colour) and the last 6 are the BACK (subset 2 -> the
// SAME shared Texture, mirrored by per-position UVs: from behind the box
// reads like the flat NoCulling quad - the same window, reversed - not a
// dark slab). The subset order IS
// the Model.materials order (the documented ProceduralMesh rule), so
// "which index is the front" is not a guess — it is built here: the front
// is subset 0 by construction. (The first attempt assumed
// Model.customMaterials[0..5] = front/right/back/...; verified against the
// live Qt 6.12 engine: customMaterials is not a property of Model at all,
// and the built-in #Cube is a single subset.)
//
// Like CylinderArcMesh.qml and CapMesh.qml this is one of the ONLY files
// importing QtQuick3D.Helpers, reached through a Loader source URL
// compiled at RUNTIME: a system without the module fails only this Loader
// — WindowLayers.slabBox stays null, every layer keeps the flat
// #Rectangle (thickness degrades to nothing) and the cube still works.
// The root is a zero-size holder Item because a Loader can only load
// Item-based components; the geometry it exposes is a plain ProceduralMesh
// referenced by every slab Model (one shared mesh per face component, the
// arc pattern).
//
// Culling note (the measured bug): the box is rendered with
// BackFaceCulling on both materials. With NoCulling the transparent
// shadow margins of the thumbnail (pixels the Mask front discards under
// the cutoff) showed the box's own black BACK/inner side — a giant bezel
// around every window. A closed, culled box has no inner surfaces to
// leak: those margin pixels fall through to the plate/interior exactly as
// in the flat model.

import QtQuick
import QtQuick3D.Helpers

import "layerGeometry.js" as LayerGeometry

Item {
  id: slabHolder

  visible: false
  width: 0
  height: 0

  // The unit box: rebuilt never (the numbers are constants - the windows
  // differ only in the Model scale).
  readonly property var box: LayerGeometry.slabVertices(100, 100, 100)

  property ProceduralMesh mesh: ProceduralMesh {
    primitiveMode: ProceduralMesh.Triangles
    positions: slabHolder.box.positions
    normals: slabHolder.box.normals
    uv0s: slabHolder.box.uvs
    indexes: slabHolder.box.indexes
    subsets: [
      // Three subsets, split of the ONE indexes list; the order IS
      // Model.materials (the documented ProceduralMesh rule), so the
      // FRONT index is constructed, never guessed: 0 = front (the
      // textured face), 1 = the FOUR SIDES (the lit edge colour - and
      // NOT the back any more), 2 = the BACK.
      // The back is a full textured subset: seen from behind the box
      // must read like the flat NoCulling quad does today - the same
      // window MIRRORED ("como la misma pantalla pero al reves"), not a
      // dark slab (measured with the first two-subset build).
      ProceduralMeshSubset {
        offset: 0
        count: slabHolder.box.frontCount
        name: "front"
      },
      ProceduralMeshSubset {
        offset: slabHolder.box.frontCount
        count: slabHolder.box.sideCount
        name: "edges"
      },
      ProceduralMeshSubset {
        offset: slabHolder.box.frontCount + slabHolder.box.sideCount
        count: slabHolder.box.backCount
        name: "back"
      }
    ]
  }
}
