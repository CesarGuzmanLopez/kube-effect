import QtQuick
import QtQuick3D

// The REAL effect components, same trick as check-cylinder-overlap.qml.
import "../package/contents/ui" as UI

// Render harness for scripts/check-cap-overlap.py (ADR-027 overlap hunt).
//
// It instantiates the REAL Cube.qml (Shape = Polygon, three stub desktops
// painted red/green/blue by check-video-dome.py's module) inside a View3D and
// drives the two ADR-027 caps exactly as KWin's SceneView would: the cube node
// carries the camera's pitch (eulerRotation.x) and yaw (eulerRotation.y), so
// the transparent pass sees the caps at every angle, the way the user measured
// (pitch 30 / yaw 154.3, n=3, d=472, separation 10).
//
// The real Cube.qml keeps capTop AND capBottom true in every variant so the
// cap mesh Loader is always active; the harness then RE-BINDS each Cap node's
// visibility to the variant below (the last Qt.binding wins, that is how the
// gate toggles caps without touching Cube.qml):
//   0  caps OFF             -> the reference silhouette (what a face owns)
//   1  caps ON, both        -> the user's config (the suspected overlap)
//   2  only CapTop          -> isolate the top cap
//   3  only CapBottom       -> isolate the bottom cap (Cube.qml's node flip)
//   4  bottom cap UNROTATED  -> the same bottom mesh with NO node rotation
//      (for the "180 volteado" lead: variant 3 vs 4 silhouettes must MATCH.
//       They did NOT with the historical eulerRotation.x: 180 — that map is
//       azimuth a -> 180 - a, which ROTATES the face-corner ring by half a
//       tick; eulerRotation.z: 180 (a -> -a) is the ring-preserving flip,
//       measured in the pilot run of this gate: mirror-symdiff collapsed
//       from 78-220 cells (X rotation) to ~0 with the Z rotation.)
//
// faceDistance for the capture = W/2/tan(pi/3) + g = 461.9 + 10 = 471.9 (the
// overlay's d=472). The loose variant-4 cap reads cube.capMesh, the EXACT
// runtime ProceduralMesh, so the comparison never invents a second geometry.
Item {
    id: harness
    width: 800
    height: 450

    // Driven by Python before each grab.
    property real pitch: 0
    property real yaw: 0
    property int variant: 0
    // Orange, NOT the user's blue: the shared stub paints desktop 3 pure
    // blue too, so a blue cap is pixel-identical to that face's inner wall
    // (measured). The material regime under test is colour-agnostic.
    property string capColor: "#ff8000"
    property int capOpacity: 80
    // CapContent index (0 Color, 2 Image, 3 Arrow); the image/arrow variants
    // carry the asymmetry probes (content mirror of the bottom cap).
    property int capContentValue: 0
    property string capImageUrl: ""
    property int snapshotTick: 0

    // Cube geometry (mirrors the capture: W=1600 H=900 g=10, N=3).
    readonly property real faceWidth: 1600
    readonly property real faceHeight: 900
    readonly property real displacement: 10
    readonly property real apothem: 0.5 * faceWidth / Math.tan(Math.PI / 3) + displacement

    // Camera on the +Z axis far enough to see the whole solid at any tilt
    // (the distant-state formula of ScreenView plus a margin: the sweep must
    // never clip a corner, the silhouette assertions read the whole ring).
    readonly property real camRadius: apothem + 0.5 * faceHeight / Math.tan(0.5 * 60 * Math.PI / 180) + 900

    View3D {
        anchors.fill: parent
        renderMode: View3D.Offscreen

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "#000000"
        }

        camera: PerspectiveCamera {
            clipNear: 10
            clipFar: 100000
            fieldOfView: 60
            position: Qt.vector3d(0, 0, harness.camRadius)
        }

        UI.Cube {
            id: cube
            shape: 0
            faceDisplacement: harness.displacement
            faceSize: Qt.size(harness.faceWidth, harness.faceHeight)
            screenName: ""
            screenGeometry: Qt.rect(0, 0, harness.faceWidth, harness.faceHeight)
            // Both true ALWAYS (see the header): mesh loading is constant, the
            // per-variant visibility is re-bound below, so no variant changes
            // the loader state and every grab shares one warm scene.
            capTop: true
            capBottom: true
            capContent: harness.capContentValue
            capColor: harness.capColor
            capImage: harness.capImageUrl
            capOpacity: harness.capOpacity
            eulerRotation.x: harness.pitch
            eulerRotation.y: harness.yaw

            // variant 4: the bottom cap WITHOUT Cube.qml's 180 X node rotation,
            // the same ProceduralMesh the runtime built, child of the cube node
            // so it rides the identical pitch/yaw transform. Variant 3 vs 4
            // isolates the node rotation from everything else.
            UI.Cap {
                id: looseBottomCap
                // Named so the findCaps walk below skips it: it is the
                // harness's own twin, not one of Cube.qml's two cap Models
                // (both share the kubeCapSurface marker and the y < 0 half).
                objectName: "looseTwin"
                visible: harness.variant === 4
                mesh: cube.capMesh
                position: Qt.vector3d(0, -harness.faceHeight / 2, 0)
                content: harness.capContentValue
                color1: harness.capColor
                color2: "#0a1a5e"
                imageSource: harness.capImageUrl
                opacityValue: harness.capOpacity / 100
                // NO eulerRotation.x on purpose: this is the unrotated twin.
            }
        }
    }

    // The two real Cap nodes of Cube.qml, found through the kubeCapSurface
    // marker (the same marker check-cylinder-overlap.qml filters with).
    property Node capTopNode: null
    property Node capBottomNode: null

    function findCaps(node) {
        if (node === null || node === undefined || node.children === undefined) {
            return;
        }
        for (let i = 0; i < node.children.length; ++i) {
            const child = node.children[i];
            if (child === null || child === undefined) {
                continue;
            }
            if (child.kubeCapSurface === true && child.objectName !== "looseTwin") {
                if (child.position.y > 0) {
                    harness.capTopNode = child;
                } else {
                    harness.capBottomNode = child;
                }
            }
            findCaps(child);
        }
    }

    Component.onCompleted: {
        findCaps(cube);
        if (capTopNode !== null) {
            capTopNode.visible = Qt.binding(() => harness.variant === 1 || harness.variant === 2);
        }
        if (capBottomNode !== null) {
            capBottomNode.visible = Qt.binding(() => harness.variant === 1 || harness.variant === 3);
        }
        snapshot = buildSnapshot();
    }

    // JSON for the Python side: cap wiring + the material state of the THREE
    // cap Models (the two real ones and the loose variant-4 twin). The enums
    // are compared SYMBOLICALLY inside QML (the ints differ across Qt
    // versions and must never travel raw to Python).
    property string snapshot: "{}"

    function capState(node, tag) {
        if (node === null || node === undefined) {
            return {tag: tag, present: false};
        }
        const material = node.materials.length > 0 ? node.materials[0] : null;
        return {
            tag: tag,
            present: true,
            y: node.position.y,
            rx: node.eulerRotation.x,
            ry: node.eulerRotation.y,
            rz: node.eulerRotation.z,
            visible: node.visible,
            hasGeometry: node.geometry !== null,
            mask: material !== null && material.alphaMode === PrincipledMaterial.Mask,
            blend: material !== null && material.alphaMode === PrincipledMaterial.Blend,
            hasAlphaMode: material !== null && material.alphaMode !== undefined,
            opacity: material !== null ? material.opacity : -1,
            cutoff: material !== null ? material.alphaCutoff : -1
        };
    }

    // Debug aid (world transforms of the cap nodes): the v3-vs-v4
    // silhouette mismatch, measured once.
    function worldDump(node, p, out) {
        if (node === null || node === undefined || node.children === undefined) {
            return;
        }
        for (let i = 0; i < node.children.length; ++i) {
            const child = node.children[i];
            if (child === null || child === undefined) {
                continue;
            }
            if (child.kubeCapSurface === true) {
                out.push({
                    path: p + "/" + i,
                    pos: [child.position.x, child.position.y, child.position.z],
                    rx: child.eulerRotation.x,
                    rz: child.eulerRotation.z,
                    scale: [child.scale.x, child.scale.y, child.scale.z],
                    abs: [child.absolutePosition.x, child.absolutePosition.y, child.absolutePosition.z],
                    visible: child.visible
                });
            }
            worldDump(child, p + "/" + i, out);
        }
    }

    function buildSnapshot() {
        const dump = [];
        try {
            worldDump(cube, "cube", dump);
        } catch (error) {
            dump.push({ failed: String(error) });
        }
        return JSON.stringify({
            world: dump,
            caps: [
                capState(capTopNode, "top"),
                capState(capBottomNode, "bottom"),
                capState(looseBottomCap, "loose")
            ],
            capsActive: cube.capsActive,
            hasMesh: cube.capMesh !== null,
            faceDistance: cube.faceDistance,
            viewRadius: cube.viewRadius,
            apothem: harness.apothem
        });
    }

    // Mesh vertex dump (diagnosis of the v3-vs-v4 mismatch): JSON array of
    // the loaded cap mesh positions, read through the TOP node's geometry.
    readonly property string meshDump: {
        if (capTopNode === null || capTopNode.geometry === null) {
            return "[]";
        }
        const raw = capTopNode.geometry.positions;
        const out = [];
        for (let i = 0; i < raw.length; ++i) {
            out.push([raw[i].x, raw[i].y, raw[i].z]);
        }
        return JSON.stringify(out);
    }

    onSnapshotTickChanged: snapshot = buildSnapshot()
}
