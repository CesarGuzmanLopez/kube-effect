import QtQuick

// Runs inside scripts/check-video.py. Two Loaders reproduce what ScreenView.qml
// does with the video hull: one builds the real HullVideo.qml (which imports
// QtMultimedia), the other points at a missing file to prove the fallback path
// (Loader.Error) leaves the rest of the scene alive.
Item {
    id: root

    property bool ok: true
    property string log: ""
    property url videoUrl
    property url brokenUrl
    property bool expectModule: true

    readonly property var videoItem: videoLoader.item
    readonly property int videoStatus: videoLoader.status
    readonly property bool videoHasItem: videoLoader.item !== null && videoLoader.item !== undefined
    readonly property bool videoExposesOutput: root.videoHasItem && videoLoader.item.videoOutput !== null && videoLoader.item.videoOutput !== undefined
    readonly property int brokenStatus: brokenLoader.status
    readonly property bool brokenHasItem: brokenLoader.item !== null && brokenLoader.item !== undefined

    function check(name, actual, expected) {
        const passed = actual === expected;
        const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected " + expected + ")");
        log = log.length > 0 ? log + "\n" + line : line;
        if (!passed)
            ok = false;
    }

    function run() {
        if (root.expectModule) {
            check("HullVideo loader status", root.videoStatus, Loader.Ready);
            check("HullVideo item created", root.videoHasItem, true);
            check("HullVideo exposes its VideoOutput", root.videoExposesOutput, true);
            // The harness sets a non-existent clip on it before running: an
            // unreadable file is a media error, never a QML error.
            check("item survives a bad clip", root.videoHasItem, true);
        } else {
            // QtMultimedia is not installed: only this item fails. The scene
            // keeps its item and ScreenView paints the colour fallback.
            check("missing QtMultimedia -> Loader.Error", root.videoStatus, Loader.Error);
            check("missing QtMultimedia -> no item, effect alive", root.videoHasItem, false);
        }
        // Fill modes (ADR-020 fix): the 360 dome must always receive the FULL
        // frame (VideoOutput.Stretch = 0) whatever the user's fit is, while the
        // flat layer keeps honouring BackgroundImageFit (Cover=0 -> crop=2,
        // Contain=1 -> fit=1, Stretch=2 -> stretch=0).
        if (root.expectModule && root.videoHasItem) {
            const video = root.videoItem;
            const output = video.videoOutput;
            video.dome = false;
            video.fit = 0;
            check("flat Cover -> PreserveAspectCrop", output.fillMode, 2);
            video.fit = 1;
            check("flat Contain -> PreserveAspectFit", output.fillMode, 1);
            video.fit = 2;
            check("flat Stretch -> Stretch", output.fillMode, 0);
            video.dome = true;
            video.fit = 0;
            check("dome forces Stretch (Cover)", output.fillMode, 0);
            video.fit = 1;
            check("dome forces Stretch (Contain)", output.fillMode, 0);
            video.fit = 2;
            check("dome forces Stretch (Stretch)", output.fillMode, 0);
        }
        // Simulated fallback: a Loader whose source does not exist must end in
        // Error and must not take the rest of the scene with it.
        check("broken source -> Loader.Error", root.brokenStatus, Loader.Error);
        check("broken source -> no item", root.brokenHasItem, false);
    }

    Loader {
        id: videoLoader
        asynchronous: false
        source: root.videoUrl
    }

    Loader {
        id: brokenLoader
        asynchronous: false
        source: root.brokenUrl
    }
}
