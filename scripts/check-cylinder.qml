import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

// Directory of the real effect components: the harness below instantiates
// the SAME CylinderArcMesh.qml that Cube.qml loads at runtime (ADR-025), so
// a broken import, property name or binding fails this gate, not the cube.
import "../package/contents/ui"

import "../package/contents/ui/constants.js" as Constants

// Runs inside scripts/check-cylinder.py (offscreen QML engine, no window,
// no KWin). It exposes three real CylinderArcMesh holders — hence three
// real ProceduralMesh objects — for the closed cylinder (g = 0), the open
// one (g = 100) and the negative-displacement one (g clamps to 0), plus the
// parameters the generator used, so the Python side can validate the vertex
// data through the ProceduralMesh properties themselves
// (positions/normals/uv0s), exactly as the renderer would read them.
Item {
    id: root

    // A 4-desktop, 2560x1440 screen: the worst case for the seam.
    readonly property int faceCount: 4
    readonly property real faceWidth: 2560
    readonly property real faceHeight: 1440
    readonly property int segments: Constants.CYLINDER_SEGMENTS

    readonly property real radiusClosed: Constants.cylinderRadius(faceCount, faceWidth, 0)
    readonly property real radiusOpen: Constants.cylinderRadius(faceCount, faceWidth, 100)
    // Negative displacement must produce EXACTLY the closed-cylinder mesh:
    // the clamp is the contract (ADR-025), not a courtesy.
    readonly property real radiusNegative: Constants.cylinderRadius(faceCount, faceWidth, -500)

    CylinderArcMesh {
        id: closedArc
        faceWidth: root.faceWidth
        faceHeight: root.faceHeight
        radius: root.radiusClosed
    }

    CylinderArcMesh {
        id: openArc
        faceWidth: root.faceWidth
        faceHeight: root.faceHeight
        radius: root.radiusOpen
    }

    CylinderArcMesh {
        id: negativeArc
        faceWidth: root.faceWidth
        faceHeight: root.faceHeight
        radius: root.radiusNegative
    }

    // The curved segment (1-2 desktops, ADR-025): a fixed 120-degree arc,
    // R = 3W/2pi. Same generator, different radius — isometry must hold
    // there too (arc length = W, |position| = R exactly).
    readonly property real radiusSegment: Constants.cylinderArcRadius(faceWidth)

    CylinderArcMesh {
        id: segmentArc
        faceWidth: root.faceWidth
        faceHeight: root.faceHeight
        radius: root.radiusSegment
    }

    // The sharing pattern of Cube/CubeFace: TWO models referencing the SAME
    // geometry object (like the built-in "#Rectangle" behind every face).
    // If the reference itself were invalid this is where it shows.
    Model {
        id: modelA
        source: ""
        geometry: openArc.mesh
        materials: DefaultMaterial {
            lighting: DefaultMaterial.NoLighting
            cullMode: Material.NoCulling
        }
    }

    Model {
        id: modelB
        source: ""
        geometry: openArc.mesh
        materials: DefaultMaterial {
            lighting: DefaultMaterial.NoLighting
            cullMode: Material.NoCulling
        }
    }

    readonly property QtObject closedMesh: closedArc.mesh
    readonly property QtObject openMesh: openArc.mesh
    readonly property QtObject negativeMesh: negativeArc.mesh
    readonly property QtObject segmentMesh: segmentArc.mesh
    readonly property bool meshesAreGeometry: closedArc.mesh !== null && closedArc.mesh !== undefined
    readonly property bool modelsShareMesh: modelA.geometry === openArc.mesh && modelB.geometry === openArc.mesh
    // url properties compare as QUrl objects: an empty source is one whose
    // string form has no length (Qt demands an empty source when a custom
    // geometry is set — CubeFace relies on exactly that).
    readonly property bool modelsHaveSourceCleared: String(modelA.source).length === 0 && String(modelB.source).length === 0

    // QList<uint> has no Python converter in PySide6 (and a var JS array
    // arrives as an opaque QJSValue): hand the indexes over as JSON strings
    // (positions/normals/uv0s DO have QVector converters and are read
    // straight from the meshes).
    function indexCopy(mesh) {
        const out = [];
        const raw = mesh.indexes;
        for (let i = 0; i < raw.length; ++i) {
            out.push(raw[i]);
        }
        return JSON.stringify(out);
    }

    readonly property string closedIndexes: indexCopy(closedArc.mesh)
    readonly property string openIndexes: indexCopy(openArc.mesh)
    readonly property string negativeIndexes: indexCopy(negativeArc.mesh)
    readonly property string segmentIndexes: indexCopy(segmentArc.mesh)

    // The enum value arrives as an unconvertible Proxy in PySide6; compare
    // it where it is a plain number.
    readonly property bool meshesUseTriangles: closedArc.mesh.primitiveMode === ProceduralMesh.Triangles
        && openArc.mesh.primitiveMode === ProceduralMesh.Triangles
        && negativeArc.mesh.primitiveMode === ProceduralMesh.Triangles
        && segmentArc.mesh.primitiveMode === ProceduralMesh.Triangles

    // The segment must measure exactly 120 degrees (theta = W/R = 2pi/3):
    // the QML engine compares it where the number is plain.
    readonly property real segmentTheta: Constants.cylinderArcAngle(faceWidth, radiusSegment)
    readonly property real segmentThetaExpected: 2 * Math.PI / 3
}
