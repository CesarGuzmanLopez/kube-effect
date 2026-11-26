/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "constants.js" as Constants

Node {
    id: cube

    property real faceDisplacement: 100
    // Face material opacity (ADR-021); ScreenView animates it with the turn.
    property real faceOpacity: 1
    // Solid shape (ADR-025): already resolved by ScreenView through
    // Constants.shape(), so a hand-edited kwinrc integer can only ever mean
    // Polygon. From 3 desktops on it picks the drum vs the polygon; below 3
    // it picks the CURVED SEGMENT (Cylinder) vs the flat sheet (Polygon) —
    // a drum cannot close with 1-2 arcs, and the sheet stays the
    // representation with Polygon (ADR-025 extends ADR-024, it does not
    // delete it).
    property int shape: Constants.Shape.Polygon
    required property size faceSize
    // Screen identity passed to every DesktopView (ADR-022): no dynamic-scope
    // lookup of ScreenView.targetScreen from inside the face delegates.
    required property string screenName
    required property rect screenGeometry
    // Camera yaw in degrees, bound by ScreenView. The face LOD was retired
    // (ADR-023), so only the debug overlay reads it; ScreenView feeds it from
    // a single DebugOverlay-gated toEulerAngles() (the gradient-yaw pattern,
    // ADR-022), so no decomposition is paid while the overlay is off.
    property real cameraYaw: 0
    // The repeater count can transiently be 0, 1 or 2 (desktops are being
    // added/removed while the model syncs). Below 3 the solid is never the
    // closed drum: it is the flat sheet or the curved segment (ADR-024 /
    // ADR-025), whose tick and radius are fixed values (Infinity/NaN from
    // 360/count can never happen). The polygon branch keeps the old ADR-022
    // clamp so a mid-sync 0 still yields finite geometry.
    readonly property int geometryCount: Math.max(3, faceRepeater.count)
    // Raw delegate count, for the debug overlay and the sheet/segment rules
    // (ADR-024/ADR-025): it can briefly be 0..2 mid-sync and then differs
    // from geometryCount. Faces themselves never branch on it for LOD —
    // that is retired (ADR-023).
    readonly property int faceCount: faceRepeater.count
    // Cylinder intent (Shape says so, at any desktop count). It gates the
    // arc-mesh Loader and the debug overlay; the two representations split
    // below (drum at >= 3, curved segment at 1-2).
    readonly property bool isCylinder: shape === Constants.Shape.Cylinder
    // Curved segment (ADR-025, below 3 desktops): one or two 120-degree
    // arcs — 1 desktop is a single arc centred on 0 (turn range [-60, 60]:
    // the arc's own band, its edges are the last front-facing degrees);
    // 2 are adjacent arcs centred on 0 and 120, a continuous 240 band with
    // the 120 gap behind it where the hull shows (ADR-003), turn range
    // [-60, 180] so the camera rides the whole band but never parks in
    // that gap (the symmetric +/-80/+/-120 first chosen were rectified by
    // geometry, ADR-025 point 11). The linear gap g does NOT apply: the
    // arcs are adjacent/fixed, R depends on W alone.
    readonly property bool cylinderSegments: isCylinder && faceRepeater.count < 3 && cylinderMesh !== null
    // Flat sheet (ADR-024): unchanged below 3 desktops whenever the shape
    // is Polygon — and also the degraded fallback when Cylinder was asked
    // but QtQuick3D.Helpers is missing (no mesh). With 0 faces mid-sync the
    // sheet is just an empty group node (harmless).
    readonly property bool isSheet: faceRepeater.count < 3 && !cylinderSegments
    // Angle between the centres of consecutive faces: 120 with the segment
    // band of 2 (the tick the arrows and states step through — face 1 sits
    // at 120, not 180), the polygon tick with the drum, fixed values below
    // so Infinity/NaN from 360/count can never happen.
    readonly property real angleTick: cylinderSegments ? (faceRepeater.count === 2 ? Constants.CYLINDER_SEGMENT_DEG : 360) : isSheet ? (faceRepeater.count === 2 ? 180 : 360) : 360 / geometryCount
    // Radius the distant state and the zoom clamps measure against. The flat
    // sheet has no apothem (its faceDistance is a gap, see below), so it
    // measures against half a face; everywhere else this is exactly
    // faceDistance (the polygon apothem, the drum's R or the segment's
    // 3W/2pi — ADR-025) and the polygon behaviour is untouched. It must NOT
    // read faceDistance in sheet mode: faceDistance derives from sheetGap
    // which derives from viewRadius (cycle).
    readonly property real viewRadius: isSheet ? 0.5 * faceSize.width : faceDistance
    // Half-separation of the two sheet quads. Proportional, not a fixed 1 px:
    // with a 24-bit depth buffer and clipNear 10, a 1-unit gap at a ~15k
    // maxRadius is 1-2 quantisation steps and can still Z-fight on 4K, so the
    // gap scales with the solid (0.5 % of viewRadius, floor 1 -> the two faces
    // are always >= 2 units apart). The order viewRadius -> sheetGap ->
    // faceDistance keeps the chain acyclic.
    readonly property real sheetGap: Math.max(1, viewRadius * 0.005)
    // Cylinder (drum, ADR-025): CubeFaceDisplacement means the LINEAR gap
    // between neighbouring arcs measured on the surface. Negative values
    // cannot exist there without breaking the isometry (the arc must
    // measure exactly W or the texture compresses), so they clamp to 0 —
    // the KCM says it in the tooltip; the polygon below keeps negative
    // overlap.
    readonly property real cylinderGap: Math.max(0, isFinite(faceDisplacement) ? faceDisplacement : 0)
    // R = N*(W + g) / 2pi (cylinderRadius() also clamps; geometryCount keeps
    // the mid-sync 0..2 counts out of this — below 3 the curved segment uses
    // segmentRadius instead and this value is not applied to the mesh).
    readonly property real cylinderRadius: Constants.cylinderRadius(geometryCount, faceSize.width, cylinderGap)
    // Radius of the curved segment (1-2 desktops, ADR-025): a fixed 120°
    // arc measuring W, so R = 3W/(2pi) — the gap plays no role by
    // construction. Reads faceSize.width only: the chain stays acyclic.
    readonly property real segmentRadius: Constants.cylinderArcRadius(faceSize.width)
    // Polygon: apothem + displacement (a hand-edited negative displacement
    // can make it NEGATIVE — see safeViewRadius). Flat sheet: the distance
    // from centre to the front quad, i.e. sheetGap itself, so the close
    // state (faceDistance + 0.5·h/tan(fov/2)) fills the screen off the
    // actual face plane (ADR-024). Drum: the arc's front sits at distance R
    // from the axis, so faceDistance IS R. Segment: the same story with
    // 3W/2pi. In every cylinder case close/distant keep filling the screen
    // with no formula changes — and if the arc mesh could not be created
    // (missing QtQuick3D.Helpers) cylinderActive/cylinderSegments are false
    // and the flat polygon/sheet values come back, matching the fallback
    // faces.
    readonly property real faceDistance: cylinderSegments ? segmentRadius : isSheet ? sheetGap : cylinderActive ? cylinderRadius : 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement
    // viewRadius pinned positive: CubeFaceDisplacement < -apothem flips the
    // polygon apothem negative (pre-existing ADR-022 range), which fed
    // negative minRadius/maxRadius to the wheel and a negative distant radius
    // — the camera dived inside the solid and the cube vanished.
    readonly property real safeViewRadius: Math.max(1, viewRadius)

    function desktopAt(azimuth) {
        if (cube.cylinderSegments) {
            // The band is asymmetric (arcs centred on 0 and 120), so the
            // selection rule is its own: |normalized a| <= 60 is face 0,
            // anything wider is face 1 (mirrored, so -61 answers 1 too).
            // -1 (mid-sync 0 faces, garbage azimuth) hands back null, which
            // ScreenView.switchTo already ignores.
            const index = Constants.cylinderSegmentDesktopAt(azimuth, faceRepeater.count);
            if (index < 0) {
                return null;
            }
            const face = faceRepeater.objectAt(index);
            return face !== null && face !== undefined ? face.desktop : null;
        }
        if (cube.isSheet) {
            // sheetDesktopAt answers -1 for a non-finite azimuth or a count
            // that cannot be a face index (0 mid-sync): hand back null, which
            // ScreenView.switchTo already ignores.
            const index = Constants.sheetDesktopAt(azimuth, faceRepeater.count);
            if (index < 0) {
                return null;
            }
            const face = faceRepeater.objectAt(index);
            return face !== null && face !== undefined ? face.desktop : null;
        }
        let index = Math.round(azimuth / angleTick) % geometryCount;
        if (index < 0) {
            index += geometryCount;
        }
        // The delegate may not exist yet (model mid-sync): objectAt returns
        // null, and dereferencing it used to throw inside the click handler.
        const face = faceRepeater.objectAt(index);
        return face !== null && face !== undefined ? face.desktop : null;
    }

    // Where face i is centred (degrees): the ONE source of face azimuths —
    // the delegate places the face with it, arrowAzimuth cycles through it
    // (ADR-025 point 13), and desktopAzimuth answers with it, so an arrow
    // can never aim at an azimuth without a face. Segment: 0 / 120
    // (cylinderSegmentAzimuth); flat sheet: 0 and 180 (ADR-024); drum and
    // polygon: the tick grid itself.
    function faceAzimuth(index) {
        if (cube.cylinderSegments) {
            return Constants.cylinderSegmentAzimuth(index, cube.faceCount);
        }
        return cube.isSheet ? index * 180 : cube.angleTick * index;
    }

    function desktopAzimuth(desktop) {
        if (cube.cylinderSegments) {
            // Segment centres: 0 with one desktop, 0 and 120 with two
            // (cylinderSegmentAzimuth; >= 3 never reaches this branch).
            const number = desktop !== null && desktop !== undefined ? desktop.x11DesktopNumber : 1;
            return Constants.cylinderSegmentAzimuth(number - 1, cube.faceCount);
        }
        if (cube.isSheet) {
            // Face 1 of a two-sided sheet looks at 180 deg; a single face (or
            // no face mid-sync) always answers 0, which is inside the ±80
            // clamp of the one-desktop sheet.
            const number = desktop !== null && desktop !== undefined ? desktop.x11DesktopNumber : 1;
            return cube.faceCount === 2 && number >= 2 ? 180 : 0;
        }
        // x11DesktopNumber es el NOMBRE del rol que expone el modelo de
        // escritorios virtuales de KWin (heredado de X11); en Wayland también es
        // el número de escritorio, 1..N. No es una ruta de compatibilidad X11.
        return cube.angleTick * (desktop.x11DesktopNumber - 1);
    }

    // Curved arc geometry (ADR-025): ONE ProceduralMesh shared by all faces
    // — the arcs differ only by eulerRotation.y, exactly like the built-in
    // "#Rectangle" is one mesh behind every Model. Cube.qml reaches it
    // through a Loader source URL (the same runtime path that keeps the
    // QtQuick3D.Helpers import of CylinderArcMesh.qml out of the effect's
    // compile-time dependencies — the HullVideo/HullRadial isolation
    // pattern of ADR-022). A Loader can only load Item roots, so the mesh
    // lives inside that file's zero-size holder Item and is read back here
    // through item.mesh. active follows isCylinder (drum OR segment):
    // polygon mode never creates it; with a missing module the Loader
    // stays in Error, cylinderMesh remains null and both cylinderActive
    // and cylinderSegments turn false, so the solid keeps the flat sheet/
    // polygon formulas. The bindings below are (W, H, R): the mesh
    // rebuilds on a screen resize, a config change or a drum/segment
    // switch, never per frame — turning and zooming are transformations
    // of the Models.
    Loader {
        id: arcMeshLoader
        active: cube.isCylinder
        source: "CylinderArcMesh.qml"
        onLoaded: {
            // Bind, do not assign: the KCM can change the displacement (R)
            // or the screen can resize (W/H) while the cube is open (the
            // videoLoader pattern of ADR-022). The radius follows the
            // cylinder branch in effect: the drum measures the linear gap
            // g, the segment is fixed at 3W/2pi.
            item.faceWidth = Qt.binding(() => cube.faceSize.width);
            item.faceHeight = Qt.binding(() => cube.faceSize.height);
            item.radius = Qt.binding(() => cube.cylinderSegments ? cube.segmentRadius : cube.cylinderRadius);
        }
    }
    // Loader.Ready can still hand a transient null item (ADR-022 guard);
    // only a ready holder means a real mesh.
    readonly property Geometry cylinderMesh: arcMeshLoader.status === Loader.Ready && arcMeshLoader.item !== null && arcMeshLoader.item !== undefined ? arcMeshLoader.item.mesh : null
    // The drum branch is only in effect while the mesh exists (the segment
    // branch has the same condition). Without it (missing module)
    // faceDistance/viewRadius/placement fall back to the flat sheet or the
    // polygon values and the faces keep the flat rectangle: same known
    // look, one engine log line about the import.
    readonly property bool cylinderActive: isCylinder && faceRepeater.count >= 3 && cylinderMesh !== null
    // True while ANY curved branch is in effect (drum or segment): gates
    // the arc geometry (mesh units -> scale 1, radius in the vertices ->
    // position at the origin) and the debug fields. The mesh condition is
    // implicit — both branches require cylinderMesh.
    readonly property bool cylinderFaces: cylinderActive || cylinderSegments
    // Live camera distance to the solid centre, bound by ScreenView from
    // cameraController.radius. NOT consumed by the runtime anymore: the
    // dynamic culling it fed was reverted (ADR-025 point 12). The binding
    // and cameraRadius stay so the cylinderCullMode seed (and the wiring
    // check that drives it) can flip the switch again once the real
    // overlap fix — paint-order/depth, not culling — lands.
    property real cameraRadius: 0
    // Culling: NoCulling ALWAYS, every shape (ADR-025 point 12, reverted
    // by the user): the mirrored inner wall of the far arcs seen through
    // the gaps and edges IS the virgin KDE cube look (ADR-023) — in the
    // cylinder as in the polygon. What must not happen is that wall being
    // PAINTED OVER the front faces while turning; that is a paint-order
    // problem (transparent-pass centroid order when faceOpacity < 0.99,
    // or depth between the Models on the shared geometry when op = 1) —
    // the overlay prints op + blend to tell the two apart.
    // TODO(cylinder-overlap): fix the paint order; only then re-enable
    // Constants.cylinderCullMode(cameraRadius, faceDistance) here (it
    // answers the token 1 outside 1.05 R / 0 inside; map tokens to the
    // Material enums symbolically, NEVER by raw int — Qt 6.12.1 is
    // BackFace=1, Front=2, None=3 and a hardcoded 2 would invert the
    // effect into showing ONLY the inner wall).
    readonly property int faceCullMode: Material.NoCulling

    Repeater3D {
        id: faceRepeater
        model: KWinComponents.VirtualDesktopModel {}
        delegate: CubeFace {
            faceSize: cube.faceSize
            faceOpacity: cube.faceOpacity
            screenName: cube.screenName
            screenGeometry: cube.screenGeometry
            // Curved arc when a cylinder branch is active (drum or
            // segment); null keeps the flat built-in rectangle (polygon,
            // sheet, and the degraded fallback without QtQuick3D.Helpers).
            cylinderMesh: cube.cylinderMesh
            // Culling: NoCulling for every shape and camera position
            // (ADR-025 point 12 reverted — cube.faceCullMode is a pinned
            // constant, see its comment and TODO).
            cullMode: cube.faceCullMode
            // Every face renders always (ADR-023): the back-facing ones show
            // their inner side through the gaps between faces, which IS the
            // look of the virgin KDE cube; hiding them opened hull holes.
            // (On every shape the inner side of the far faces stays
            // visible through the gaps — the look ADR-023 defends; the
            // overlap to fix is their PAINT ORDER over the front faces,
            // diagnosed with op + blend in the overlay.)
            // The arc mesh is already in face units (W x H at radius R), so
            // the rectangle's 100-unit scale must NOT be applied to it.
            scale: cube.cylinderFaces ? Qt.vector3d(1, 1, 1) : Qt.vector3d(faceSize.width / 100, faceSize.height / 100, 1)
            // Flat sheet (ADR-024): both quads at the centre, one facing each
            // way (0 deg / 180 deg), separated by +/-sheetGap in z
            // (proportional, >= 2 units total) so the near-coplanar triangles
            // never Z-fight at any depth-buffer precision. With a single
            // desktop only the front one exists; it keeps z = +sheetGap, the
            // side the resting camera looks at, so the close state and the
            // two-desktop front read identically.
            // Curved segment (ADR-025): the arcs take their CENTRES instead
            // (0 and 120 — a 240 band, the drum formula's 360/N with the
            // count clamped by the shape itself), the drum keeps the polygon
            // tick; the flat rectangle stays at the old sheet angles.
            eulerRotation.y: cube.faceAzimuth(index)
            position: {
                if (cube.isSheet) {
                    return Qt.vector3d(0, 0, index === 0 ? cube.sheetGap : -cube.sheetGap);
                }
                if (cube.cylinderFaces) {
                    // The radius lives in the arc's VERTICES (centred on +Z
                    // at distance R from the Y axis), so the face itself
                    // stays at the origin and eulerRotation.y above carries
                    // it to its azimuth — the drum reuses the polygon's
                    // placement rule unchanged; the segment only differs in
                    // which azimuths the faces sit on (0 / 120, ADR-025).
                    return Qt.vector3d(0, 0, 0);
                }
                const transform = Qt.matrix4x4();
                transform.rotate(cube.angleTick * index, Qt.vector3d(0, 1, 0));
                return transform.times(Qt.vector3d(0, 0, cube.faceDistance));
            }
        }
    }
}
