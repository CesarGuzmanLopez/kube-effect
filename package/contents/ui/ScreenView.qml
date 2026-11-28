/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "constants.js" as Constants
import "layerGeometry.js" as LayerGeometry

Item {
  id: root
  focus: true

  readonly property QtObject targetScreen: KWinComponents.SceneView.screen
  property QtObject currentDesktop: KWinComponents.Workspace.currentDesktopForScreen(root.targetScreen)

  function switchTo(desktop) {
    // desktopAt can hand out null while the model is mid-sync (ADR-022
    // guard in Cube.desktopAt): switching to nothing would only close the
    // effect with no visible change.
    if (desktop === null || desktop === undefined) {
      return;
    }
    // A click or Enter during the closing animation must not move the
    // desktop without feedback: the effect already deactivated (ADR-022).
    if (!effect.activated) {
      return;
    }
    KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, root.targetScreen);
    effect.deactivate();
  }
  function switchToSelected() {
    const eulerRotation = cameraController.rotation.toEulerAngles();
    switchTo(cube.desktopAt(eulerRotation.y));
  }

  // helpers live in constants.js so they can be unit-tested (scripts/check-constants)
  readonly property string backgroundImageSource: Constants.backgroundImageSource(effect.configuration.SkyBox)
  readonly property bool backgroundImageSet: root.backgroundImageSource.length > 0
  readonly property string backgroundVideoSource: Constants.videoSource(effect.configuration.BackgroundVideo)
  readonly property bool backgroundVideoSet: root.backgroundVideoSource.length > 0
  readonly property int backgroundMode: Constants.backgroundMode(effect.configuration.Background)
  readonly property bool equirectMapping: Constants.usesEquirectMapping(effect.configuration.BackgroundImageLayout, root.backgroundImageSet)
  // Shared by the flat image and the flat video: one setting, one meaning.
  readonly property int flatImageFit: Constants.imageFit(effect.configuration.BackgroundImageFit)

  // Advanced: draw the cube only on the output the pointer was on when the
  // effect activated (ADR-014). KWin creates one SceneView per output and
  // composites each offscreen view over that screen's normal scene, so an
  // invisible view leaves the other screens untouched. The screen is
  // captured in main.qml at activation: Workspace.cursorPos +
  // Workspace.screenAt() give the real pointer output (KWin 6.8); moving the
  // pointer while the cube is shown does not move the cube. An empty name
  // (capture failed / older KWin) draws on every screen instead of nowhere.
  readonly property string sceneScreenName: {
    const screen = KWinComponents.SceneView.screen;
    if (screen === null || screen === undefined) {
      return "";
    }
    // String(undefined) would be the literal "undefined", which matches
    // nothing and would leave the cube drawn on no screen at all.
    const name = screen.name;
    return typeof name === "string" && name.length > 0 ? name : "";
  }
  readonly property bool cursorScreenOnly: effect.configuration.CursorScreenOnly === true
  readonly property bool drawOnThisScreen: !root.cursorScreenOnly || effect.cursorScreenName === "" || root.sceneScreenName === effect.cursorScreenName
  visible: root.drawOnThisScreen

  // An equirectangular image that rotates with the centre is the only case
  // rendered as a 3D SkyBox; everything else is a flat full-screen layer.
  // BackgroundImageRotate defaults to true, so an unset value still rotates.
  readonly property bool skyBoxBackground: root.backgroundMode === Constants.Background.Image && root.equirectMapping && effect.configuration.BackgroundImageRotate !== false && root.backgroundImageSet
  // Flat hull layer: Image mode that does not wrap the scene. A skybox keeps
  // it off so the panorama is decoded once (by the 3D texture), not twice.
  readonly property bool showFlatImage: root.backgroundMode === Constants.Background.Image && !root.skyBoxBackground

  // Video (Background == Video) is an image whose source is a clip, so it
  // reuses the image mapping/fit/rotate keys and the same two render paths:
  // equirect + rotate = 360 SkyBox (lightProbe), anything else = flat layer.
  // The clip itself lives in HullVideo.qml behind a Loader: QtMultimedia is
  // optional, and a missing module must only disable this item.
  readonly property bool backgroundVideo: root.backgroundMode === Constants.Background.Video
  readonly property bool videoWanted: root.backgroundVideo && root.backgroundVideoSet
  readonly property bool videoSkyBox: root.videoWanted && root.equirectMapping && effect.configuration.BackgroundImageRotate !== false
  // Decoding starts on the first activation and never in the background: the
  // item stays loaded (paused) once shown, so re-activating resumes the clip
  // instead of rebuilding it. Cleared only when the mode/source changes.
  property bool videoEverShown: false
  readonly property bool videoActive: root.videoWanted && root.videoEverShown
  readonly property bool videoReady: videoLoader.status === Loader.Ready
  // Loader.Ready survives a transient null item for one frame (unload); the
  // item reference must be checked before reading through it (ADR-022).
  readonly property bool videoPainted: root.videoReady && videoLoader.item !== null && videoLoader.item !== undefined && videoLoader.item.frameAvailable === true
  // Qt Quick 3D refuses a Texture.sourceItem as a light probe ("Cannot use
  // QSGTexture from Texture.sourceItem as light probe."), so a video can NOT
  // be wrapped by SceneEnvironment.SkyBox. The 360 clip is painted on a
  // sphere around the viewer instead (see videoDome below): same result, and
  // a Texture.sourceItem does work on a material's baseColorMap.
  readonly property bool videoDomePainted: root.videoSkyBox && root.videoPainted
  // The VideoOutput must be rendered for its texture provider to exist, so the
  // flat layer stays visible even in the 360 case; the dome, being opaque and
  // painted inside the View3D, covers it.
  readonly property bool showFlatVideo: root.videoActive
  // Texture.sourceItem takes a QQuickItem (verified in Qt 6.12 qmltypes) and
  // VideoOutput is one, so the skybox samples the very same video output.
  readonly property Item videoProbeItem: root.videoReady && videoLoader.item !== null && videoLoader.item !== undefined ? videoLoader.item.videoOutput : null
  // The warning must not repeat every frame: Loader.Error sticks anyway, so
  // one line tells the user qt6-multimedia is missing.
  property bool videoWarningShown: false
  onBackgroundsActiveChanged: {
    if (root.backgroundsActive) {
      root.videoEverShown = true;
    }
  }
  Component.onCompleted: {
    // A SceneView created while the effect is already visible (it is not,
    // today) must not wait for a change that never comes.
    if (root.backgroundsActive) {
      root.videoEverShown = true;
    }
  }
  // The "never reset" comment was a lie (ADR-022): a new clip or mode must
  // rebuild the item and be allowed to warn again; otherwise a source change
  // while the effect is off keeps the OLD decoder state and silences the new
  // one's failures forever. A view that already holds a live HullVideo is
  // not re-created by the reset (same source list), so the diagnosis timer
  // is rearmed here: without it a broken NEW clip stays silent until the
  // next activation (ADR-022, second review).
  onBackgroundVideoSourceChanged: {
    root.videoWarningShown = false;
    root.videoEverShown = root.backgroundsActive;
    if (videoLoader.status === Loader.Ready) {
      videoDiagnosis.restart();
    }
  }
  onBackgroundModeChanged: {
    root.videoWarningShown = false;
    root.videoEverShown = root.backgroundsActive;
    if (videoLoader.status === Loader.Ready) {
      videoDiagnosis.restart();
    }
  }
  // QtQuick3D's Texture exposes no load status (checked in Qt 6.12), so a tiny
  // probe decodes the file first: until it is ready (or on a broken path) the
  // environment stays transparent (no empty black SkyBox), and the colour
  // layer below paints the backdrop instead. The probe is decoded at 64 px
  // wide, not full size.
  readonly property bool skyBoxImageReady: root.skyBoxBackground && skyBoxProbe.status === Image.Ready
  // See the veil below: the cube "moves" while dragging or while the camera
  // rotation animation runs.
  readonly property bool cubeMoving: cameraController.busy || rotationAnimation.running
  // Turn range for the camera (ADR-024/ADR-025): [min, max] degrees or
  // [null, null] = free wrap. The routing itself lives in
  // Constants.azimuthRangeFor (ADR-026) so check-constants can test it —
  // an inline ternary between the two ranges could be swapped without any
  // check noticing. Computed here so the controller bindings, the states
  // and the debug overlay all read the SAME live value (one Cube re-eval).
  readonly property var azimuthRange: Constants.azimuthRangeFor(cube.shape, cube.faceCount, cube.cylinderMesh !== null)
  // DebugOverlay (ADR-023): live state painted on screen while the Advanced
  // key is on. console.log never reaches this KWin's journal and
  // org.kde.kwin.Effects.supportInformation returns an empty string for QML
  // properties (KWin 6.8.3, measured 2026-11-25; doc/trucos-aprendidos.md
  // section D), so the overlay is the only visible diagnostic channel.
  // debugEuler follows the gradient-yaw gating pattern (ADR-022): the
  // quaternion is decomposed ONCE per change and only while the overlay is
  // on (Cube receives cube.cameraYaw from it, the text below reads .x).
  readonly property vector3d debugEuler: effect.configuration.DebugOverlay === true ? cameraController.rotation.toEulerAngles() : Qt.vector3d(0, 0, 0)
  readonly property string debugInfo: {
    // Two lines max; composed only while the overlay is on.
    if (effect.configuration.DebugOverlay !== true) {
      return "";
    }
    // Names come from constants.js (mirrors config/main.xml, ADR-023).
    let line1 = "bg=" + Constants.backgroundName(root.backgroundMode) + " eq=" + (root.equirectMapping ? 1 : 0) + " sky=" + (root.skyBoxImageReady ? 1 : 0) + " vid " + (root.videoWanted ? 1 : 0) + "/" + (root.videoReady ? 1 : 0) + "/" + (root.videoPainted ? 1 : 0);
    if (root.videoReady) {
      // Loader.Ready survives a transient null item (same guard as
      // videoPainted above); "?" then beats dereferencing nothing.
      const videoItem = videoLoader.item;
      line1 += " ms=" + (videoItem === null || videoItem === undefined ? "?" : videoItem.mediaStatus);
    }
    line1 += " dim=" + (root.cubeMoving ? 1 : 0) + " exp=" + root.skyBoxExposure.toFixed(2) + " scr=" + root.sceneScreenName + " cur=" + effect.cursorScreenName + " draw=" + (root.drawOnThisScreen ? 1 : 0);
    // The per-face cos kept the information that diagnosed the LOD bug
    // (yaw, pitch, op, tick, cos per face); with the LOD retired it is
    // purely informative: no face is ever hidden by orientation.
    // sheet=1/0 and the azimuth limit (ADR-024): the sheet rules are live
    // state (isSheet flips mid-sync) and a stuck clamp is invisible
    // without them.
    let line2 = "yaw=" + cube.cameraYaw.toFixed(1) + " pitch=" + root.debugEuler.x.toFixed(1) + " r=" + cameraController.radius.toFixed(0) + " op=" + root.faceOpacity.toFixed(2) + " tick=" + cube.angleTick.toFixed(1) + " n=" + cube.faceCount + "/" + cube.geometryCount + " d=" + cube.faceDistance.toFixed(0) + " v=" + cube.viewRadius.toFixed(0) + " sheet=" + (cube.isSheet ? 1 : 0) + " lim=" + (root.azimuthRange[0] === null ? "none" : root.azimuthRange[0] + ".." + root.azimuthRange[1]) + " slab=" + cube.layerBoxSummary();
    // Shape state (ADR-025/ADR-026): the resolved form, and — while the
    // drum is in effect — its radius R plus the EFFECTIVE gap g_eff
    // (what the mesh really used after the negative clamp; a mismatch
    // with the KCM value is exactly what a hand-edited kwinrc would
    // cause). Below 3 desktops the drum keeps three slots and the field
    // slots=N/3 marks the empty ones (the hull shows there, no panel).
    // cyl(fallback) marks Shape=Cylinder without a mesh (QtQuick3D.Helpers
    // missing): the solid degraded to the flat sheet/polygon formulas.
    // The old cull= field is gone — faceCullMode is pinned to NoCulling
    // (ADR-025 pt.12) — and replaced by the blend= diagnostic below.
    line2 += " shape=" + Constants.shapeName(cube.shape);
    if (cube.cylinderActive) {
      line2 += " R=" + cube.cylinderRadius.toFixed(0) + " g_eff=" + cube.cylinderGap.toFixed(0);
      if (cube.faceCount < cube.geometryCount) {
        line2 += " slots=" + cube.faceCount + "/" + cube.geometryCount;
      }
    } else if (cube.isCylinder) {
      line2 += "(fallback)";
    }
    // Overlap diagnostic (ADR-025 pt.12, fixed by ADR-026 but kept
    // because it reads the live pass): blend=1 means the faces rotate-
    // blend (opacity < 0.99 -> alphaMode Blend, ordered back-to-front by
    // the per-face sort centroid); blend=0 on the CYLINDER means rest,
    // the Mask mode: far arcs cannot paint over near ones because the
    // kept fragments write depth. On the polygon/sheet blend=0 only
    // says "rest opacity" — those faces always Blend (the Mask branch
    // is bounded to the curved mesh, ADR-026 re-review) and never had
    // the overlap. If an inner wall ever shows "on top" again, shape +
    // op + blend together say which mechanism regressed.
    if (cube.isCylinder) {
      line2 += " blend=" + (root.faceOpacity < 0.99 ? 1 : 0);
    }
    for (let i = 0; i < cube.faceCount; ++i) {
      const cos = Math.cos((cube.angleTick * i - cube.cameraYaw) * Math.PI / 180);
      line2 += " f" + i + ":" + cos.toFixed(2);
    }
    return line1 + "\n" + line2;
  }
  // Face transparency (ADR-021): rest opacity, or the rotation opacity while
  // the cube moves (same signal as the hull dim; wheel zoom is not a turn).
  // The Behavior fades between both so a paused drag does not strobe. This
  // is independent of DimWhileRotating: that darkens the hull, this the faces.
  property real faceOpacity: Constants.faceOpacity(effect.configuration.FaceOpacity, effect.configuration.FaceRotationOpacity, root.cubeMoving)
  Behavior on faceOpacity {
    NumberAnimation {
      duration: Constants.faceFadeDuration(effect.configuration.FaceFadeMs)
      easing.type: Easing.OutQuad
    }
  }
  // Window layers (ADR-028 as amended): the pile fades with its OWN key,
  // WindowLayerRotationOpacity, through the very same machinery (rest 1 ->
  // the key while turning, FaceFadeMs). Rest is HARD-CODED 1, not the
  // FaceOpacity key: at rest the layered windows are always solid opaque
  // quads sitting in front of their holes (the Mask threshold in
  // WindowLayers reads this value, and >= 0.99 keeps the depth-ordered
  // opaque pass). The default 0.7 equals the face rotation default, so
  // out of the box turning fades the pile exactly like the face; 1.0 keeps
  // the windows solid AND depth-ordered while turning too. With the flag
  // off the value flows nowhere visible: no quads exist, the plate is
  // hidden and the face materials never read it (parity gate assert).
  property real layerOpacity: Constants.faceOpacity(1, LayerGeometry.rotationOpacity(effect.configuration.WindowLayerRotationOpacity), root.cubeMoving)
  Behavior on layerOpacity {
    NumberAnimation {
      duration: Constants.faceFadeDuration(effect.configuration.FaceFadeMs)
      easing.type: Easing.OutQuad
    }
  }
  // Dimming while rotating reaches every background, but never through the
  // same object:
  //   Color / Gradient / flat image / flat video -> the 2D veil (hullDim)
  //     over the hull.
  //   Image or video + Equirect (SkyBox 3D) -> probeExposure of the
  //     environment: that background is painted by the 3D scene, not by the
  //     2D layer, so a black Rectangle in front of the View3D would cover
  //     the faces as well.
  // dimOpacity is shared so both modes darken by the same amount, and the
  // 120 ms Behavior mirrors the veil's so neither stutters on a paused drag.
  property real skyBoxExposure: Constants.skyBoxExposure(effect.configuration.DimWhileRotating === true, root.cubeMoving, effect.configuration.DimWhileRotatingAmount)
  Behavior on skyBoxExposure {
    NumberAnimation {
      duration: 120
      easing.type: Easing.OutQuad
    }
  }
  // Alpha of the black sphere that dims the 360 *video* dome. The image
  // panorama dims with probeExposure, and a model has no exposure, so the
  // same amount is applied as a veil; 1 - exposure means both paths darken by
  // exactly dimOpacity(...) and the Behavior above animates both.
  readonly property real videoDomeVeil: 1 - root.skyBoxExposure

  // The hull (background behind the 3D view) must disappear together with
  // the effect. Binding Window.color kept the window surface painted after
  // deactivation, so the hull is painted here instead, gated by effect.visible
  // (still true during the closing animation, false once it ends).
  readonly property bool hullVisible: effect.visible

  // Decoding is not free (a 360 panorama or clip is several MB), so no
  // Image, no skybox texture and no MediaPlayer gets a source until the
  // effect is first shown. visible flips to true in activate(), before the
  // opening animation, and survives the closing one, so the switch happens
  // off screen and cannot flicker.
  readonly property bool backgroundsActive: effect.visible
  // Image + SkyBox paints nothing in 2D (the flat layer is off on purpose)
  // and the 3D environment is transparent until the probe is Ready, so the
  // solid colour has to hold the screen meanwhile; without it the hull would
  // be see-through (or black) on a slow/broken panorama.
  readonly property bool imageFallbackColor: root.backgroundMode === Constants.Background.Image && !root.skyBoxImageReady
  // A SkyBox (image or video) is painted by the 3D environment, so the 2D
  // veil must stay off once it is on screen (see skyBoxExposure below).
  readonly property bool skyBoxPainted: root.skyBoxImageReady || root.videoDomePainted
  // Solid colour layer: Color mode, the backdrop under a SkyBox that is not
  // painted yet, and the backdrop of the video. The last one covers three
  // cases with one rule: bars left by Contain/Stretch, the first frames
  // before decoding, and the documented fallback when QtMultimedia is
  // missing (then nothing else paints the hull).
  readonly property bool colorHullVisible: root.backgroundMode === Constants.Background.Color || root.imageFallbackColor || root.backgroundVideo

  Image {
    id: skyBoxProbe
    visible: false
    // drawOnThisScreen (ADR-022): KWin creates one SceneView per output
    // even when CursorScreenOnly paints on one, so without the gate every
    // screen decoded its own probe and its own lightProbe texture.
    source: root.skyBoxBackground && root.backgroundsActive && root.drawOnThisScreen ? root.backgroundImageSource : ""
    sourceSize.width: 64
    asynchronous: true
  }

  // Hull: solid colour (Background == Color), also the backup under Image +
  // SkyBox while the panorama is not painted yet (see imageFallbackColor) and
  // the backdrop/fallback of the video (see colorHullVisible).
  Rectangle {
    id: colorBackground
    anchors.fill: parent
    visible: root.hullVisible && root.colorHullVisible
    color: effect.configuration.BackgroundColor
  }

  // Hull: two-colour gradient without shaders (Background == Gradient).
  // Linear orientations are a Rectangle + Gradient; Radial is a real radial
  // painted with QtQuick.Shapes through an optional Loader (see
  // HullGradient.qml for why, ADR-013; ADR-022 makes Shapes fall back to the
  // linear gradient when the module is missing).
  HullGradient {
    id: gradientBackground
    anchors.fill: parent
    visible: root.hullVisible && root.backgroundMode === Constants.Background.Gradient
    gradientType: effect.configuration.BackgroundGradientType
    gradientStop: effect.configuration.BackgroundGradientStop
    firstColor: effect.configuration.BackgroundColor
    secondColor: effect.configuration.BackgroundColor2
    // FollowCube/Inverse (ADR-017): the camera yaw is the same azimuth the
    // cube uses for desktop selection, so the layer turns with the solid.
    // toEulerAngles() costs a quaternion decomposition; it is only needed
    // while the gradient hull is the active background (ADR-022): with the
    // layer hidden or Fixed the binding was decomposing every frame for a
    // value nothing read.
    gradientRotation: effect.configuration.BackgroundGradientRotation
    yaw: root.backgroundMode === Constants.Background.Gradient ? cameraController.rotation.toEulerAngles().y : 0
  }

  // Hull: flat image (Background == Image, not wrapping the scene). The
  // solid colour shows while the picture loads and when none is configured.
  // The source is cleared when the layer is hidden or the effect is off:
  // Image decodes its source even while invisible, and a 360 panorama is
  // already decoded by the SkyBox texture, so loading it here as well would
  // double its memory.
  Rectangle {
    id: flatImageHull
    anchors.fill: parent
    visible: root.hullVisible && root.showFlatImage
    color: effect.configuration.BackgroundColor
    Image {
      anchors.fill: parent
      source: root.showFlatImage && root.backgroundsActive ? root.backgroundImageSource : ""
      fillMode: {
        switch (root.flatImageFit) {
        case Constants.BackgroundImageFit.Contain:
          return Image.PreserveAspectFit;
        case Constants.BackgroundImageFit.Stretch:
          return Image.Stretch;
        default:
          return Image.PreserveAspectCrop;
        }
      }
      asynchronous: true
    }
  }

  // Hull: video (Background == Video). Its own file + Loader isolate the
  // QtMultimedia import: if the module is missing the Loader ends in Error,
  // qWarning fires once and the solid colour below keeps the hull painted.
  // The Loader is a direct child (never inside a hidden container) because
  // the same item doubles as Texture.sourceItem of the 360 dome; the item
  // stays alive once shown and pauses with effect.visible.
  //
  // "Nothing is painted" has several causes that look identical on screen
  // (module missing, clip unreadable, decoder refusing inside KWin's process,
  // a path the media backend cannot open), so the effect says in the log,
  // once, which of them it is. Without this the only way to know is to guess.
  Loader {
    id: videoLoader
    anchors.fill: parent
    // drawOnThisScreen (ADR-022, second review): KWin creates one SceneView
    // per output even with CursorScreenOnly, and an active Loader decodes —
    // without the gate every screen ran its own MediaPlayer for a view
    // that is never painted. drawOnThisScreen is true whenever
    // CursorScreenOnly is off, so the single-screen case is untouched.
    active: root.videoActive && root.drawOnThisScreen
    visible: root.hullVisible && root.showFlatVideo
    source: "HullVideo.qml"
    onStatusChanged: {
      if (status === Loader.Error && !root.videoWarningShown) {
        root.videoWarningShown = true;
        console.warn("kube-effect: background video unavailable (is qt6-multimedia installed?); using the background colour");
      }
    }
    onLoaded: {
      // Bindings on the created item: the KCM can change the clip or the
      // fit while the effect is loaded, and effect.visible must pause it.
      item.source = Qt.binding(() => root.backgroundVideoSource);
      item.fit = Qt.binding(() => root.flatImageFit);
      // The dome samples this very item: while it wraps the scene the
      // output must show the full frame (Stretch), not the flat fit.
      item.dome = Qt.binding(() => root.videoSkyBox);
      item.playing = Qt.binding(() => effect.visible);
      videoDiagnosis.restart();
    }
  }

  // Loader.Ready only proves the QML built: the clip may still fail to decode.
  // 3 s after the item appears, if there is still no frame, report the media
  // status and error text. mediaStatus values (QtMultimedia QMediaStatus):
  // 0 NoMedia, 1 Loading, 2 Loaded, 3 Stalled, 4 Buffering, 5 Buffered,
  // 6 EndOfMedia, 7 InvalidMedia.
  Timer {
    id: videoDiagnosis
    interval: 3000
    onTriggered: {
      // The clip pauses (and legitimately stops advancing) with the
      // effect closed: diagnosing then is a false positive (ADR-022).
      if (root.videoWarningShown || !root.videoActive || !effect.visible) {
        return;
      }
      const item = videoLoader.item;
      if (item === null || item === undefined) {
        return;
      }
      if (item.frameAvailable) {
        return;
      }
      root.videoWarningShown = true;
      console.warn("kube-effect: vídeo de fondo sin fotograma tras 3 s" + " (mediaStatus=" + item.mediaStatus + ", error=" + item.errorString + ")" + "; fuente=" + root.backgroundVideoSource + "; se pinta el color de respaldo");
    }
  }

  // Advanced: black veil over the hull (not over the faces) while the cube
  // moves. "Moving" is cameraController.busy (pointer drag) or the rotation
  // Behavior's animation (arrow keys, activation and desktop switch); the
  // radius animation is a zoom, not a turn, so it is ignored. effect.activated
  // alone would dim an idle cube too. The short Behavior keeps a drag from
  // strobing when the pointer pauses for a frame.
  // This veil dims the 2D hull only: color, gradient and the flat image. Once
  // the SkyBox is painted it stays off, because that background belongs to
  // the 3D environment and is dimmed with probeExposure instead (see
  // skyBoxExposure); while the panorama is still decoding the layer below is
  // the solid fallback colour and dimming it is fine, so no frame goes
  // undimmed and no frame is dimmed twice.
  Rectangle {
    id: hullDim
    anchors.fill: parent
    color: "black"
    visible: opacity > 0
    opacity: root.cubeMoving && !root.skyBoxPainted ? Constants.dimOpacity(effect.configuration.DimWhileRotating === true, effect.configuration.DimWhileRotatingAmount) : 0
    Behavior on opacity {
      NumberAnimation {
        duration: 120
        easing.type: Easing.OutQuad
      }
    }
  }

  // DebugOverlay (ADR-023): the two state lines from debugInfo, painted over
  // everything (z: 100) while the Advanced key is on. Nothing is composed
  // when it is off (see debugInfo), so the default stays free.
  Text {
    id: debugOverlay
    visible: effect.configuration.DebugOverlay === true
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: 6
    z: 100
    color: "red"
    // Outline: the overlay is the ONLY visible diagnostic channel, so it
    // must stay readable over a light wallpaper (and line 2 stays one
    // line: no wrap, the text runs off a small screen instead).
    style: Text.Outline
    styleColor: "black"
    font.pixelSize: 14
    font.family: "monospace"
    text: root.debugInfo
  }

  View3D {
    id: view
    anchors.fill: parent
    // TODO: Use the Underlay mode again when the QtQuick3D renderer accounts for QQuickRenderTarget::mirrorVertically().
    renderMode: View3D.Offscreen

    // ONE SceneEnvironment for the whole lifetime of the view (ADR-022).
    // The previous pair of Loaders destroyed and rebuilt the environment
    // on every mode flip (mid-animation even), churning the scene's render
    // setup; backgroundMode now toggles in place: Transparent while the
    // SkyBox is not painting — which covers Color/Gradient/flat image/flat
    // video and the 360 video dome (a sphere inside the scene needs a
    // transparent environment behind it) — and SkyBox once the probe is
    // Ready. Never bind the window colour here; it outlives the effect.
    // Honesty note (second review): KWin DESTROYS the SceneView on every
    // deactivation (QuickSceneEffect::stopInternal; view caching is
    // off and not a Q_PROPERTY), so the panorama re-decodes per activation
    // no matter what QML holds: keeping the texture across activations
    // needs view caching in C++ (outside the QML-only contract). The
    // probe gate below still avoids decoding while the effect is off or on
    // screens that never paint (drawOnThisScreen, same multi-monitor
    // reason as the skyBoxProbe).
    environment: SceneEnvironment {
      backgroundMode: root.skyBoxImageReady ? SceneEnvironment.SkyBox : SceneEnvironment.Transparent
      lightProbe: Texture {
        source: root.skyBoxImageReady && root.drawOnThisScreen ? root.backgroundImageSource : ""
      }
      // Dimming for this mode (see skyBoxExposure): probeExposure is the
      // environment's brightness, so it darkens the panorama and nothing
      // else. The object is never re-created; the value is animated.
      probeExposure: root.skyBoxExposure
      Behavior on probeExposure {
        NumberAnimation {
          duration: 120
          easing.type: Easing.OutQuad
        }
      }
    }

    PerspectiveCamera {
      id: camera
      clipNear: 10.0
      clipFar: 100000.0
      // Headlight for the slab edges (ADR-028 fourth amendment, the
      // "read as a solid" fix measured 2026-11-28): an unlit edge material
      // is a flat colour that reads as a shadow ("solo un cuadro como
      // sombreado"), not as volume. A soft directional light rides on the
      // camera (its own +Z is the view direction; a child of the camera
      // inherits it) with a fixed euler offset so the four edge
      // orientations of the box catch visibly DIFFERENT shading instead of
      // one flat silhouette. The light is built ONLY while the layers can
      // exist: a Repeater3D with model 0 instantiates ZERO nodes, so a
      // virgin cube (WindowLayering false) keeps byte-for-byte the scene
      // tree of before - the strict parity the ADR demands, this time on
      // the light side. It illuminates nothing else: every other material
      // of the effect (faces, fronts, plate, caps, hull) is NoLighting by
      // the ADR-026 contract, so Fragment materials feel it and the rest
      // never does.
      Repeater3D {
        id: headlightRepeater
        model: effect.configuration.WindowLayering === true ? 1 : 0
        DirectionalLight {
          eulerRotation: Qt.vector3d(25, -35, 0)
          color: "#ffffff"
          // Soft headlight: brightness (Qt 6.12 spelling; "intensity" is
          // Qt3D's, and the live loader here rejects it - measured), kept
          // under 1 so the rim reads volume without bleaching the dark
          // edge tone.
          brightness: 0.8
          castsShadow: false
        }
      }
    }

    // Video 360 (Background == Video, Equirect + rotate): a sphere seen from
    // the inside, sitting on the camera position but NOT on its rotation, so
    // the clamp turns with the view like a real skybox. The panorama is fed
    // by Texture.sourceItem of the HullVideo VideoOutput, which Qt Quick 3D
    // accepts on a material (it rejects it as a light probe). Radius = mesh
    // 50 * scale 100 = 5000, far inside clipFar and far outside the cube.
    Model {
      id: videoDome
      visible: root.videoDomePainted
      source: "#Sphere"
      position: camera.position
      scale: Qt.vector3d(100, 100, 100)
      materials: PrincipledMaterial {
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.FrontFaceCulling
        baseColorMap: Texture {
          sourceItem: root.videoProbeItem
        }
      }
    }

    // Dimming for the video dome: a black sphere just inside it, with the
    // same 120 ms ramp as the 2D veil (skyBoxExposure is 1 - dimOpacity, so
    // 1 - exposure is the veil alpha when the cube turns). Depth testing
    // keeps it off the cube faces, which sit much closer.
    Model {
      id: videoDomeDim
      visible: root.videoDomePainted && root.videoDomeVeil > 0.001
      source: "#Sphere"
      position: camera.position
      scale: Qt.vector3d(99, 99, 99)
      materials: PrincipledMaterial {
        lighting: PrincipledMaterial.NoLighting
        cullMode: Material.FrontFaceCulling
        baseColor: "black"
        opacity: root.videoDomeVeil
      }
    }

    Cube {
      id: cube
      faceDisplacement: effect.configuration.CubeFaceDisplacement
      faceOpacity: root.faceOpacity
      // Window layers pile opacity (ADR-028 as amended): the resolved +
      // animated value above, forwarded untouched down to WindowLayers.
      layerOpacity: root.layerOpacity
      // Shape (ADR-025): resolved here through Constants.shape() so a
      // hand-edited kwinrc value can only ever mean Polygon; below 3
      // desktops it picks the representation (flat sheet vs the
      // three-slot drum, ADR-024/ADR-025 pt.11 re-rectified).
      shape: Constants.shape(effect.configuration.Shape)
      // Caps (ADR-027): raw config values; Cube resolves every enum /
      // range through the pure constants.js helpers, so a hand-edited
      // kwinrc cannot reach the paint with a broken index. Defaults
      // are off (CapTop/CapBottom false): nothing loads without the
      // user asking for it.
      capTop: effect.configuration.CapTop
      capBottom: effect.configuration.CapBottom
      // With the overlay on, the caps force the Arrow marker whatever
      // CapContent says (ADR-027 amendment 2, see Cube.qml): the same
      // flag that already exposes yaw/pitch/d/v becomes the diagnostic
      // for rotation and mirroring.
      debugOverlay: effect.configuration.DebugOverlay === true
      capContent: effect.configuration.CapContent
      capColor: effect.configuration.CapColor
      capColor2: effect.configuration.CapColor2
      capGradientType: effect.configuration.CapGradientType
      capGradientStop: effect.configuration.CapGradientStop
      capImage: effect.configuration.CapImage
      capImageFit: effect.configuration.CapImageFit
      capOpacity: effect.configuration.CapOpacity
      // Window layers (ADR-028): raw config values again (the caps
      // pattern); Cube resolves every range through layerGeometry.js, so
      // a hand-edited kwinrc cannot reach the scene with an out-of-range
      // gap, LOD face count or plate alpha. Default off: pixel parity
      // with the cube of before. currentDesktop feeds the LOD distance
      // (root.currentDesktop already follows onCurrentDesktopChanged).
      windowLayering: effect.configuration.WindowLayering === true
      windowLayerGap: effect.configuration.WindowLayerGap
      windowLayerLodFaces: effect.configuration.WindowLayerLodFaces
      windowLayerPlateOpacity: effect.configuration.WindowLayerPlateOpacity
      // Slab thickness arrives as the REQUEST; layerGeometry.thicknessEffective
      // clips it to half the fitted step where the step is known (WindowLayers).
      // The edge colour arrives as the raw KConfig string; Cube re-resolves it
      // through layerGeometry.edgeColor so garbage never reaches the scene.
      windowLayerThickness: effect.configuration.WindowLayerThickness
      windowLayerEdgeColor: effect.configuration.WindowLayerEdgeColor
      currentDesktop: root.currentDesktop
      // Live camera distance for the culling seed kept ready
      // (ADR-025 point 12 reverted): the runtime ignores it
      // (faceCullMode is pinned to NoCulling) but the documented
      // alternative and scripts/check-cylinder-wiring.py drive it
      // through cylinderCullMode(). cameraController is declared later in
      // this same component — QML ids resolve component-wide, the
      // binding re-evaluates like the gradient-yaw one.
      cameraRadius: cameraController.radius
      faceSize: Qt.size(root.width, root.height)
      // The yaw feeds only the debug overlay now that the face LOD is
      // retired (ADR-023): debugEuler decomposes the quaternion once,
      // gated on DebugOverlay (the gradient-yaw pattern, ADR-022).
      cameraYaw: root.debugEuler.y
      // Screen identity for DesktopView, explicit (ADR-022): no dynamic
      // scope through Cube/Repeater3D into this root.
      screenName: root.targetScreen !== null && root.targetScreen !== undefined ? root.targetScreen.name : ""
      screenGeometry: root.targetScreen !== null && root.targetScreen !== undefined ? root.targetScreen.geometry : Qt.rect(0, 0, 0, 0)
    }

    CubeCameraController {
      id: cameraController
      anchors.fill: parent
      state: effect.activated ? "distant" : "close"
      camera: camera
      xInvert: effect.configuration.MouseInvertedX
      yInvert: effect.configuration.MouseInvertedY
      // Turn range (ADR-024 / ADR-026 routing), see root.azimuthRange:
      // the flat sheet answers [-80, 80] with one desktop (mirrored
      // back rule) and none with two; EVERY cylinder with the arc mesh
      // — drum at 3+, three-slot drum at 1-2 — is open, free wrap: the
      // asymmetric band [-60, 60] / [-60, 180] the user tested at the
      // grill was retired (it "made jumps and felt choppy"; a DRAG may
      // park on an empty slot, where the hull shows — a valid resting
      // view, selection there is the guarded no-op; the ARROWS never
      // park there, ADR-026b cycles the real faces). Same live
      // inputs Cube branches on. The range alone is
      // not enough when the count or the shape CHANGES mid-open —
      // interaction kills the state bindings — so the handlers below
      // rewrite rotation/radius from the current state's formulas.
      azimuthMin: root.azimuthRange[0]
      azimuthMax: root.azimuthRange[1]
      // Zoom limits relative to the solid (ADR-022): safeViewRadius is
      // positive by construction — the sheet's half-face, or the polygon
      // apothem, whose displacement can be negative (KCM range -500..500,
      // pre-ADR-024 bug: negative limits let the wheel dive the camera
      // inside the solid).
      minRadius: cube.safeViewRadius * 0.6
      maxRadius: cube.safeViewRadius * 8

      states: [
        State {
          name: "close"
          PropertyChanges {
            target: cameraController
            radius: closeRadius()
            rotation: Quaternion.fromEulerAngles(0, targetAzimuth(), 0)
          }
        },
        State {
          name: "distant"
          PropertyChanges {
            target: cameraController
            radius: distantRadius()
            rotation: Quaternion.fromEulerAngles(0, targetAzimuth(), 0).times(Quaternion.fromEulerAngles(-20, 0, 0))
          }
        }
      ]

      Behavior on rotation {
        enabled: !cameraController.busy
        QuaternionAnimation {
          id: rotationAnimation
          duration: effect.animationDuration
          easing.type: Easing.OutCubic
        }
      }
      Behavior on radius {
        NumberAnimation {
          duration: effect.animationDuration
          easing.type: Easing.OutCubic
        }
      }

      // State target yaw: the desktop's own azimuth, put through the
      // range clamp (ADR-024/ADR-026). desktopAzimuth already answers
      // inside the range for sheets (0 or 180 with the count's own
      // tick), the cylinder is open so verbatim lands on the slot's
      // grid azimuth (0/120/... — with 1 desktop slot 0, the face is
      // ALWAYS front-facing when the effect opens), and with an open
      // range clampAzimuthRange returns the angle verbatim — exactly
      // the pre-sheet behaviour; only a real range normalizes.
      function targetAzimuth() {
        // Bare names: azimuthMin/azimuthMax resolve on this
        // controller (the object the function is declared in),
        // currentDesktop and cube through ScreenView's component
        // scope (as in the states).
        return Constants.clampAzimuthRange(cube.desktopAzimuth(currentDesktop), azimuthMin, azimuthMax);
      }

      // Camera distance that makes a face of faceSize.height fill the
      // screen vertically; both state radii sit on top of it.
      function faceFit() {
        return 0.5 * cube.faceSize.height / Math.tan(0.5 * camera.fieldOfView * Math.PI / 180);
      }

      function closeRadius() {
        return cube.faceDistance + faceFit();
      }

      function distantRadius() {
        return cube.safeViewRadius * effect.configuration.DistanceFactor + faceFit();
      }

      // Force the live state's values after a shape change while the
      // effect stays open (ADR-024 review): the states' PropertyChanges
      // are live bindings only until the first interaction — a drag,
      // arrow or wheel assignment KILLS them — so with 2->1 desktops and
      // yaw at 170 the new ±80 clamp was never applied (the mirrored
      // back of the single quad showed), 2->3 left yaw at 180 (Enter or
      // a click then selected desktop 3, not the current one), and the
      // radius stayed the old solid's (2616 vs 2080). Rewriting
      // rotation/radius here is idempotent while the bindings are still
      // alive, and it survives their death: the next state flip (every
      // deactivate/activate re-applies PropertyChanges) rebuilds them.
      function resyncToState() {
        const euler = rotation.toEulerAngles();
        // Keep the current elevation (the states' own pitch comes from
        // the -20 distant quaternion, already inside euler.x after a
        // settled transition); re-aim the yaw at the new shape.
        rotation = Quaternion.fromEulerAngles(euler.x, targetAzimuth(), 0);
        radius = state === "distant" ? distantRadius() : closeRadius();
      }

      // The live list of face azimuths, straight from Cube.faceAzimuth
      // (the same function the delegate places the faces with). Used on
      // limited ranges — the sheet, where every stop must be real — and
      // on open ranges WITH HOLES in the grid, the three-slot drum at
      // 1-2 desktops (ADR-026b: the arrows cycle the real faces, never
      // the empty slot; arrowAzimuth decides from the list length).
      function faceAzimuthList() {
        const out = [];
        for (let i = 0; i < cube.faceCount; ++i) {
          out.push(cube.faceAzimuth(i));
        }
        return out;
      }

      function rotateToLeft() {
        if (rotationAnimation.running) {
          return;
        }
        const eulerAngles = rotation.toEulerAngles();
        // ADR-025 point 13 + ADR-026b: with a range (the sheet-1) the
        // arrow cycles the REAL faces instead of clamping a raw tick to
        // an edge; with an open range whose grid has HOLES (the
        // three-slot drum at 1-2 desktops) the arrow advances to the
        // next REAL face with a full wrap — 0 <-> 120 from either side,
        // never the empty slot at 240 («no se puede pasar», measured).
        // Open ranges with a FULL grid — polygon, sheet-2, drum at 3+ —
        // keep the old tick arithmetic verbatim. The drag path clamps
        // raw bounds in CubeCameraController: edges, not faces, and a
        // drag may still park facing the hull — from there the arrows
        // move to the closest real face in the requested direction.
        const next = Constants.arrowAzimuth(eulerAngles.y, -1, cube.angleTick, azimuthMin, azimuthMax, faceAzimuthList());
        rotation = Quaternion.fromEulerAngles(0, next - eulerAngles.y, 0).times(rotation);
      }

      function rotateToRight() {
        if (rotationAnimation.running) {
          return;
        }
        const eulerAngles = rotation.toEulerAngles();
        // ADR-025 point 13 + ADR-026b, mirrored: limited ranges cycle
        // the real faces (the one-desktop sheet holds); open ranges
        // with holes in the grid — the 1-2 drum — take the next REAL
        // face with a full wrap (0 <-> 120, never 240); open ranges
        // with a full grid (drum 3+, polygon, sheet-2) step the raw
        // tick verbatim as always.
        const next = Constants.arrowAzimuth(eulerAngles.y, 1, cube.angleTick, azimuthMin, azimuthMax, faceAzimuthList());
        rotation = Quaternion.fromEulerAngles(0, next - eulerAngles.y, 0).times(rotation);
      }
    }
  }

  MouseArea {
    anchors.fill: view
    onClicked: mouse => {
      const hitResult = view.pick(mouse.x, mouse.y);
      if (hitResult.objectHit) {
        root.switchTo(hitResult.objectHit.desktop);
      } else {
        root.switchToSelected();
      }
    }
  }

  Keys.onEscapePressed: effect.deactivate()
  Keys.onLeftPressed: cameraController.rotateToLeft()
  Keys.onRightPressed: cameraController.rotateToRight()
  Keys.onEnterPressed: root.switchToSelected()
  Keys.onReturnPressed: root.switchToSelected()
  Keys.onSpacePressed: root.switchToSelected()

  // Shape re-sync (ADR-024 review): faceCount is the only Cube input the
  // camera state derives from that can change while the effect is open
  // (desktops added/removed mid-animation, and the transient 0..2 counts of
  // a model sync). One handler covers clamp, alignment and radius; the
  // Behavior on rotation animates the correction unless a drag is active.
  Connections {
    target: cube
    function onFaceCountChanged() {
      cameraController.resyncToState();
    }
    // Shape switch with the cube open (KCM change, or the arc mesh
    // appearing/failing — ADR-025): same story as a desktop-count change,
    // the state bindings may be dead and R replaced the apothem (or the
    // drum replaced the flat sheet, with its own radius and open range),
    // so rewrite rotation/radius from the live shape. One handler covers
    // every cylinder flip (the segment branch retired with ADR-025
    // pt.11's three-slot design); everything else goes through
    // onFaceCountChanged.
    function onCylinderActiveChanged() {
      cameraController.resyncToState();
    }
    // R changes WITH the drum in effect (ADR-025, review): the KCM can
    // move CubeFaceDisplacement while the cube is open and a screen
    // resize re-runs R = N(W+g)/2pi; the state radius bindings may be
    // dead, so re-apply the live state. Gated on cylinderActive: the
    // polygon (whose apothem moves the same way) and the flat sheet keep
    // the exact pre-cylinder behaviour — no new resync paths for them.
    function onCylinderRadiusChanged() {
      if (cube.cylinderActive) {
        cameraController.resyncToState();
      }
    }
    function onFaceSizeChanged() {
      if (cube.cylinderActive) {
        cameraController.resyncToState();
      }
    }
  }

  Connections {
    target: KWinComponents.Workspace
    function onCurrentDesktopChanged(previous, current, screen) {
      if (screen !== root.targetScreen) {
        return;
      }

      root.currentDesktop = current;
      // ADR-024 review: KWin may change the CURRENT desktop while the
      // effect is open (a removal lands on a neighbour). The state's
      // rotation binding is dead after any interaction, so re-aim
      // explicitly instead of waiting for the next activate.
      if (effect.activated) {
        cameraController.resyncToState();
      }
    }
  }
}
