import QtQuick
import "../package/contents/ui/constants.js" as Constants

// Runs inside scripts/check-constants.py. The holder `h` exposes QColor and
// QUrl properties, i.e. exactly what KConfigLoader hands QML for a Color or a
// Url entry: the conversions below are the ones the effect sees in KWin.
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
        // Color entries: KConfig hands QML a QColor.
        check("color(opaque)", Constants.color(h.opaque, "#000000"), "#212427");
        check("color(alpha 255)", Constants.color(h.opaqueAlpha, "#000000"), "#212427");
        check("color(translucent)", Constants.color(h.translucent, "#000000"), "#806ee7ff");
        check("color(string)", Constants.color("#1a1d21", "#000000"), "#1a1d21");
        check("color(short hex)", Constants.color("#abc", "#000000"), "#abc");
        check("color(garbage string)", Constants.color("#zzz", "#123456"), "#123456");
        check("color(empty)", Constants.color("", "#123456"), "#123456");
        check("color(undefined)", Constants.color(undefined, "#123456"), "#123456");

        // Url entries: KConfig hands QML a url value, not a string.
        check("imageUrl(file url)", Constants.imageUrl(h.fileUrl, "fallback"), "file:///home/user/My Wall.jpg");
        check("imageUrl(empty url)", Constants.imageUrl(h.emptyUrl, "fallback"), "fallback");
        check("imageUrl(bare path)", Constants.imageUrl("/home/user/wall.jpg", "fallback"), "file:///home/user/wall.jpg");
        check("imageUrl(file url string)", Constants.imageUrl("file:///home/user/w.jpg", "fallback"), "file:///home/user/w.jpg");
        check("imageUrl(empty string)", Constants.imageUrl("", "fallback"), "fallback");
        check("imageUrl(undefined)", Constants.imageUrl(undefined, "fallback"), "fallback");
        check("imageUrl(bare url value)", Constants.imageUrl(h.bareUrl, "fallback"), "file:///home/user/wall.jpg");
    }
}
