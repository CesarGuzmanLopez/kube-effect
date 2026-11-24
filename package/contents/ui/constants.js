/*
    SPDX-FileCopyrightText: 2023 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Matches the Background enum in config/main.xml
const Background = {
    Color: 0,
    // Index 1 used to be named SkyBox; kwinrc stores the index, not the name.
    Image: 1,
    Gradient: 2
};
// Matches the BackgroundImageLayout enum in config/main.xml. Auto was
// removed (ADR-013): the user states whether the picture is a panorama. The
// KEY (not just the choices) was renamed on purpose: kwinrc keeps the index,
// so an old BackgroundImageMapping=1 stays orphaned instead of being read back
// as Flat (it used to mean Equirect under the 0=Auto, 1=Equirect, 2=Flat
// scheme).
const BackgroundImageLayout = {
    Equirect: 0,
    Flat: 1
};
// Matches the BackgroundImageFit enum in config/main.xml
const BackgroundImageFit = {
    Cover: 0,
    Contain: 1,
    Stretch: 2
};
// Default BackgroundImageFit / DimWhileRotatingAmount / BackgroundGradientStop
// from config/main.xml, used when the stored value is not a usable number.
const DEFAULT_IMAGE_FIT = BackgroundImageFit.Cover;
const DEFAULT_DIM_AMOUNT = 40;
const DEFAULT_GRADIENT_STOP = 50;
// Matches the BackgroundGradientType enum in config/main.xml
const BackgroundGradientType = {
    LinearVertical: 0,
    LinearHorizontal: 1,
    Radial: 2
};
// Matches the BackgroundGradientRotation enum in config/main.xml. Only the
// gradient hull uses it (ADR-017): the layer may stay still or turn with the
// cube, forwards or backwards.
const BackgroundGradientRotation = {
    Fixed: 0,
    FollowCube: 1,
    FollowCubeInverse: 2
};

// An unknown value (kwinrc edited by hand) falls back to a solid colour
// instead of leaving the hull unpainted.
function backgroundMode(value) {
    if (value === Background.Image || value === Background.Gradient) {
        return value;
    }
    return Background.Color;
}

// Equirect is the default and the safe fallback: only an explicit Flat turns
// it off. A hand-edited kwinrc value or a missing entry resolves to equirect;
// stretching a real panorama as a flat photo is worse than wrapping a photo
// around the scene. Values left over from the old key never reach this helper
// (KConfig drops the orphaned key), so an old "1" cannot turn into Flat.
// hasImage no longer influences the decision (the SkyBox still requires an
// image, see skyBoxBackground); it stays in the signature for callers/tests.
function usesEquirectMapping(mapping, hasImage) {
    return mapping !== BackgroundImageLayout.Flat;
}

// Flat-image fit: unknown values fall back to Cover, the schema default.
function imageFit(value) {
    if (value === BackgroundImageFit.Contain || value === BackgroundImageFit.Stretch) {
        return value;
    }
    return DEFAULT_IMAGE_FIT;
}

// Opacity of the black veil drawn over the hull while the cube rotates:
// 0 when DimWhileRotating is off, otherwise amount/100 clamped to 0..1. A
// missing or non-numeric amount uses the schema default (40 %).
function dimOpacity(enabled, amount) {
    if (enabled !== true) {
        return 0;
    }
    var percent = Number(amount);
    if (!isFinite(percent)) {
        percent = DEFAULT_DIM_AMOUNT;
    }
    return Math.min(1, Math.max(0, percent / 100));
}

// Exposure of the SkyBox light probe while the cube rotates. 1.0 leaves the
// panorama untouched (DimWhileRotating off, or the cube still), otherwise the
// veil opacity is subtracted so a 360 background darkens as much as the 2D
// hull does. A SkyBox is painted by the 3D environment, so the black Rectangle
// that dims color/gradient/flat image cannot reach it; probeExposure (the
// brightness of the environment) can. The result stays in 0..1.
function skyBoxExposure(enabled, rotating, amount) {
    if (enabled !== true || rotating !== true) {
        return 1;
    }
    return Math.max(0, 1 - dimOpacity(enabled, amount));
}

// Position of the second gradient stop in 0..1 (BackgroundGradientStop is a
// 0..100 Int). KConfigXT clamps the entry, but a hand-edited kwinrc can still
// carry anything, and a non-numeric value would poison the stop with NaN, so a
// non-finite value uses the schema default (50 %) and the rest is clamped.
function gradientStopPosition(value) {
    var percent = Number(value);
    if (!isFinite(percent)) {
        percent = DEFAULT_GRADIENT_STOP;
    }
    return Math.min(1, Math.max(0, percent / 100));
}

// Angle in degrees applied to the gradient layer (ADR-017). Fixed (and any
// value a hand-edited kwinrc may carry) resolves to 0 so the default look is
// never distorted; FollowCube copies the cube/camera yaw and FollowCubeInverse
// mirrors it. A non-finite yaw also falls back to 0 instead of poisoning the
// transform with NaN.
function gradientRotationAngle(mode, yawDegrees) {
    if (mode !== BackgroundGradientRotation.FollowCube && mode !== BackgroundGradientRotation.FollowCubeInverse) {
        return 0;
    }
    const yaw = Number(yawDegrees);
    if (!isFinite(yaw)) {
        return 0;
    }
    return mode === BackgroundGradientRotation.FollowCube ? yaw : -yaw;
}

// Visible span of a w x h area along the gradient axis once the layer is turned
// by angleDeg (ADR-017): the projection that shows how much of the oversized
// rectangle stays on screen. Horizontal gradients measure X (|w*cos| + |h*sin|),
// vertical ones measure Y (|w*sin| + |h*cos|). A non-finite input falls back to
// 0 instead of poisoning the stops with NaN.
function gradientVisibleSpan(w, h, angleDeg, horizontal) {
    var width = Number(w);
    var height = Number(h);
    var radians = Number(angleDeg) * Math.PI / 180;
    if (!isFinite(width) || !isFinite(height) || !isFinite(radians)) {
        return 0;
    }
    var cosine = Math.abs(Math.cos(radians));
    var sine = Math.abs(Math.sin(radians));
    return horizontal ? width * cosine + height * sine : width * sine + height * cosine;
}

// Half of the unpainted margin left on each side of the visible band (0..0.5).
// The layer is the screen diagonal, so the visible span covers only part of it;
// the stops are remapped into [margin, 1 - margin] to keep Fixed's look. A
// degenerate area (w or h = 0) has no gradient to remap.
function gradientStopMargin(w, h, angleDeg, horizontal) {
    var width = Number(w);
    var height = Number(h);
    var radians = Number(angleDeg) * Math.PI / 180;
    if (!isFinite(width) || !isFinite(height) || !isFinite(radians) || width <= 0 || height <= 0) {
        return 0;
    }
    var diagonal = Math.hypot(width, height);
    var span = gradientVisibleSpan(width, height, angleDeg, horizontal);
    return 0.5 - 0.5 * Math.min(1, span / diagonal);
}

// True when the gradient layer follows the cube (ADR-017). Fixed and any value
// a hand-edited kwinrc may carry keep the radial focal point at the centre.
function gradientFollows(mode) {
    return mode === BackgroundGradientRotation.FollowCube || mode === BackgroundGradientRotation.FollowCubeInverse;
}

// KConfig hands a Url entry as a url value (not a string), and the entry can
// be undefined/null before the KCM saves anything. Only local resources are
// accepted: the compositor must not fetch remote content when the effect
// activates, and QtQuick3D could not use a remote texture anyway.
function backgroundImageSource(value) {
    if (value === undefined || value === null) {
        return "";
    }
    const source = String(value);
    if (source.length === 0) {
        return "";
    }
    const scheme = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(source);
    if (scheme !== null && scheme[1] !== "file" && scheme[1] !== "image") {
        return "";
    }
    return source;
}
