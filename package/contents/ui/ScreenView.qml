/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

import "constants.js" as Constants

Item {
    id: root
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    property QtObject currentDesktop: KWinComponents.Workspace.currentDesktopForScreen(root.targetScreen)

    function switchTo(desktop) {
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
    readonly property int backgroundMode: Constants.backgroundMode(effect.configuration.Background)
    readonly property bool equirectMapping: Constants.usesEquirectMapping(effect.configuration.BackgroundImageLayout, root.backgroundImageSet)
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
    // QtQuick3D's Texture exposes no load status (checked in Qt 6.12), so a tiny
    // probe decodes the file first: until it is ready (or on a broken path) the
    // environment stays transparent (no empty black SkyBox), and the colour
    // layer below paints the backdrop instead. The probe is decoded at 64 px
    // wide, not full size.
    readonly property bool skyBoxImageReady: root.skyBoxBackground && skyBoxProbe.status === Image.Ready
    // See the veil below: the cube "moves" while dragging or while the camera
    // rotation animation runs.
    readonly property bool cubeMoving: cameraController.busy || rotationAnimation.running
    // Dimming while rotating reaches all four backgrounds, but never through
    // the same object:
    //   Color / Gradient / flat image -> the 2D veil (hullDim) over the hull.
    //   Image + Equirect (SkyBox 3D)  -> probeExposure of the environment: the
    //     panorama is painted by the 3D scene, not by the 2D layer, so a black
    //     Rectangle in front of the View3D would cover the faces as well.
    // dimOpacity is shared so both modes darken by the same amount, and the
    // 120 ms Behavior mirrors the veil's so neither stutters on a paused drag.
    property real skyBoxExposure: Constants.skyBoxExposure(effect.configuration.DimWhileRotating === true, root.cubeMoving, effect.configuration.DimWhileRotatingAmount)
    Behavior on skyBoxExposure {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    // The hull (background behind the 3D view) must disappear together with
    // the effect. Binding Window.color kept the window surface painted after
    // deactivation, so the hull is painted here instead, gated by effect.visible
    // (still true during the closing animation, false once it ends).
    readonly property bool hullVisible: effect.visible

    // Decoding is not free (a 360 panorama is several MB), so no Image and no
    // skybox texture gets a source until the effect is first shown. visible
    // flips to true in activate(), before the opening animation, and survives
    // the closing one, so the switch happens off screen and cannot flicker.
    readonly property bool backgroundsActive: effect.visible
    // Image + SkyBox paints nothing in 2D (the flat layer is off on purpose)
    // and the 3D environment is transparent until the probe is Ready, so the
    // solid colour has to hold the screen meanwhile; without it the hull would
    // be see-through (or black) on a slow/broken panorama.
    readonly property bool imageFallbackColor: root.backgroundMode === Constants.Background.Image && !root.skyBoxImageReady

    Image {
        id: skyBoxProbe
        visible: false
        source: root.skyBoxBackground && root.backgroundsActive ? root.backgroundImageSource : ""
        sourceSize.width: 64
        asynchronous: true
    }

    // Hull: solid colour (Background == Color), also the backup under Image +
    // SkyBox while the panorama is not painted yet (see imageFallbackColor).
    Rectangle {
        id: colorBackground
        anchors.fill: parent
        visible: root.hullVisible && (root.backgroundMode === Constants.Background.Color || root.imageFallbackColor)
        color: effect.configuration.BackgroundColor
    }

    // Hull: two-colour gradient without shaders (Background == Gradient).
    // Linear orientations are a Rectangle + Gradient; Radial is a real radial
    // painted with QtQuick.Shapes (see HullGradient.qml for why, ADR-013).
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
        // toEulerAngles() is decomposed every frame because the binding must
        // track the camera; with Fixed the value is ignored and nothing repaints.
        gradientRotation: effect.configuration.BackgroundGradientRotation
        yaw: cameraController.rotation.toEulerAngles().y
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
        opacity: root.cubeMoving && !root.skyBoxImageReady ? Constants.dimOpacity(effect.configuration.DimWhileRotating === true, effect.configuration.DimWhileRotatingAmount) : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        // TODO: Use the Underlay mode again when the QtQuick3D renderer accounts for QQuickRenderTarget::mirrorVertically().
        renderMode: View3D.Offscreen

        // Transparent clear: the hull rectangles above paint the background.
        // Never bind the window colour here; it outlives the effect. It is also
        // the fallback while the panorama decodes or fails to load.
        Loader {
            id: transparentSceneEnvironment
            active: !root.skyBoxImageReady
            sourceComponent: SceneEnvironment {
                backgroundMode: SceneEnvironment.Transparent
            }
        }

        // Only active for an equirectangular image that rotates with the
        // centre; an empty source would leave a SkyBox environment with no
        // texture, so skyBoxBackground already requires the image to be set and
        // the environment follows the probe status (see skyBoxImageReady).
        Loader {
            id: skyboxSceneEnvironment
            active: root.skyBoxBackground && root.backgroundsActive
            sourceComponent: SceneEnvironment {
                backgroundMode: SceneEnvironment.SkyBox
                // Dimming for this mode (see skyBoxExposure): probeExposure is
                // the environment's brightness, so it darkens the panorama and
                // nothing else. The item is created once and keeps the binding;
                // the value is animated, the object is never re-created.
                probeExposure: root.skyBoxExposure
                lightProbe: Texture {
                    source: root.backgroundImageSource
                }
            }
        }

        environment: root.skyBoxImageReady ? skyboxSceneEnvironment.item : transparentSceneEnvironment.item

        PerspectiveCamera {
            id: camera
            clipNear: 10.0
            clipFar: 100000.0
        }

        Cube {
            id: cube
            faceDisplacement: effect.configuration.CubeFaceDisplacement
            faceSize: Qt.size(root.width, root.height)
        }

        CubeCameraController {
            id: cameraController
            anchors.fill: parent
            state: effect.activated ? "distant" : "close"
            camera: camera
            xInvert: effect.configuration.MouseInvertedX
            yInvert: effect.configuration.MouseInvertedY

            states: [
                State {
                    name: "close"
                    PropertyChanges {
                        target: cameraController
                        radius: cube.faceDistance + 0.5 * cube.faceSize.height / Math.tan(0.5 * camera.fieldOfView * Math.PI / 180)
                        rotation: Quaternion.fromEulerAngles(0, cube.desktopAzimuth(currentDesktop), 0)
                    }
                },
                State {
                    name: "distant"
                    PropertyChanges {
                        target: cameraController
                        radius: cube.faceDistance * effect.configuration.DistanceFactor + 0.5 * cube.faceSize.height / Math.tan(0.5 * camera.fieldOfView * Math.PI / 180)
                        rotation: Quaternion.fromEulerAngles(0, cube.desktopAzimuth(currentDesktop), 0).times(Quaternion.fromEulerAngles(-20, 0, 0))
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

            function rotateToLeft() {
                if (rotationAnimation.running) {
                    return;
                }
                const eulerAngles = rotation.toEulerAngles();
                let next = Math.floor(eulerAngles.y / cube.angleTick) * cube.angleTick;
                if (Math.abs(next - eulerAngles.y) < 0.05 * cube.angleTick) {
                    next -= cube.angleTick;
                }
                rotation = Quaternion.fromEulerAngles(0, next - eulerAngles.y, 0).times(rotation);
            }

            function rotateToRight() {
                if (rotationAnimation.running) {
                    return;
                }
                const eulerAngles = rotation.toEulerAngles();
                let next = Math.ceil(eulerAngles.y / cube.angleTick) * cube.angleTick;
                if (Math.abs(next - eulerAngles.y) < 0.05 * cube.angleTick) {
                    next += cube.angleTick;
                }
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

    Connections {
        target: KWinComponents.Workspace
        function onCurrentDesktopChanged(previous, current, screen) {
            if (screen !== root.targetScreen) {
                return;
            }

            root.currentDesktop = current;
        }
    }
}
