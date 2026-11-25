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

    // Projected spans are trigonometric, so 180/360 only match 0 within float
    // noise (sin(pi) is not exactly 0); the identity checks stay exact.
    function checkClose(name, actual, expected, epsilon) {
        const tolerance = epsilon === undefined ? 1e-9 : epsilon;
        const passed = Math.abs(actual - expected) <= tolerance;
        const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected ~" + expected + ")");
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
        check("mode(Video)", Constants.backgroundMode(Constants.Background.Video), Constants.Background.Video);
        check("mode(unknown int)", Constants.backgroundMode(4), Constants.Background.Color);
        check("mode(-1)", Constants.backgroundMode(-1), Constants.Background.Color);
        check("mode(undefined)", Constants.backgroundMode(undefined), Constants.Background.Color);
        check("mode(null)", Constants.backgroundMode(null), Constants.Background.Color);
        check("mode(string)", Constants.backgroundMode("2"), Constants.Background.Color);

        // Image layout: Equirect is the default, only an explicit Flat turns it
        // off. Unknown values (hand-edited BackgroundImageLayout) must resolve
        // to equirect instead of silently flattening a panorama; values under
        // the old BackgroundImageMapping key never arrive (orphaned in kwinrc).
        check("equirect(Equirect, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Equirect, false), true);
        check("equirect(Equirect, image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Equirect, true), true);
        check("equirect(Flat, image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Flat, true), false);
        check("equirect(Flat, no image)", Constants.usesEquirectMapping(Constants.BackgroundImageLayout.Flat, false), false);
        check("equirect(unknown 2, image)", Constants.usesEquirectMapping(2, true), true);
        check("equirect(unknown 2, no image)", Constants.usesEquirectMapping(2, false), true);
        check("equirect(unknown 7, image)", Constants.usesEquirectMapping(7, true), true);
        check("equirect(undefined, image)", Constants.usesEquirectMapping(undefined, true), true);
        check("equirect(undefined, no image)", Constants.usesEquirectMapping(undefined, false), true);
        check("equirect(null, image)", Constants.usesEquirectMapping(null, true), true);
        check("equirect(string, image)", Constants.usesEquirectMapping("1", true), true);

        // Flat-image fit: only Contain/Stretch are accepted; anything else
        // (legacy or hand-edited) is Cover, the schema default.
        check("fit(Cover)", Constants.imageFit(Constants.BackgroundImageFit.Cover), Constants.BackgroundImageFit.Cover);
        check("fit(Contain)", Constants.imageFit(Constants.BackgroundImageFit.Contain), Constants.BackgroundImageFit.Contain);
        check("fit(Stretch)", Constants.imageFit(Constants.BackgroundImageFit.Stretch), Constants.BackgroundImageFit.Stretch);
        check("fit(unknown 3)", Constants.imageFit(3), Constants.BackgroundImageFit.Cover);
        check("fit(negative)", Constants.imageFit(-1), Constants.BackgroundImageFit.Cover);
        check("fit(undefined)", Constants.imageFit(undefined), Constants.BackgroundImageFit.Cover);
        check("fit(null)", Constants.imageFit(null), Constants.BackgroundImageFit.Cover);
        check("fit(string)", Constants.imageFit("contain"), Constants.BackgroundImageFit.Cover);

        // Rotating veil: off is always 0, amount is a percentage clamped to
        // 0..1, and an unusable amount uses the schema default (40 %).
        check("dim(off, 40)", Constants.dimOpacity(false, 40), 0);
        check("dim(off, 100)", Constants.dimOpacity(false, 100), 0);
        check("dim(on, 40)", Constants.dimOpacity(true, 40), 0.4);
        check("dim(on, 0)", Constants.dimOpacity(true, 0), 0);
        check("dim(on, 100)", Constants.dimOpacity(true, 100), 1);
        check("dim(on, 150)", Constants.dimOpacity(true, 150), 1);
        check("dim(on, -20)", Constants.dimOpacity(true, -20), 0);
        check("dim(on, undefined)", Constants.dimOpacity(true, undefined), 0.4);
        check("dim(undefined, 40)", Constants.dimOpacity(undefined, 40), 0);

        // SkyBox exposure: 1.0 when not dimming or not rotating, otherwise the
        // veil opacity is subtracted (same amount as the 2D hull), clamped at 0
        // so a hand-edited amount above 100 cannot turn the value negative.
        check("exposure(off, still)", Constants.skyBoxExposure(false, false, 40), 1);
        check("exposure(off, rotating)", Constants.skyBoxExposure(false, true, 40), 1);
        check("exposure(on, still)", Constants.skyBoxExposure(true, false, 40), 1);
        check("exposure(on, rotating, 40)", Constants.skyBoxExposure(true, true, 40), 0.6);
        check("exposure(on, rotating, 0)", Constants.skyBoxExposure(true, true, 0), 1);
        check("exposure(on, rotating, 100)", Constants.skyBoxExposure(true, true, 100), 0);
        check("exposure(on, rotating, 150)", Constants.skyBoxExposure(true, true, 150), 0);
        check("exposure(on, rotating, -20)", Constants.skyBoxExposure(true, true, -20), 1);
        check("exposure(on, rotating, undefined)", Constants.skyBoxExposure(true, true, undefined), 0.6);
        check("exposure(undefined, rotating)", Constants.skyBoxExposure(undefined, true, 40), 1);
        check("exposure(on, undefined)", Constants.skyBoxExposure(true, undefined, 40), 1);

        // Gradient stop: percentage clamped to 0..1, non-finite -> schema
        // default (50 %). KConfigXT hands a typed Int, so null only comes from
        // a hand-edited value and is clamped like any other number (0).
        check("stop(0)", Constants.gradientStopPosition(0), 0);
        check("stop(50)", Constants.gradientStopPosition(50), 0.5);
        check("stop(100)", Constants.gradientStopPosition(100), 1);
        check("stop(150)", Constants.gradientStopPosition(150), 1);
        check("stop(-20)", Constants.gradientStopPosition(-20), 0);
        check("stop(string)", Constants.gradientStopPosition("abc"), 0.5);
        check("stop(undefined)", Constants.gradientStopPosition(undefined), 0.5);
        check("stop(null)", Constants.gradientStopPosition(null), 0);

        // Gradient rotation: only the gradient hull (ADR-017). Fixed is always
        // 0, FollowCube copies the yaw, FollowCubeInverse mirrors it, and an
        // unknown mode (hand-edited kwinrc) leaves the layer still.
        check("rotation(Fixed, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.Fixed, 90), 0);
        check("rotation(Fixed, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.Fixed, 0), 0);
        check("rotation(FollowCube, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, 90), 90);
        check("rotation(FollowCube, -45)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, -45), -45);
        check("rotation(FollowCube, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, 0), 0);
        check("rotation(Inverse, 90)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, 90), -90);
        check("rotation(Inverse, -45)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, -45), 45);
        check("rotation(Inverse, 0)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCubeInverse, 0), 0);
        check("rotation(unknown 9, 90)", Constants.gradientRotationAngle(9, 90), 0);
        check("rotation(undefined, 90)", Constants.gradientRotationAngle(undefined, 90), 0);
        check("rotation(FollowCube, undefined)", Constants.gradientRotationAngle(Constants.BackgroundGradientRotation.FollowCube, undefined), 0);

        // Gradient geometry (ADR-017): the projection and the stop remap live
        // in constants.js, so HullGradient.qml keeps no copy of them. 180/360
        // equal 0 up to float noise; a zero width or height has no band.
        check("span(v, 0)", Constants.gradientVisibleSpan(800, 600, 0, false), 600);
        check("span(h, 0)", Constants.gradientVisibleSpan(800, 600, 0, true), 800);
        checkClose("span(v, 90)", Constants.gradientVisibleSpan(800, 600, 90, false), 800);
        checkClose("span(h, 90)", Constants.gradientVisibleSpan(800, 600, 90, true), 600);
        checkClose("span(v, 45)", Constants.gradientVisibleSpan(800, 600, 45, false), 1400 * Math.SQRT1_2);
        checkClose("span(v, 180) = 0deg", Constants.gradientVisibleSpan(800, 600, 180, false), 600);
        checkClose("span(v, 360) = 0deg", Constants.gradientVisibleSpan(800, 600, 360, false), 600);

        checkClose("margin(v, 0)", Constants.gradientStopMargin(800, 600, 0, false), 0.2);
        check("margin(v, 0) identity", Constants.gradientStopMargin(800, 600, 0, false), 0.5 - 0.5 * 600 / Math.hypot(800, 600));
        checkClose("margin(v, 90)", Constants.gradientStopMargin(800, 600, 90, false), 0.1);
        checkClose("margin(v, 180) = 0deg", Constants.gradientStopMargin(800, 600, 180, false), 0.2);
        checkClose("margin(v, 360) = 0deg", Constants.gradientStopMargin(800, 600, 360, false), 0.2);
        checkClose("margin(w = h)", Constants.gradientStopMargin(800, 800, 0, false), 0.5 - 0.5 * Math.SQRT1_2);
        check("margin(w = 0)", Constants.gradientStopMargin(0, 600, 45, false), 0);
        check("margin(h = 0)", Constants.gradientStopMargin(800, 0, 45, false), 0);
        check("margin(w = h = 0)", Constants.gradientStopMargin(0, 0, 45, true), 0);

        // Only the two follow modes move the radial focal point; Fixed and an
        // unknown kwinrc value keep it centred (no off-centre radial).
        check("follows(Fixed)", Constants.gradientFollows(Constants.BackgroundGradientRotation.Fixed), false);
        check("follows(FollowCube)", Constants.gradientFollows(Constants.BackgroundGradientRotation.FollowCube), true);
        check("follows(Inverse)", Constants.gradientFollows(Constants.BackgroundGradientRotation.FollowCubeInverse), true);
        check("follows(unknown 7)", Constants.gradientFollows(7), false);
        check("follows(undefined)", Constants.gradientFollows(undefined), false);

        // Face opacity (ADR-021): rest vs rotation value, clamped to
        // [0.1, 1] (a fully invisible face cannot be picked), non-finite
        // falls back to the schema default of the active branch.
        check("face(rest 1, still)", Constants.faceOpacity(1, 0.7, false), 1);
        check("face(rot 0.7, rotating)", Constants.faceOpacity(1, 0.7, true), 0.7);
        check("face(rest 0.5, still)", Constants.faceOpacity(0.5, 0.7, false), 0.5);
        check("face(rot 1, rotating)", Constants.faceOpacity(0.5, 1, true), 1);
        check("face(rest 0, clamp)", Constants.faceOpacity(0, 0.7, false), 0.1);
        check("face(rot -1, clamp)", Constants.faceOpacity(1, -1, true), 0.1);
        check("face(rest 2, clamp)", Constants.faceOpacity(2, 0.7, false), 1);
        check("face(rest NaN -> 1)", Constants.faceOpacity(undefined, 0.7, false), 1);
        check("face(rot NaN -> 0.7)", Constants.faceOpacity(1, undefined, true), 0.7);
        // Number(null) is 0, not NaN: null clamps to the floor like 0 does.
        check("face(rest null -> floor)", Constants.faceOpacity(null, 0.7, false), 0.1);
        check("face(rot null -> floor)", Constants.faceOpacity(1, null, true), 0.1);
        check("face(rest numeric string)", Constants.faceOpacity("0.5", 0.7, false), 0.5);
        check("face(rest bad string -> 1)", Constants.faceOpacity("abc", 0.7, false), 1);
        check("face(rot undefined rotating)", Constants.faceOpacity(1, 0.7, undefined), 1);

        // Face fade duration: 0..1000 ms, 0 is a hard cut, non-finite -> 120.
        check("fade(120)", Constants.faceFadeDuration(120), 120);
        check("fade(0)", Constants.faceFadeDuration(0), 0);
        check("fade(1000)", Constants.faceFadeDuration(1000), 1000);
        check("fade(-5)", Constants.faceFadeDuration(-5), 0);
        check("fade(5000)", Constants.faceFadeDuration(5000), 1000);
        check("fade(undefined)", Constants.faceFadeDuration(undefined), 120);
        check("fade(null)", Constants.faceFadeDuration(null), 0);
        check("fade(string)", Constants.faceFadeDuration("abc"), 120);

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

        // Video source: same local-only rule as the image, but a clip must be a
        // real file. image: is rejected (there is no video provider behind it)
        // and so is every remote scheme.
        check("video(file url)", Constants.videoSource(h.fileUrl), "file:///home/user/My Wall.jpg");
        check("video(bare url value)", Constants.videoSource(h.bareUrl), "/home/user/wall.jpg");
        check("video(file url string)", Constants.videoSource("file:///home/user/clip.mp4"), "file:///home/user/clip.mp4");
        check("video(absolute path)", Constants.videoSource("/home/user/clip.mp4"), "/home/user/clip.mp4");
        check("video(empty url)", Constants.videoSource(h.emptyUrl), "");
        check("video(empty string)", Constants.videoSource(""), "");
        check("video(undefined)", Constants.videoSource(undefined), "");
        check("video(null)", Constants.videoSource(null), "");
        check("video(image provider)", Constants.videoSource("image://wallpaper/0"), "");
        check("video(http)", Constants.videoSource("http://example.com/clip.mp4"), "");
        check("video(smb)", Constants.videoSource("smb://host/clip.mp4"), "");
    }
}
