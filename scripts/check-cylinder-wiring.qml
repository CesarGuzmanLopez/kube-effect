import QtQuick
import QtQuick3D

// Directory of the real effect components: the harness below instantiates
// the SAME Cube.qml that ScreenView.qml builds at runtime (ADR-025 wiring
// gate) — not the loose CylinderArcMesh: what is proven here is the cable
// between the shape flags, the Loader-created mesh and the faces.
import "../package/contents/ui" as UI

// Runs inside scripts/check-cylinder-wiring.py (offscreen QML engine, no
// window, no View3D, no rendering: only the object tree and the property
// bindings are exercised). stubDesktopCount (context property) sizes the
// stub VirtualDesktopModel: 3 = drum, 2 = curved segment. The Python side
// moves cameraRadius across the 1.05 R margin and reads faceCullMode back,
// because PySide cannot convert the Material enum itself — the comparison
// values therefore leave this file as plain numbers.
Item {
    id: harness

    property real cameraRadius: 0

    // Material.CullMode as numbers, for the Python comparisons.
    readonly property int backCullValue: Material.BackFaceCulling
    readonly property int noneCullValue: Material.NoCulling

    UI.Cube {
        id: cube
        // Shape.Cylinder as the raw enum int: constants.shape() resolution
        // is checked in check-constants, this harness tests the wiring.
        shape: 1
        faceDisplacement: 100
        faceSize: Qt.size(2560, 1440)
        screenName: ""
        screenGeometry: Qt.rect(0, 0, 2560, 1440)
        // The live wiring ScreenView installs in production.
        cameraRadius: harness.cameraRadius
    }

    readonly property bool isCylinder: cube.isCylinder
    readonly property bool cylinderActive: cube.cylinderActive
    readonly property bool cylinderSegments: cube.cylinderSegments
    readonly property bool cylinderFaces: cube.cylinderFaces
    readonly property var cylinderMesh: cube.cylinderMesh
    readonly property real angleTick: cube.angleTick
    readonly property real faceDistance: cube.faceDistance
    readonly property real faceSizeWidth: cube.faceSize.width
    readonly property int faceCullMode: cube.faceCullMode
    readonly property int faceCount: cube.faceCount
}
