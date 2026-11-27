/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import "constants.js" as Constants

// One closing cap of the solid (ADR-027): a flat mesh (shared ProceduralMesh,
// CapMesh.qml) painted with its own content — solid colour, gradient or local
// image — and its own transparency.
//
// The material is the ADR-026 rule extended to the caps: NoLighting (the cap
// is a flat UI surface, not a lit object), NoCulling (parity with the faces,
// ADR-023/ADR-025 pt.12: the cap reads the same from above and below, and
// the bottom one is the SAME mesh on a node rotated 180 deg, so culling
// would delete it), Blend always (the content carries alpha by default:
// CapOpacity 80). Each Cap Model sits at y = +/- faceHeight/2, so it brings
// its own sort centroid on Y and can never paint over the front faces.
//
// The content is a plain 2D Item used as Texture.sourceItem (no shaders):
// a Rectangle for the colour, the reused HullGradient for the gradient
// (Fixed rotation: the cap turns with the solid anyway) and an Image for the
// picture. A broken or absent image falls back to CapColor and asks Cube to
// warn ONCE (imageUnavailable, the background-video pattern of ADR-020).
Model {
    id: cap

    // Symbolic marker so the face-walking test harnesses (the collectFaces of
    // check-cylinder-overlap.qml, which treats any node with materials +
    // position + geometry as a face) can tell a cap from a face: the caps are
    // NOT desktop faces and must never join the face-count, radius-centroid or
    // faceOpacity assertions of that gate.
    readonly property bool kubeCapSurface: true

    // Shared geometry from Cube.capMesh (null = no QtQuick3D.Helpers or the
    // loader is not ready: the cap must not render, exactly like the arc).
    property Geometry mesh: null
    // Content, already resolved by Cube through the constants.js helpers
    // (capContent / capGradientType / capImageFit / capOpacity /
    // capImageSource), so an unvalidated kwinrc can never reach the paint.
    property int content: Constants.CapContent.Color
    property color color1: "#1b3fd8"
    property color color2: "#0a1a5e"
    property int gradientType: Constants.CapGradientType.LinearVertical
    property int gradientStop: 50
    property string imageSource: ""
    property int imageFit: Constants.CapImageFit.Cover
    // Material opacity in 0..1 (Constants.capOpacity of the Int 0..100 key).
    property real opacityValue: 0.8
    // Edge of the square surface grabbed as the texture: the mesh UVs map it
    // onto the cap's bounding square, centred (u = 0.5 + x/(2r)). Static
    // content, so it is grabbed once per change, not per frame; 512 keeps a
    // close-up cap readable without taxing the compositor.
    property int surfaceSize: 512

    // Emitted when the Image content is missing or failed to load; Cube
    // turns it into a single console.warn for the whole effect (both caps
    // share one image, two Models must not log twice).
    signal imageUnavailable(string reason)

    // One report per instance is the cap's own budget; Cube still filters
    // the global duplicate (the radialWarned pattern of HullGradient).
    property bool reported: false

    readonly property bool imageReady: capImage.status === Image.Ready
    readonly property bool imageUsable: cap.imageSource.length > 0 && cap.imageReady
    readonly property bool paintColor: cap.content === Constants.CapContent.Color || (cap.content === Constants.CapContent.Image && !cap.imageUsable)
    readonly property bool paintImage: cap.content === Constants.CapContent.Image && cap.imageUsable

    function report(reason) {
        if (cap.reported) {
            return;
        }
        cap.reported = true;
        cap.imageUnavailable(reason);
    }

    source: cap.mesh === null ? "#Rectangle" : ""
    geometry: cap.mesh
    materials: [
        PrincipledMaterial {
            lighting: PrincipledMaterial.NoLighting
            cullMode: Material.NoCulling
            alphaMode: PrincipledMaterial.Blend
            opacity: cap.opacityValue
            baseColorMap: Texture {
                // Surface item (grabbed, never laid into the scene graph):
                // the colour shows through whenever the image is not ready,
                // so a broken source degrades to CapColor without a flash.
                // The explicit sourceItem assignment is the CubeFace pattern.
                sourceItem: Item {
                    id: surface

                    width: cap.surfaceSize
                    height: cap.surfaceSize

                    Rectangle {
                        anchors.fill: parent
                        visible: cap.paintColor
                        color: cap.color1
                    }

                    HullGradient {
                        anchors.fill: parent
                        visible: cap.content === Constants.CapContent.Gradient
                        firstColor: cap.color1
                        secondColor: cap.color2
                        // CapGradientType mirrors BackgroundGradientType in
                        // index and meaning (main.xml); HullGradient resolves
                        // Radial through its own optional-Shapes Loader.
                        gradientType: cap.gradientType
                        gradientStop: cap.gradientStop
                    }

                    Image {
                        id: capImage
                        anchors.fill: parent
                        visible: cap.paintImage
                        source: cap.content === Constants.CapContent.Image ? cap.imageSource : ""
                        fillMode: cap.imageFit === Constants.CapImageFit.Contain ? Image.PreserveAspectFit : (cap.imageFit === Constants.CapImageFit.Stretch ? Image.Stretch : Image.PreserveAspectCrop)
                        asynchronous: true
                        onStatusChanged: {
                            if (status === Image.Error && cap.content === Constants.CapContent.Image) {
                                cap.report("cap image failed to load: " + cap.imageSource);
                            }
                        }
                    }
                }
            }
        }
    ]

    // An Image of an empty source never reaches Error (it stays Null), so the
    // "absent" half of the fallback is checked on the content switch too.
    // Deferred with callLater: when the KCM value arrives, the content and the
    // source bindings update in the SAME pass, and the content handler would
    // otherwise see the not-yet-rebound empty source of a configured image.
    function checkAbsent() {
        if (cap.content === Constants.CapContent.Image && cap.imageSource.length === 0) {
            cap.report("no cap image configured");
        }
    }
    onContentChanged: Qt.callLater(cap.checkAbsent)
    onImageSourceChanged: Qt.callLater(cap.checkAbsent)
}
