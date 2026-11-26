import QtQuick
import QtQuick3D

// The REAL effect components, same trick as check-cylinder-wiring.qml.
import "../package/contents/ui" as UI

// Render harness for scripts/check-cylinder-overlap.py (ADR-026).
//
// It instantiates the REAL Cube.qml (Shape = Cylinder, three stub desktops
// whose DesktopView carries one flat colour per face: red/green/blue, plus a
// magenta clear colour for the hull) inside a View3D, exactly like KWin's
// SceneView would: the stub org.kde.kwin module and the warm-up/handler
// pattern are the proven ones of check-video-dome.py. Cube.qml itself is NOT
// modified and not wrapped by ScreenView.qml — the overlap lives in the
// faces' material and placement, so the gate exercises Cube directly.
//
// What the Python side checks, per scenario:
//   * pixels: the near face always wins its own footprint (no far face
//     painted over it at rest or mid-turn), and the face texture's alpha
//     holes stay see-through at rest (a Mask/Blend material; an Opaque one
//     would paint them black);
//   * structure: the `snapshot` property below — one entry per face with its
//     node position (the ADR-026 sort centroid: hypot(x, z) == R, pairwise
//     distinct) and its material state (alphaMode by the faceOpacity
//     threshold, opacity bound through). snapshotTick exists to force the
//     binding to re-evaluate after each setProperty — QML does not track
//     property writes through a `var` list of children.
Item {
    id: harness
    width: 640
    height: 360

    // Set by the Python scenario before the grab.
    property real yaw: 0
    property real faceOpacity: 1
    // Constants.Shape int: 1 = Cylinder (the rest branch is Mask ONLY with
    // the arc mesh), 0 = Polygon reference — Blend always, virgin ADR-023
    // look, distinct positions already since ADR-022.
    property int shape: 1
    property int snapshotTick: 0

    // Camera on the +Z axis at the runtime close-state distance for the
    // CYLINDER setup (drum radius R plus the term that makes H fill the
    // screen at 60 deg vertical FOV). Deterministic, pitch 0, so the front
    // face's footprint windows are stable across runs. The polygon at the
    // same distance shows a smaller solid (apothem+g < R) whose front quad
    // still spans the sampled windows — the assertions only look inside it.
    readonly property real drumRadius: 3 * (640 + 100) / (2 * Math.PI)
    readonly property real camRadius: drumRadius + 0.5 * 360 / Math.tan(0.5 * 60 * Math.PI / 180)

    View3D {
        anchors.fill: parent
        renderMode: View3D.Offscreen

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "#ff00ff"
        }

        camera: PerspectiveCamera {
            fieldOfView: 60
            position: Qt.vector3d(0, 0, harness.camRadius)
        }

        UI.Cube {
            id: cube
            // Shape as the raw int (resolution itself is check-constants'
            // business); here it is the wiring + pixels.
            shape: harness.shape
            faceDisplacement: 100
            faceSize: Qt.size(640, 360)
            screenName: ""
            screenGeometry: Qt.rect(0, 0, 640, 360)
            faceOpacity: harness.faceOpacity
            eulerRotation.y: harness.yaw
        }
    }

    // JSON: [{x, z, mask, blend, opaque, hasAlphaMode, opacity}, ...] one per
    // face Model. mask/blend compare the enum SYMBOLICALLY inside QML (the
    // ints differ across Qt versions and must never travel raw to Python).
    property string snapshot: "{}"

    function collectFaces(node, faces) {
        // The Repeater3D parents its delegates UNDER itself (a Node), so the
        // walk goes through the whole subtree; a face Model is any node with
        // materials and a position.
        if (node === null || node === undefined || node.children === undefined) {
            return;
        }
        for (let i = 0; i < node.children.length; ++i) {
            const child = node.children[i];
            if (child === null || child === undefined) {
                continue;
            }
            if (child.materials !== undefined && child.position !== undefined && child.geometry !== undefined) {
                const material = child.materials.length > 0 ? child.materials[0] : null;
                if (material !== null && material !== undefined && material.opacity !== undefined) {
                    faces.push({
                        x: child.position.x,
                        z: child.position.z,
                        mask: material.alphaMode === PrincipledMaterial.Mask,
                        blend: material.alphaMode === PrincipledMaterial.Blend,
                        hasAlphaMode: material.alphaMode !== undefined,
                        opacity: material.opacity
                    });
                }
            }
            collectFaces(child, faces);
        }
    }

    function buildSnapshot() {
        const faces = [];
        collectFaces(cube, faces);
        return JSON.stringify({
            faces: faces,
            drumRadius: harness.drumRadius,
            faceCount: cube.faceCount,
            cylinderActive: cube.cylinderActive,
            hasMesh: cube.cylinderMesh !== null
        });
    }

    onSnapshotTickChanged: snapshot = buildSnapshot()
    Component.onCompleted: snapshot = buildSnapshot()
}
