/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "constants.js" as Constants
import "layerGeometry.js" as LayerGeometry

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
  // added/removed while the model syncs). For a Cylinder this is also the
  // slot count floor: the drum below 3 desktops keeps THREE slots — the
  // ones without a desktop simply have no delegate and show the hull
  // (ADR-025 pt.11, three-slot design) — so tick, R and the debug overlay
  // all read geometryCount, never the raw count. For a Polygon below 3 the
  // solid is the flat sheet (ADR-024) whose tick and radius are fixed
  // values, and the polygon branch keeps the old ADR-022 clamp so a
  // mid-sync 0 still yields finite geometry.
  readonly property int geometryCount: Math.max(3, faceRepeater.count)
  // Raw delegate count, for the debug overlay and the sheet rule
  // (ADR-024): it can briefly be 0..2 mid-sync and then differs from
  // geometryCount. Faces themselves never branch on it for LOD — that is
  // retired (ADR-023).
  readonly property int faceCount: faceRepeater.count
  // Cylinder intent (Shape says so, at any desktop count). It gates the
  // arc-mesh Loader, the debug overlay and the open turn range: the
  // representation is ALWAYS a drum — below 3 desktops a three-slot one
  // with empty slots showing the hull (ADR-025 pt.11, re-rectified: the
  // capped segment band made jumps and felt choppy).
  readonly property bool isCylinder: shape === Constants.Shape.Cylinder
  // Flat sheet (ADR-024): unchanged below 3 desktops whenever the shape
  // is Polygon — and also the degraded fallback when Cylinder was asked
  // but QtQuick3D.Helpers is missing (no mesh). With 0 faces mid-sync the
  // sheet is just an empty group node (harmless).
  readonly property bool isSheet: faceRepeater.count < 3 && !cylinderActive
  // Angle between the centres of consecutive slots: the polygon tick at
  // >= 3 everywhere, 360/3 = 120 in the three-slot drum (faces live in
  // slots 0..count-1, azimuths 0 and 120 — the arrows cycle the REAL
  // faces when this grid has holes, ADR-026b; a drag may still park on
  // an empty slot), fixed values on the sheet so Infinity/NaN from
  // 360/count can never happen.
  readonly property real angleTick: isSheet ? (faceRepeater.count === 2 ? 180 : 360) : 360 / geometryCount
  // Radius the distant state and the zoom clamps measure against. The flat
  // sheet has no apothem (its faceDistance is a gap, see below), so it
  // measures against half a face; with the drum in effect this is R
  // straight from cylinderRadius; otherwise (polygon, and the cylinder
  // without mesh at >= 3) it is exactly faceDistance (the apothem) and the
  // polygon behaviour is untouched. THE BRANCH ORDER IS THE FIX of the
  // v=4 regression (ADR-026b): reading faceDistance while cylinderActive
  // made the chain viewRadius -> faceDistance -> sheetGap -> viewRadius
  // cyclic for a mid-evaluation isSheet flip (measured trigger: a hot Shape
  // change with the cube open below 3 desktops — the arc Loader is
  // synchronous by default, so it was never a delayed mount; any mesh or
  // status flip that re-enters the sheet branch does the same): Qt cut the
  // loop and left viewRadius frozen at sheetGap (~4)
  // while faceDistance recovered to R — the engine even logged 'Binding
  // loop detected for property "viewRadius"' at this line (measured
  // offscreen with the real ScreenView: d=776 v=4, distant 786, wheel
  // cap 32 = 8*4, the camera trapped inside the drum). With cylinderActive
  // answered first the cylinder branch never touches the sheet chain, the
  // graph is acyclic in all three branches, and viewRadius === faceDistance
  // === R becomes structural at any count (3, 2 or 1).
  readonly property real viewRadius: cylinderActive ? cylinderRadius : isSheet ? 0.5 * faceSize.width : faceDistance
  // Half-separation of the two sheet quads. Proportional, not a fixed 1 px:
  // with a 24-bit depth buffer and clipNear 10, a 1-unit gap at a ~15k
  // maxRadius is 1-2 quantisation steps and can still Z-fight on 4K, so the
  // gap scales with the solid (0.5 % of viewRadius, floor 1 -> the two faces
  // are always >= 2 units apart). The chain is acyclic in every branch
  // (ADR-026b): the sheet's faceDistance reads sheetGap and viewRadius is
  // the half-face (it never reads faceDistance there); the drum reads
  // cylinderRadius in both; the polygon's faceDistance is the apothem.
  // Before the branch reorder this WAS cyclic in the sheet -> drum flip
  // (viewRadius -> faceDistance -> sheetGap -> viewRadius) and froze
  // viewRadius at this very gap (measured v=4 with R=776).
  readonly property real sheetGap: Math.max(1, viewRadius * 0.005)
  // Cylinder (every count, ADR-025/ADR-026): CubeFaceDisplacement means
  // the LINEAR gap between neighbouring arcs measured on the surface —
  // also in the three-slot drum, where the empty slots' wedge measures
  // the same g. Negative values cannot exist without breaking the
  // isometry (the arc must measure exactly W or the texture compresses),
  // so they clamp to 0 — the KCM says it in the tooltip; the polygon
  // below keeps negative overlap.
  readonly property real cylinderGap: Math.max(0, isFinite(faceDisplacement) ? faceDisplacement : 0)
  // R = N*(W + g) / 2pi with N = geometryCount (cylinderRadius() also
  // clamps). geometryCount pins the drum of 1-2 desktops to its three
  // slots — R = 3(W + g)/2pi, THE user gap included (the old fixed
  // 3W/2pi segment radius is retired with the band design).
  readonly property real cylinderRadius: Constants.cylinderRadius(geometryCount, faceSize.width, cylinderGap)
  // Polygon: apothem + displacement (a hand-edited negative displacement
  // can make it NEGATIVE — see safeViewRadius). Flat sheet: the distance
  // from centre to the front quad, i.e. sheetGap itself, so the close
  // state (faceDistance + 0.5·h/tan(fov/2)) fills the screen off the
  // actual face plane (ADR-024). Cylinder (drum or three-slot drum): the
  // arc's front sits at distance R from the axis, so faceDistance IS R
  // and close/distant keep filling the screen with no formula changes.
  // If the arc mesh could not be created (missing QtQuick3D.Helpers)
  // cylinderActive is false and the flat polygon/sheet values come back,
  // matching the fallback faces.
  readonly property real faceDistance: isSheet ? sheetGap : cylinderActive ? cylinderRadius : 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement
  // viewRadius pinned positive: CubeFaceDisplacement < -apothem flips the
  // polygon apothem negative (pre-existing ADR-022 range), which fed
  // negative minRadius/maxRadius to the wheel and a negative distant radius
  // — the camera dived inside the solid and the cube vanished.
  readonly property real safeViewRadius: Math.max(1, viewRadius)

  function desktopAt(azimuth) {
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
  // (ADR-025 point 13), and desktopAzimuth answers with it. Flat sheet:
  // 0 and 180 (ADR-024); drum, three-slot drum and polygon: the tick grid
  // itself (angleTick already is 360/slots, so slot 1 of the 1-2 drum sits
  // at 120 without a dedicated helper).
  function faceAzimuth(index) {
    return cube.isSheet ? index * 180 : cube.angleTick * index;
  }

  function desktopAzimuth(desktop) {
    if (cube.isSheet) {
      // Face 1 of a two-sided sheet looks at 180 deg; a single face (or
      // no face mid-sync) always answers 0, which is inside the ±80
      // clamp of the one-desktop sheet.
      const number = desktop !== null && desktop !== undefined ? desktop.x11DesktopNumber : 1;
      return cube.faceCount === 2 && number >= 2 ? 180 : 0;
    }
    // x11DesktopNumber is the NAME of the role KWin's virtual-desktop
    // model exposes (the name is inherited from X11); under Wayland it is
    // also the desktop number, 1..N. It is not an X11 compatibility path.
    return cube.angleTick * (desktop.x11DesktopNumber - 1);
  }

  // Curved arc geometry (ADR-025): ONE ProceduralMesh shared by all faces
  // — the arcs differ only by position and eulerRotation.y, exactly like
  // the built-in "#Rectangle" is one mesh behind every Model. Cube.qml reaches it
  // through a Loader source URL (the same runtime path that keeps the
  // QtQuick3D.Helpers import of CylinderArcMesh.qml out of the effect's
  // compile-time dependencies — the HullVideo/HullRadial isolation
  // pattern of ADR-022). A Loader can only load Item roots, so the mesh
  // lives inside that file's zero-size holder Item and is read back here
  // through item.mesh. active follows isCylinder at ANY desktop count
  // (the three-slot drum below 3 needs it too): polygon mode never
  // creates it; with a missing module the Loader stays in Error,
  // cylinderMesh remains null and cylinderActive turns false, so the
  // solid keeps the flat sheet/polygon formulas. The bindings below are
  // (W, H, R): the mesh rebuilds on a screen resize, a config change or
  // a slot-count switch, never per frame — turning and zooming are
  // transformations of the Models.
  Loader {
    id: arcMeshLoader
    active: cube.isCylinder
    source: "CylinderArcMesh.qml"
    onLoaded: {
      // Bind, do not assign: the KCM can change the displacement (R)
      // or the screen can resize (W/H) while the cube is open (the
      // videoLoader pattern of ADR-022). One radius formula for every
      // cylinder: the drum N(W+g)/2pi with geometryCount = max(3,
      // faces), so the 1-2 drum gets its three slots and the user's
      // linear gap g (the old fixed 3W/2pi segment branch is gone).
      item.faceWidth = Qt.binding(() => cube.faceSize.width);
      item.faceHeight = Qt.binding(() => cube.faceSize.height);
      item.radius = Qt.binding(() => cube.cylinderRadius);
    }
  }
  // Loader.Ready can still hand a transient null item (ADR-022 guard);
  // only a ready holder means a real mesh.
  readonly property Geometry cylinderMesh: arcMeshLoader.status === Loader.Ready && arcMeshLoader.item !== null && arcMeshLoader.item !== undefined ? arcMeshLoader.item.mesh : null
  // The curved drum is in effect whenever it was asked AND the mesh
  // exists — at 1-2 desktops that is the three-slot drum, not the sheet.
  // Without the mesh (missing module) faceDistance/viewRadius/placement
  // fall back to the flat sheet or the polygon values and the faces keep
  // the flat rectangle: same known look, one engine log line about the
  // import. (The old count >= 3 condition belonged to the segment branch
  // retired by ADR-025 pt.11's three-slot design.)
  readonly property bool cylinderActive: isCylinder && cylinderMesh !== null
  // Live camera distance to the solid centre, bound by ScreenView from
  // cameraController.radius. NOT consumed by the runtime: the dynamic
  // culling it fed was reverted (ADR-025 point 12) and ADR-026 fixed the
  // overlap as a paint-order problem instead. The binding and cameraRadius
  // stay so the cylinderCullMode seed (and the wiring check that drives
  // it) keep their contract as the documented alternative.
  property real cameraRadius: 0
  // -----------------------------------------------------------------
  // Caps (tapas, ADR-027): the top and bottom closing surfaces, enabled
  // separately and dead by default (false) so the untouched look is the
  // cube of before, pixel for pixel. Raw config values arrive here (the
  // ScreenView binding below passes effect.configuration as-is) and are
  // RESOLVED here through the pure constants.js helpers, the same way
  // shape() is resolved upstream: a hand-edited kwinrc can only ever mean
  // a valid content/fit/gradient type, a 0..1 opacity and a local image.
  // None of these feeds faceDistance/viewRadius/sheetGap: the cap block
  // only READS the existing geometry (geometryCount, faceDistance,
  // cylinderRadius, faceSize), never writes it, so it cannot recreate the
  // ADR-026b binding-loop class (the capMesh property is consumed by the
  // two Cap Models and by nothing that measures the camera).
  property bool capTop: false
  property bool capBottom: false
  property int capContent: Constants.CapContent.Color
  // The overlay is the project's diagnostic switch (ADR-023); with it on,
  // the caps PAINT THE ARROW MARKER whatever CapContent says (ADR-027
  // amendment 2): rotation/mirror becomes readable in the nested test
  // without touching the user's stored value, and the pixel gate can
  // measure the marker centroids of both caps.
  property bool debugOverlay: false
  property color capColor: "#1b3fd8"
  property color capColor2: "#0a1a5e"
  property int capGradientType: Constants.CapGradientType.LinearVertical
  property int capGradientStop: 50
  property url capImage: ""
  property int capImageFit: Constants.CapImageFit.Cover
  property int capOpacity: 80
  // Resolved once here so both caps (and the debug paths later) share one
  // interpretation of the stored values. DebugOverlay overrides the
  // content with the Arrow marker (see the debugOverlay property).
  readonly property int capContentType: debugOverlay ? Constants.CapContent.Arrow : Constants.capContent(capContent)
  readonly property int capGradientTypeResolved: Constants.capGradientType(capGradientType)
  readonly property int capImageFitResolved: Constants.capImageFit(capImageFit)
  readonly property string capImageSource: Constants.capImageSource(capImage)
  readonly property real capOpacityValue: Constants.capOpacity(capOpacity)
  // The one log for a broken/absent cap image (both Cap Models funnel
  // their imageUnavailable signal here; the radialWarned pattern).
  property bool capImageWarned: false
  function reportCapImageFailure(reason) {
    if (cube.capImageWarned) {
      return;
    }
    cube.capImageWarned = true;
    console.warn("kube-effect: " + reason + "; painting CapColor on the caps instead");
  }
  // Caps are volume surfaces: the flat sheet (Polygon at 1-2 desktops,
  // ADR-024) encloses nothing, so they are disabled BY CODE (ADR-027), not
  // by an option. cylinderActive picks the silhouette: disc over the drum
  // (it closes the empty wedges too), inscribed N-gon over the polygon.
  readonly property bool capsActive: (capTop || capBottom) && !isSheet
  // ONE mesh for both caps (ADR-027, the shared CylinderArcMesh pattern):
  // isolated behind a Loader because ProceduralMesh lives in
  // QtQuick3D.Helpers — without the module only this Loader errors, the
  // mesh stays null, both caps stay hidden and the cube is untouched (one
  // engine log line, no console spam). The bindings are the existing
  // geometry outputs; the generators answer EMPTY arrays while any of them
  // is degenerate (mid-sync faceSize, displacement past the apothem), so
  // the mesh simply renders nothing until the numbers settle.
  Loader {
    id: capMeshLoader
    active: cube.capsActive
    source: "CapMesh.qml"
    onLoaded: {
      // Bind, do not assign (the arcMeshLoader lesson): the KCM can
      // toggle Shape or move the displacement slider, and the screen
      // can resize, while the caps are open.
      item.sides = Qt.binding(() => cube.geometryCount);
      item.apothem = Qt.binding(() => cube.faceDistance);
      // The face width is what keeps the polygon ring on the face
      // corners instead of the plane intersections (ADR-027
      // amendment): reads faceSize only, never viewRadius, so the
      // binding graph stays acyclic (ADR-026b).
      item.faceWidth = Qt.binding(() => cube.faceSize.width);
      item.radius = Qt.binding(() => cube.cylinderRadius);
      item.halfHeight = Qt.binding(() => cube.faceSize.height / 2);
      item.useDisc = Qt.binding(() => cube.cylinderActive);
    }
  }
  // Loader.Ready can still hand a transient null item (ADR-022 guard).
  readonly property Geometry capMesh: capMeshLoader.status === Loader.Ready && capMeshLoader.item !== null && capMeshLoader.item !== undefined ? capMeshLoader.item.mesh : null
  // The two closing surfaces at y = +/- faceSize.height/2. The BOTTOM one
  // is the SAME mesh on a node rotated 180 deg about Z (ADR-027 amendment
  // 2 — see the axis note on the node below: no second geometry): the turn
  // flips the +Y normal to -Y (outward down) and keeps the winding
  // consistent seen from outside. Distinct Y centroids
  // (+H/2 vs -H/2) extend the ADR-026 ordering rule to the caps: they can
  // never paint over the front faces.
  Cap {
    id: capTopModel
    visible: cube.capTop && cube.capsActive && cube.capMesh !== null
    mesh: cube.capMesh
    position: Qt.vector3d(0, cube.faceSize.height / 2, 0)
    content: cube.capContentType
    color1: cube.capColor
    color2: cube.capColor2
    gradientType: cube.capGradientTypeResolved
    gradientStop: cube.capGradientStop
    imageSource: cube.capImageSource
    imageFit: cube.capImageFitResolved
    opacityValue: cube.capOpacityValue
    onImageUnavailable: cube.reportCapImageFailure(reason)
    onSurfaceDegraded: cube.reportCapImageFailure(reason)
  }
  Cap {
    id: capBottomModel
    visible: cube.capBottom && cube.capsActive && cube.capMesh !== null
    mesh: cube.capMesh
    position: Qt.vector3d(0, -cube.faceSize.height / 2, 0)
    // Rotation of the SAME node content: +Y normal becomes -Y, and the
    // mesh (flat, y = 0 around its origin) lands in the plane y = 0 of
    // this node — the position above already carries the half-height.
    // THE AXIS IS Z, NOT X (ADR-027 overlap fix, measured with pixels in
    // cap pixel gate, removed for cost (doc/trucos-aprendidos.md, section P)): a 180 deg turn about X maps the
    // ring's local (x, z) to (x, -z), i.e. azimuth a -> 180 - a, which
    // is NOT a symmetry of the face-corner ring — it rotates the whole
    // ring by half a tick (60 deg at N = 3). The mis-rotated ring then
    // reaches 928 along the face normal (wall at 472: the cap pierces
    // the faces) and its border at a GAP azimuth drops to 472 instead
    // of 928 (the gap opens). Only 180 deg about Z flips the normal AND
    // preserves the ring: it maps (x, z) -> (-x, z), azimuth a -> -a,
    // the ring's real mirror symmetry (corner pairs straddle the face
    // normals, gap chords straddle the face-gap azimuths). Side effect
    // on the content: the grab is mirrored horizontally (u -> 1 - u)
    // instead of vertically; the asymmetric Arrow marker makes that
    // visible and is what the gate's mirror probe measures.
    eulerRotation.z: 180
    content: cube.capContentType
    color1: cube.capColor
    color2: cube.capColor2
    gradientType: cube.capGradientTypeResolved
    gradientStop: cube.capGradientStop
    imageSource: cube.capImageSource
    imageFit: cube.capImageFitResolved
    opacityValue: cube.capOpacityValue
    onImageUnavailable: cube.reportCapImageFailure(reason)
    onSurfaceDegraded: cube.reportCapImageFailure(reason)
  }
  // Culling: NoCulling ALWAYS, every shape (ADR-025 point 12, reverted
  // by the user; ADR-026 keeps the rule): the mirrored inner wall of the
  // far arcs seen through the gaps and edges IS the virgin KDE cube look
  // (ADR-023) — in the cylinder as in the polygon. What must not happen
  // is that wall being PAINTED OVER the front faces; ADR-026 fixes that
  // as a paint-order problem (distinct per-face sort centroids from the
  // polygon-style placement + an explicit material alphaMode: Mask at
  // rest writes depth so a far arc can never win, Blend while turning is
  // sorted back-to-front by those centroids). Culling stays out of it:
  // Constants.cylinderCullMode(cameraRadius, faceDistance) remains the
  // tested-but-unused seed of the alternative approach (tokens 1/0, map
  // to the Material enums symbolically, NEVER raw int — Qt 6.12.1 is
  // BackFace=1, Front=2, None=3 and a hardcoded 2 would invert the
  // effect into showing ONLY the inner wall).
  readonly property int faceCullMode: Material.NoCulling

  // -----------------------------------------------------------------
  // Window layers (ADR-028 model H as amended 2026-11-27): every window of
  // a face becomes a quad pushed OUTWARDS along the face normal by its
  // stacking rank, and the face grab releases exactly those ids (the holes
  // stay; the plate at z = -2 veils them so the solid's interior never
  // shows). Dead by default (WindowLayering false): pixel parity with the
  // cube of before, the caps' opt-in pattern (ADR-027). Raw config values
  // arrive here (the ScreenView binding passes effect.configuration
  // as-is) and are RESOLVED here through the pure layerGeometry.js helpers
  // — a hand-edited kwinrc can never reach the scene with an out-of-range
  // gap, LOD or plate alpha. None of these feeds faceDistance/viewRadius/
  // sheetGap: the block only READS faceCount/currentFaceIndex for the LOD,
  // so it cannot recreate the ADR-026b binding-loop class. The depth budget
  // is the fixed cap in layerGeometry.js for every shape — the amended
  // outward stack has no per-representation wiring left. The FIFTH key
  // (WindowLayerRotationOpacity) does not arrive raw: ScreenView resolves
  // it through layerGeometry.rotationOpacity + the faceOpacity mechanism
  // (Constants.faceOpacity(1, resolved, cubeMoving), FaceFadeMs) and feeds
  // the animated value as layerOpacity below — inert while the flag is off
  // (WindowLayers reads it only for quads and plate).
  property bool windowLayering: false
  // Raw KConfig reads arrive as VAR, never int/real: a scripted effect
  // returns UNDEFINED for a kwinrc key that was never saved, and binding
  // undefined to an int/real property coerces it to 0 BEFORE any resolver
  // sees it (measured 2026-11-28: gap/thickness/plate all silently became
  // 0 with a kwinrc that only held WindowLayering - the slab never built,
  // the veil never veiled). var keeps the undefined and the resolved
  // properties below are the first code that ever touches the value -
  // layerGeometry's resolvers already treat undefined/null/garbage as
  // "never configured" (finiteOr), which is exactly the schema default.
  property var windowLayerGap: LayerGeometry.GAP_DEFAULT
  property var windowLayerLodFaces: LayerGeometry.LOD_FACES_DEFAULT
  property var windowLayerPlateOpacity: LayerGeometry.PLATE_OPACITY_DEFAULT
  // Slab body (fourth amendment): the thickness REQUEST travels down
  // unchanged - layerGeometry.thicknessEffective clips it to half the
  // fitted step inside WindowLayers, where the step is known per face.
  // The edge colour is resolved here (raw KConfig strings can mean
  // garbage; the resolver answers the schema default for those).
  property var windowLayerThickness: LayerGeometry.THICKNESS_DEFAULT
  property string windowLayerEdgeColor: LayerGeometry.EDGE_COLOR_DEFAULT
  // The effective opacity of the pile, animated in ScreenView exactly like
  // faceOpacity (rest 1, rotation WindowLayerRotationOpacity).
  property real layerOpacity: 1
  // The desktop the camera is aimed at (ScreenView's currentDesktop), for
  // the LOD distance. Compared by desktop NUMBER, not by wrapper identity:
  // the model rows and Workspace.currentDesktopForScreen may hand out
  // different wrapper objects around the same desktop.
  property var currentDesktop: null
  readonly property real layerGapResolved: LayerGeometry.gapUnits(cube.windowLayerGap)
  readonly property int layerLodResolved: LayerGeometry.lodFaces(cube.windowLayerLodFaces)
  readonly property real layerPlateResolved: LayerGeometry.plateOpacity(cube.windowLayerPlateOpacity)
  readonly property string layerEdgeResolved: LayerGeometry.edgeColor(cube.windowLayerEdgeColor)
  // The face index the current desktop sits on (-1 mid-sync: no desktop
  // found yet, so no face is "current" and the LOD keeps every face flat).
  readonly property int currentFaceIndex: {
    const current = cube.currentDesktop;
    const count = faceRepeater.count;
    if (current === null || current === undefined) {
      return -1;
    }
    const number = current.x11DesktopNumber;
    for (let i = 0; i < count; ++i) {
      const node = faceRepeater.objectAt(i);
      if (node !== null && node !== undefined && node.desktop !== null && node.desktop !== undefined && node.desktop.x11DesktopNumber === number) {
        return i;
      }
    }
    return -1;
  }
  // Per-face decision: flag AND LOD distance of indices (window 0 = all
  // faces; ADR-028 rule 3 — a COST budget, never an ordering rule: an
  // instantiated quad costs a capture per frame even when culled).
  function layerFaceActive(index) {
    if (!cube.windowLayering) {
      return false;
    }
    return LayerGeometry.layerWithinLod(index, cube.currentFaceIndex, cube.faceCount, cube.layerLodResolved);
  }
  // The face node (CubeFace) of one index, null mid-sync. Used by the
  // layering gate (scripts/check-layers.py) to read the live quads and
  // grabs per face; desktopAt keeps its own path untouched.
  function faceNodeAt(index) {
    return faceRepeater.objectAt(index);
  }
  // DebugOverlay line 2 summary of the live slab ("slab=<box>/<quad>
  // eff=<n>", the ADR-028 fourth amendment): the box count proves on
  // screen that SlabMesh.qml actually LOADED (a Loader error keeps every
  // layer flat - slab=0/N - and the gate/console say the same). Built
  // only from accessors that already exist on WindowLayers.
  function layerBoxSummary() {
    let boxes = 0;
    let quadsTotal = 0;
    for (let i = 0; i < faceRepeater.count; ++i) {
      const node = faceRepeater.objectAt(i);
      if (node !== null && node !== undefined && node.windowLayers !== null && node.windowLayers !== undefined) {
        boxes += node.windowLayers.boxLiveCount;
        quadsTotal += node.windowLayers.quadCount;
      }
    }
    const first = faceRepeater.count > 0 ? faceRepeater.objectAt(0) : null;
    const wl = first !== null && first !== undefined && first.windowLayers !== null && first.windowLayers !== undefined ? first.windowLayers : null;
    const eff = wl !== null ? Math.round(wl.layerSlabEff) : 0;
    // Frame-vs-grab diagnostics (the separation hunt, 2026-11-28): the
    // FIRST layered window of face 0, box rect and grab rect side by
    // side. boxW == grabW with a geometry available = the frame == grab
    // case; box < grab with the margins visible here is the expected
    // Breeze picture.
    let diag = "";
    if (wl !== null && wl.quadCount > 0) {
      const q = wl.quadAt(0);
      if (q !== null && q !== undefined && q.win !== null && q.win !== undefined) {
        diag = " boxW=" + Math.round(q.boxW) + " boxH=" + Math.round(q.boxH) + " grabW=" + Math.round(q.win.width) + " grabH=" + Math.round(q.win.height) + " frame=" + (q.hasFrame ? 1 : 0);
      }
    }
    return boxes + "/" + quadsTotal + " eff=" + eff + diag;
  }

  Repeater3D {
    id: faceRepeater
    model: KWinComponents.VirtualDesktopModel {}
    delegate: CubeFace {
      faceSize: cube.faceSize
      faceOpacity: cube.faceOpacity
      screenName: cube.screenName
      screenGeometry: cube.screenGeometry
      // Curved arc while the cylinder drum is active (every slot
      // count); null keeps the flat built-in rectangle (polygon,
      // sheet, and the degraded fallback without QtQuick3D.Helpers).
      cylinderMesh: cube.cylinderMesh
      // Culling: NoCulling for every shape and camera position
      // (ADR-025 point 12 reverted; ADR-026 keeps the rule — the
      // overlap it chased was paint order, fixed by the placement
      // below and the material's alphaMode, never by culling).
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
      // (Since ADR-028 the scale lives on the face Model inside the
      // CubeFace node, not on the node itself: the layer quads apply
      // their own px scale and must not inherit this one twice. The
      // composed world transform is identical to the old Model-root.)
      faceScale: cube.cylinderActive ? Qt.vector3d(1, 1, 1) : Qt.vector3d(faceSize.width / 100, faceSize.height / 100, 1)
      // Window layers (ADR-028 as amended): the per-face LOD decision and
      // the resolved numbers; the face node forwards them to WindowLayers
      // untouched (raw kwinrc values are clamped above, in Cube; the depth
      // budget is the fixed cap inside layerGeometry.js — nothing to pass).
      layersActive: cube.layerFaceActive(index)
      layerGap: cube.layerGapResolved
      layerPlateOpacity: cube.layerPlateResolved
      layerOpacity: cube.layerOpacity
      layerThickness: cube.windowLayerThickness
      edgeColor: cube.layerEdgeResolved
      // Flat sheet (ADR-024): both quads at the centre, one facing each
      // way (0 deg / 180 deg), separated by +/-sheetGap in z
      // (proportional, >= 2 units total) so the near-coplanar triangles
      // never Z-fight at any depth-buffer precision. With a single
      // desktop only the front one exists; it keeps z = +sheetGap, the
      // side the resting camera looks at, so the close state and the
      // two-desktop front read identically.
      // Cylinder slots: angleTick * index with the 3-slot floor, so
      // 1-2 desktops put their faces at 0 and 120 exactly like the
      // drum — no special azimuth rule survives from the retired
      // band design (ADR-025 pt.11); the flat rectangle keeps the
      // sheet angles.
      eulerRotation.y: cube.faceAzimuth(index)
      position: {
        if (cube.isSheet) {
          return Qt.vector3d(0, 0, index === 0 ? cube.sheetGap : -cube.sheetGap);
        }
        // Every solid — polygon, drum and three-slot drum — places its face
        // with THIS rule: the node sits at faceDistance along the
        // face's azimuth (ADR-026). The drum's arc mesh is generated
        // around the node (mid-point at the origin, axis at -R), so
        // the same translate + rotate below builds the drum from the
        // polygon's placement instead of pinning every node to the
        // axis: the world sort centroid (QtQuick3D orders the
        // transparent pass by the bounds centre projected on the view
        // axis) then differs per face even where the drum surface
        // would otherwise tie, and the polygon never needed more.
        const transform = Qt.matrix4x4();
        transform.rotate(cube.angleTick * index, Qt.vector3d(0, 1, 0));
        return transform.times(Qt.vector3d(0, 0, cube.faceDistance));
      }
    }
  }
}
