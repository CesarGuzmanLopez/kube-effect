import QtQuick
import QtQuick3D

import "../package/contents/ui/constants.js" as Constants

// Directory of the real effect components: the harness below instantiates
// the SAME Cube.qml that ScreenView.qml builds at runtime (ADR-025 wiring
// gate) — not the loose CylinderArcMesh: what is proven here is the cable
// between the shape flags, the Loader-created mesh and the faces.
import "../package/contents/ui" as UI

// Runs inside scripts/check-cylinder-wiring.py (offscreen QML engine, no
// window, no View3D, no rendering: only the object tree and the property
// bindings are exercised). stubDesktopCount (context property) sizes the
// stub VirtualDesktopModel: 3 = closed drum, 1-2 = the THREE-SLOT drum
// (ADR-025 pt.11 re-rectified: R = 3(W + g)/2pi with the user gap, tick
// grid 120, empty slots have no delegate, turn range OPEN). The Python
// side moves cameraRadius across the 1.05 R margin and reads faceCullMode
// back, because PySide cannot convert the Material enum itself — the
// comparison values therefore leave this file as plain numbers.
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
    readonly property var cylinderMesh: cube.cylinderMesh
    // The range the camera would actually get for this live shape/count/mesh
    // (ADR-026 routing through the three-slot design: cylinder WITH mesh is
    // open at every count, the 1-2 band caps are retired).
    readonly property string cylRangeJson: JSON.stringify(Constants.azimuthRangeFor(1, cube.faceCount, cube.cylinderMesh !== null))
    readonly property real angleTick: cube.angleTick
    readonly property real faceDistance: cube.faceDistance
    // The radius chain the camera clamps and the states measure against
    // (ADR-026b: with the drum in effect viewRadius must BE R — never the
    // sheet's gap — or the wheel traps the camera inside the solid).
    readonly property real viewRadius: cube.viewRadius
    readonly property real sheetGap: cube.sheetGap
    readonly property real safeViewRadius: cube.safeViewRadius
    readonly property real cylinderRadiusValue: cube.cylinderRadius
    readonly property real faceSizeHeight: cube.faceSize.height
    readonly property real faceSizeWidth: cube.faceSize.width
    readonly property int faceCullMode: cube.faceCullMode
    readonly property int faceCount: cube.faceCount
    // Slot-grid azimuths straight from the live Cube (ADR-025 pt.11 three-slot
    // design): slot 0 answers 0 (the face is ALWAYS front-facing when the
    // effect opens) and the empty slot 1 sits on the same grid at 120.
    readonly property real slotZeroAzimuth: cube.faceAzimuth(0)
    readonly property real slotOneAzimuth: cube.faceAzimuth(1)
}
