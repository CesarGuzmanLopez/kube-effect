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
// The material is the ADR-026 rule extended to the caps (overlap fix):
// NoLighting (the cap is a flat UI surface, not a lit object), NoCulling
// (parity with the faces, ADR-023/ADR-025 pt.12: the cap reads the same
// from above and below, and the bottom one is the SAME mesh on a node
// rotated 180 deg about Z, so culling would delete it), and an alphaMode
// that follows the opacity threshold exactly like CubeFace: Mask at rest
// (>= 0.99: the kept fragments WRITE DEPTH, so no sort tie can ever paint
// a far cap over a near face) and Blend while translucent (the default
// CapOpacity 80 stays a real see-through cap, back-to-front by the node
// centroids at y = +/- faceHeight/2). NOT SetToOpaque/Opaque: measured in
// ADR-026, those paint the texture's alpha holes BLACK. alphaCutoff is
// pinned explicitly (CubeFace's lesson: Qt's default could move the hard
// edge under a future Qt). The pixel gate scripts/check-cap-overlap.py
// asserts both regimes and the depth consequence.
//
// The content is a plain 2D Item used as Texture.sourceItem (no shaders):
// a Rectangle for the colour, the reused HullGradient for the gradient
// (Fixed rotation: the cap turns with the solid anyway), an Image for the
// picture and CapArrow.qml (behind its own Loader) for the Arrow marker —
// the schema default, the only content that can be READ as oriented. A
// broken or absent image falls back to CapColor and asks Cube to warn ONCE
// (imageUnavailable, the background-video pattern of ADR-020); a missing
// QtQuick.Shapes degrades the arrow the same way (surfaceDegraded, the
// HullRadial pattern of ADR-022).
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
    // Emitted once when the Arrow content cannot paint (QtQuick.Shapes
    // missing -> CapArrow.qml's Loader is in Error): the cap keeps its
    // CapColor background, exactly the HullRadial degradation of ADR-022.
    // The SAME one-line budget applies (Cube dedupes with capImageWarned).
    signal surfaceDegraded(string reason)

    // One report per instance is the cap's own budget; Cube still filters
    // the global duplicate (the radialWarned pattern of HullGradient).
    property bool reported: false
    property bool degradedReported: false

    readonly property bool imageReady: capImage.status === Image.Ready
    readonly property bool imageUsable: cap.imageSource.length > 0 && cap.imageReady
    readonly property bool paintColor: cap.content === Constants.CapContent.Color || (cap.content === Constants.CapContent.Image && !cap.imageUsable)
    readonly property bool paintImage: cap.content === Constants.CapContent.Image && cap.imageUsable
    // CapContent Arrow (the schema default): the orientation marker of
    // CapArrow.qml. Its Loader's Error state feeds back into paintColor, so
    // without QtQuick.Shapes the cap degrades to a plain CapColor surface.
    readonly property bool paintArrow: cap.content === Constants.CapContent.Arrow

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
            alphaMode: cap.opacityValue >= 0.99 ? PrincipledMaterial.Mask : PrincipledMaterial.Blend
            alphaCutoff: 0.5
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
                        // Also the Arrow fallback: when CapArrow.qml cannot
                        // load (no QtQuick.Shapes) the plain colour holds.
                        visible: cap.paintColor || (cap.paintArrow && arrowLoader.status === Loader.Error)
                        color: cap.color1
                    }

                    Loader {
                        id: arrowLoader
                        anchors.fill: parent
                        visible: cap.paintArrow && status === Loader.Ready
                        // Isolated behind a Loader (the HullRadial / HullVideo
                        // pattern): CapArrow.qml is the ONLY cap file that
                        // imports QtQuick.Shapes, so a system without the
                        // module only errors HERE — the cap falls back to the
                        // CapColor Rectangle above and warns once.
                        active: cap.paintArrow
                        source: "CapArrow.qml"
                        onStatusChanged: {
                            if (status === Loader.Error && !cap.degradedReported) {
                                cap.degradedReported = true;
                                cap.surfaceDegraded("QtQuick.Shapes unavailable; the cap marker cannot paint");
                            }
                        }
                        onLoaded: {
                            item.color1 = Qt.binding(() => cap.color1);
                        }
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
