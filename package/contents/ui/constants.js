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
// Matches the BackgroundImageMapping enum in config/main.xml
const BackgroundImageMapping = {
    Auto: 0,
    Equirect: 1,
    Flat: 2
};
// Matches the BackgroundGradientType enum in config/main.xml
const BackgroundGradientType = {
    LinearVertical: 0,
    LinearHorizontal: 1,
    Radial: 2
};

// An unknown value (kwinrc edited by hand) falls back to a solid colour
// instead of leaving the hull unpainted.
function backgroundMode(value) {
    if (value === Background.Image || value === Background.Gradient) {
        return value;
    }
    return Background.Color;
}

// BackgroundImageMapping.Auto cannot know the image aspect ratio without
// decoding the picture, so Auto treats any configured image as a 2:1
// panorama; a flat picture must be marked Flat explicitly.
function usesEquirectMapping(mapping, hasImage) {
    if (mapping === BackgroundImageMapping.Equirect) {
        return true;
    }
    if (mapping === BackgroundImageMapping.Flat) {
        return false;
    }
    return hasImage;
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
