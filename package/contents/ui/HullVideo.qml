/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Video hull layer (Background == Video).
//
// This is the ONLY file of the effect importing QtMultimedia, and it lives in
// its own file on purpose: QtMultimedia is an optional dependency (package
// qt6-multimedia). ScreenView.qml loads it with a Loader, so on a system
// without the module only THIS item fails to build; the rest of the effect
// keeps working and ScreenView paints the colour fallback. Never move the
// import into another QML file: a top-level import failure kills the whole
// effect.
//
// The clip is painted exactly like an image: ScreenView decides whether it is
// a flat full-screen layer (Flat mapping, or Equirect with "rotate" off) or the
// 360 SkyBox light probe (Equirect + rotate). This file only decodes and
// exposes the VideoOutput; it owns no layout decision beyond BackgroundImageFit.
import QtQuick
import QtMultimedia

import "constants.js" as Constants

Item {
    id: root

    // Local clip only (Constants.videoSource rejects remote URLs): the
    // compositor must not fetch the network when the effect activates.
    property url source
    // BackgroundImageFit value, shared with the flat image: Cover (default),
    // Contain or Stretch. It only applies to the flat layer.
    property int fit: Constants.BackgroundImageFit.Cover
    // True when ScreenView wraps the clip on the 360 dome (Equirect + rotate).
    // The whole frame must reach the texture: an equirect clip is 2:1 by
    // definition and the sphere does the wrapping, so the output STRETCHES.
    // Cover would crop the top and bottom of the panorama (the sky and the
    // ground vanish and the horizon jumps) and Contain would letterbox black
    // bars into the sphere's poles. Measured 2026-11-25 with a 608x304 clip.
    property bool dome: false
    // effect.visible. Pausing (not stopping) keeps the position, so the clip
    // resumes where it was, and a hidden effect decodes nothing.
    property bool playing: false

    // ScreenView uses this item as Texture.sourceItem for the 360 SkyBox.
    readonly property Item videoOutput: output
    // A clip has a video stream once it is loaded; until then the environment
    // is transparent and ScreenView shows the colour fallback (same idea as
    // the Image probe of the picture background).
    readonly property bool frameAvailable: player.hasVideo
    readonly property int mediaStatus: player.mediaStatus
    readonly property string errorString: player.errorString
    function applyPlayback() {
        if (root.playing && root.source.toString().length > 0) {
            player.play();
        } else {
            player.pause();
        }
    }

    onPlayingChanged: root.applyPlayback()
    onSourceChanged: root.applyPlayback()
    Component.onCompleted: root.applyPlayback()

    MediaPlayer {
        id: player
        source: root.source
        // A background loop never ends; a short clip must not freeze on its
        // last frame while the cube keeps turning.
        loops: MediaPlayer.Infinite
        autoPlay: false
        videoOutput: output
        // MediaPlayer has no muted property in Qt 6.12: silence comes from the
        // audio output it renders to.
        audioOutput: AudioOutput {
            muted: true
        }
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        // Dome: always Stretch (see the property). Flat layer: the same three
        // fits as the flat image, so both modes share one setting.
        fillMode: {
            if (root.dome) {
                return VideoOutput.Stretch;
            }
            switch (root.fit) {
            case Constants.BackgroundImageFit.Contain:
                return VideoOutput.PreserveAspectFit;
            case Constants.BackgroundImageFit.Stretch:
                return VideoOutput.Stretch;
            default:
                return VideoOutput.PreserveAspectCrop;
            }
        }
    }
}
