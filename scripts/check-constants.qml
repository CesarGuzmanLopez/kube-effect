import QtQuick
import "../package/contents/ui/constants.js" as Constants

// Runs inside scripts/check-constants.py. The holder `h` exposes QUrl
// properties, i.e. exactly what KConfigLoader hands QML for a Url entry: the
// conversions below are the ones the effect sees in KWin.
Item {
    id: root

    property bool ok: true
    property string log: ""

    function check(name, actual, expected) {
        const passed = actual === expected;
        const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected " + expected + ")");
        log = log.length > 0 ? log + "\n" + line : line;
        if (!passed)
            ok = false;
    }

    Component.onCompleted: {
        // Background mode: an unknown value (hand-edited kwinrc) must still
        // paint a hull instead of leaving the scene transparent.
        check("mode(Color)", Constants.backgroundMode(Constants.Background.Color), Constants.Background.Color);
        check("mode(Image)", Constants.backgroundMode(Constants.Background.Image), Constants.Background.Image);
        check("mode(Gradient)", Constants.backgroundMode(Constants.Background.Gradient), Constants.Background.Gradient);
        check("mode(unknown int)", Constants.backgroundMode(3), Constants.Background.Color);
        check("mode(-1)", Constants.backgroundMode(-1), Constants.Background.Color);
        check("mode(undefined)", Constants.backgroundMode(undefined), Constants.Background.Color);
        check("mode(null)", Constants.backgroundMode(null), Constants.Background.Color);
        check("mode(string)", Constants.backgroundMode("2"), Constants.Background.Color);

        // Image mapping: only an explicit Equirect wins without an image, and
        // Flat always wins over Auto.
        check("equirect(Equirect, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Equirect, false), true);
        check("equirect(Equirect, image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Equirect, true), true);
        check("equirect(Flat, image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Flat, true), false);
        check("equirect(Flat, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Flat, false), false);
        check("equirect(Auto, image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Auto, true), true);
        check("equirect(Auto, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageMapping.Auto, false), false);
        check("equirect(undefined, image)", Constants.usesEquirectMapping(undefined, true), true);
        check("equirect(undefined, no image)", Constants.usesEquirectMapping(undefined, false), false);

        // Url entry: url value or string, empty/undefined/null -> no image,
        // remote schemes rejected (the compositor must not fetch the network).
        check("source(file url)", Constants.backgroundImageSource(h.fileUrl), "file:///home/user/My Wall.jpg");
        check("source(empty url)", Constants.backgroundImageSource(h.emptyUrl), "");
        check("source(bare url value)", Constants.backgroundImageSource(h.bareUrl), "/home/user/wall.jpg");
        check("source(absolute path)", Constants.backgroundImageSource("/home/user/My Wall.jpg"), "/home/user/My Wall.jpg");
        check("source(file url string)", Constants.backgroundImageSource("file:///home/user/w.jpg"), "file:///home/user/w.jpg");
        check("source(image provider)", Constants.backgroundImageSource("image://wallpaper/0"), "image://wallpaper/0");
        check("source(empty string)", Constants.backgroundImageSource(""), "");
        check("source(undefined)", Constants.backgroundImageSource(undefined), "");
        check("source(null)", Constants.backgroundImageSource(null), "");
        check("source(http)", Constants.backgroundImageSource("http://example.com/sky.jpg"), "");
        check("source(smb)", Constants.backgroundImageSource("smb://host/sky.jpg"), "");
    }
}
