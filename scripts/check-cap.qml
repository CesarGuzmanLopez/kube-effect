import QtQuick
import QtQuick3D
import QtQuick3D.Helpers

// Directory of the real effect components: the harness below instantiates
// the SAME CapMesh.qml that Cube.qml loads at runtime (ADR-027), so a
// broken import, property name or binding fails this gate, not the cube.
import "../package/contents/ui"

import "../package/contents/ui/constants.js" as Constants

// Runs inside scripts/check-cap.py (offscreen QML engine, no window, no
// KWin). It exposes the real ProceduralMesh data for both cap shapes and,
// for the polygon, for BOTH ADR-027 regimes: the face-corner ring with gap
// chords (displacement > 0, the case that used to poke) and the inscribed
// N-gon (the same apothem below the no-displacement apothem of 5 sides),
// plus the disc (drum on) — and the two Models that share ONE mesh the way
// Cube's top/bottom caps do, so the Python side validates vertex data
// exactly as the renderer would read it.
Item {
    id: root

    // A 4-desktop screen: geometryCount = 4, faceDistance = W/2/tan(pi/4)
    // + g (the polygon apothem plus the user's displacement) and
    // R = 4(W+g)/2pi for the drum. With g = 100 the apothem 1380 EXCEEDS
    // W/2/tan(pi/4) = 1280: this is the face-corner regime (2N vertices,
    // ADR-027 amendment) — the exact screen state that used to poke. The
    // inscribed side is exercised at 5 sides, where 1380 < 1761.7 =
    // W/2/tan(pi/5) is the no-displacement apothem (d < 0).
    readonly property int sides: 4
    readonly property int inscribedSides: 5
    readonly property real faceWidth: 2560
    readonly property real faceHeight: 1440
    readonly property real displacement: 100
    readonly property real halfHeight: faceHeight / 2
    readonly property real apothem: faceWidth / 2 / Math.tan(Math.PI / sides) + displacement
    readonly property real radius: Constants.cylinderRadius(sides, faceWidth, displacement)
    readonly property int segments: Constants.CYLINDER_SEGMENTS

    // Polygon cap with separated faces (Shape = Polygon, g > 0): the ring
    // must run the FACE CORNERS (2N vertices) closed by straight chords.
    CapMesh {
        id: polygonCap
        sides: root.sides
        apothem: root.apothem
        faceWidth: root.faceWidth
        radius: root.radius
        halfHeight: root.halfHeight
        useDisc: false
    }

    // Polygon cap at 5 sides with the same apothem: the displacement is
    // effectively negative (1380 < 1761.7), so the ring must collapse to
    // the inscribed N-gon (N vertices) — the untouched look of the cube.
    CapMesh {
        id: inscribedCap
        sides: root.inscribedSides
        apothem: root.apothem
        faceWidth: root.faceWidth
        radius: root.radius
        halfHeight: root.halfHeight
        useDisc: false
    }

    // faceWidth 0 is degenerate for the polygon branch (a face of no width
    // has no corners to seal): empty arrays, never a plane of tips.
    CapMesh {
        id: zeroWidthCap
        sides: root.sides
        apothem: root.apothem
        faceWidth: 0
        radius: root.radius
        halfHeight: root.halfHeight
        useDisc: false
    }

    // Disc cap (Shape = Cylinder at any count, the three-slot drum included:
    // same disc, N = 3 radius).
    CapMesh {
        id: discCap
        sides: root.sides
        apothem: root.apothem
        radius: root.radius
        halfHeight: root.halfHeight
        useDisc: true
    }

    // Degenerate inputs (mid-sync faceSize, or a displacement past the
    // apothem): the generator must answer EMPTY arrays, never NaN vertices.
    CapMesh {
        id: brokenCap
        sides: 2
        apothem: -5
        faceWidth: root.faceWidth
        radius: 0
        halfHeight: 0
        useDisc: false
    }
    CapMesh {
        id: brokenDisc
        sides: root.sides
        apothem: root.apothem
        radius: 0
        halfHeight: root.halfHeight
        useDisc: true
    }

    // The sharing pattern of Cube: the top and bottom Cap Models reference
    // the SAME geometry (ADR-027: one mesh, the bottom node rotated 180 deg
    // — the rotation belongs to the Model, never to a second mesh).
    Model {
        id: topCapModel
        source: ""
        geometry: polygonCap.mesh
        position: Qt.vector3d(0, root.halfHeight, 0)
        materials: DefaultMaterial {
            lighting: DefaultMaterial.NoLighting
            cullMode: Material.NoCulling
        }
    }
    Model {
        id: bottomCapModel
        source: ""
        geometry: polygonCap.mesh
        position: Qt.vector3d(0, -root.halfHeight, 0)
        eulerRotation.z: 180
        materials: DefaultMaterial {
            lighting: DefaultMaterial.NoLighting
            cullMode: Material.NoCulling
        }
    }

    readonly property QtObject polygonMesh: polygonCap.mesh
    readonly property QtObject inscribedMesh: inscribedCap.mesh
    readonly property QtObject discMesh: discCap.mesh
    readonly property QtObject brokenMesh: brokenCap.mesh
    readonly property QtObject brokenDiscMesh: brokenDisc.mesh
    readonly property bool modelsShareMesh: topCapModel.geometry === polygonCap.mesh && bottomCapModel.geometry === polygonCap.mesh
    // An empty source is one whose string form has no length (Qt demands it
    // with a custom geometry — the CubeFace requirement, reused here).
    readonly property bool modelsHaveSourceCleared: String(topCapModel.source).length === 0 && String(bottomCapModel.source).length === 0
    readonly property int brokenVertexCount: brokenCap.mesh.positions.length
    readonly property int brokenDiscVertexCount: brokenDisc.mesh.positions.length
    readonly property int zeroWidthVertexCount: zeroWidthCap.mesh.positions.length

    // The real Cap component (Model + PrincipledMaterial + 2D surface): the
    // same two Models Cube.qml places at y = +/- halfHeight, one rotated 180
    // about Z (ADR-027). Instantiating them here catches a broken import, a bad
    // material property or a dead HullGradient binding in this gate, and the
    // image fallback signal is exercised: content Image with an empty source
    // must report ONCE (callLater absorbs the same-pass binding order), the
    // gradient cap never reports.
    property int unavailableReports: 0
    Cap {
        id: capTopInstance
        mesh: root.polygonMesh
        content: Constants.CapContent.Image
        imageSource: ""
        position: Qt.vector3d(0, root.halfHeight, 0)
        onImageUnavailable: root.unavailableReports += 1
    }
    Cap {
        id: capBottomInstance
        mesh: root.polygonMesh
        content: Constants.CapContent.Gradient
        position: Qt.vector3d(0, -root.halfHeight, 0)
        eulerRotation.z: 180
        onImageUnavailable: root.unavailableReports += 1
    }
    readonly property bool capsShareGeometry: capTopInstance.geometry === capBottomInstance.geometry && capTopInstance.geometry === polygonCap.mesh
    readonly property bool capsHaveOwnCentroids: capTopInstance.position.y > 0 && capBottomInstance.position.y < 0

    // QList<uint> has no Python converter in PySide6 (and a var JS array
    // arrives as an opaque QJSValue): hand the indexes over as JSON strings.
    function indexCopy(mesh) {
        const out = [];
        const raw = mesh.indexes;
        for (let i = 0; i < raw.length; ++i) {
            out.push(raw[i]);
        }
        return JSON.stringify(out);
    }

    readonly property string polygonIndexes: indexCopy(polygonCap.mesh)
    readonly property string inscribedIndexes: indexCopy(inscribedCap.mesh)
    readonly property string discIndexes: indexCopy(discCap.mesh)

    // The enum value arrives as an unconvertible Proxy in PySide6; compare
    // it where it is a plain number.
    readonly property bool meshesUseTriangles: polygonCap.mesh.primitiveMode === ProceduralMesh.Triangles && discCap.mesh.primitiveMode === ProceduralMesh.Triangles
}
