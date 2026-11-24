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
    readonly property bool equirectMapping: Constants.usesEquirectMapping(effect.configuration.BackgroundImageMapping, root.backgroundImageSet)

    // An equirectangular image that rotates with the centre is the only case
    // rendered as a 3D SkyBox; everything else is a flat full-screen layer.
    // BackgroundImageRotate defaults to true, so an unset value still rotates.
    readonly property bool skyBoxBackground: root.backgroundMode === Constants.Background.Image && root.equirectMapping && effect.configuration.BackgroundImageRotate !== false && root.backgroundImageSet
    // Flat hull layer: Image mode that does not wrap the scene. A skybox keeps
    // it off so the panorama is decoded once (by the 3D texture), not twice.
    readonly property bool showFlatImage: root.backgroundMode === Constants.Background.Image && !root.skyBoxBackground
    // QtQuick3D's Texture exposes no load status (checked in Qt 6.12), so a tiny
    // probe decodes the file first: until it is ready (or on a broken path) the
    // transparent environment keeps the colour backdrop instead of an empty
    // black SkyBox. The probe is decoded at 64 px wide, not full size.
    readonly property bool skyBoxImageReady: root.skyBoxBackground && skyBoxProbe.status === Image.Ready

    // The hull (background behind the 3D view) must disappear together with
    // the effect. Binding Window.color kept the window surface painted after
    // deactivation, so the hull is painted here instead, gated by effect.visible
    // (still true during the closing animation, false once it ends).
    readonly property bool hullVisible: effect.visible

    Image {
        id: skyBoxProbe
        visible: false
        source: root.skyBoxBackground ? root.backgroundImageSource : ""
        sourceSize.width: 64
        asynchronous: true
    }

    // Hull: solid colour (Background == Color).
    Rectangle {
        id: colorBackground
        anchors.fill: parent
        visible: root.hullVisible && root.backgroundMode === Constants.Background.Color
        color: effect.configuration.BackgroundColor
    }

    // Hull: two-colour gradient without shaders (Background == Gradient).
    // LinearVertical/LinearHorizontal map to Gradient.orientation; Radial has
    // no QtQuick primitive without shaders, so it falls back to LinearVertical
    // (TODO: true radial when QtQuick offers it, still without shaders or C++).
    Rectangle {
        id: gradientBackground
        anchors.fill: parent
        visible: root.hullVisible && root.backgroundMode === Constants.Background.Gradient
        gradient: Gradient {
            orientation: effect.configuration.BackgroundGradientType === Constants.BackgroundGradientType.LinearHorizontal ? Gradient.Horizontal : Gradient.Vertical
            GradientStop {
                position: 0.0
                color: effect.configuration.BackgroundColor
            }
            GradientStop {
                position: effect.configuration.BackgroundGradientStop / 100.0
                color: effect.configuration.BackgroundColor2
            }
            GradientStop {
                position: 1.0
                color: effect.configuration.BackgroundColor2
            }
        }
    }

    // Hull: flat image (Background == Image, not wrapping the scene). The
    // solid colour shows while the picture loads and when none is configured.
    // The source is cleared when the layer is hidden: Image decodes its source
    // even while invisible, and a 360 panorama is already decoded by the SkyBox
    // texture, so loading it here as well would double its memory.
    Rectangle {
        id: flatImageHull
        anchors.fill: parent
        visible: root.hullVisible && root.showFlatImage
        color: effect.configuration.BackgroundColor
        Image {
            anchors.fill: parent
            source: root.showFlatImage ? root.backgroundImageSource : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
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
            active: root.skyBoxBackground
            sourceComponent: SceneEnvironment {
                backgroundMode: SceneEnvironment.SkyBox
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
