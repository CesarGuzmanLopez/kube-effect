#!/usr/bin/env bash
# Dependency check for KKube.
#
# Required entries are shipped with Plasma 6; if one is missing the effect
# cannot load. Optional entries only enable extra features (user glTF models,
# 360 video background). The feature catalog at the end (features.json) is
# informational too: a missing module disables a feature, it never aborts.
# Re-run this whenever you want to re-check: `make deps` or scripts/check-deps.sh.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

fail=0
optional_missing=()

# check <label> <path> <required|optional> [arch-package] [debian-package]
check() {
    local label=$1 path=$2 kind=$3 arch=${4:-} deb=${5:-}
    if [ -e "$path" ]; then
        printf '  [ok]      %-34s %s\n' "$label" "$path"
        return 0
    fi
    if [ "$kind" = "required" ]; then
        printf '  [MISSING] %-34s %s\n' "$label" "$path"
        [ -n "$arch" ] && printf '            install: pacman -S %s   |   apt install %s\n' "$arch" "$deb"
        fail=1
    else
        printf '  [absent]  %-34s %s\n' "$label" "$path"
        optional_missing+=("$label|$arch|$deb")
    fi
    return 1
}

QML=/usr/lib/qt6/qml
echo "KKube dependency check"
echo
echo "Required (shipped with Plasma 6; no extra installs needed):"
check "QtQuick3D" "$QML/QtQuick3D/qmldir" required qt6-quick3d qml6-module-qtquick3d
# HullGradient.qml imports QtQuick.Shapes unconditionally (radial hull gradient,
# ADR-013), so the whole effect needs it even when the background is a colour.
check "QtQuick.Shapes" "$QML/QtQuick/Shapes/qmldir" required qt6-declarative qml6-module-qtquick-shapes
check "org.kde.kwin" "$QML/org/kde/kwin" required kwin kwin-wayland
check "org.kde.kirigami" "$QML/org/kde/kirigami/qmldir" required kirigami qml6-module-org-kde-kirigami
check "plasma.components" "$QML/org/kde/plasma/components/qmldir" required libplasma qml6-module-org-kde-plasma-components
check "plasma.extras" "$QML/org/kde/plasma/extras/qmldir" required libplasma qml6-module-org-kde-plasma-extras
check "QtQuick.Controls" "$QML/QtQuick/Controls/qmldir" required qt6-declarative qml6-module-qtquick-controls

KCM=$(find /usr/lib /usr/lib64 -path '*kwin/effects/configs/kcm_kwin4_genericscripted.so' 2>/dev/null | head -1)
if [ -n "$KCM" ]; then
    printf '  [ok]      %-34s %s\n' "generic KCM" "$KCM"
else
    printf '  [MISSING] %-34s %s\n' "generic KCM" "kcm_kwin4_genericscripted"
    printf '            the settings panel needs it (package kwin / kwin-common)\n'
    fail=1
fi

echo
echo "Settings panel widgets (config.ui is built with QUiLoader):"
for plugin in kio6widgets kwidgetsaddons6widgets; do
    PLUGIN=$(find /usr/lib /usr/lib64 -path "*designer/${plugin}.so" 2>/dev/null | head -1)
    if [ -n "$PLUGIN" ]; then
        printf '  [ok]      %-34s %s\n' "$plugin designer plugin" "$PLUGIN"
    else
        printf '  [MISSING] %-34s %s\n' "$plugin designer plugin" "designer/${plugin}.so"
        printf '            without it the KCM file/colour pickers degrade to empty widgets\n'
        printf '            install the KF6 KIO / KWidgetsAddons designer plugins of your distro\n'
        fail=1
    fi
done

echo
echo "Optional (extra features only):"
check "RuntimeLoader (glTF runtime)" "$QML/QtQuick3D/AssetUtils/qmldir" optional qt6-quick3d qml6-module-qtquick3d-assetutils
check "assimp importer plugin" "/usr/lib/qt6/plugins/assetimporters/libassimp.so" optional assimp libassimp6
if ldconfig -p 2>/dev/null | grep -q 'libassimp\.so\.6'; then
    printf '  [ok]      %-34s %s\n' "libassimp.so.6" "ldconfig"
else
    printf '  [absent]  %-34s %s\n' "libassimp.so.6" "ldconfig"
    optional_missing+=("libassimp.so.6|assimp|libassimp6")
fi
# 360 video background: the QML module and the shared library must both be
# there. Without them the effect keeps working (transparent background plus an
# on-screen banner), it only loses the Video background.
check "QtMultimedia (360 video)" "$QML/QtMultimedia/qmldir" optional qt6-multimedia libqt6multimedia6
if ldconfig -p 2>/dev/null | grep -q 'libQt6Multimedia\.so\.6'; then
    printf '  [ok]      %-34s %s\n' "libQt6Multimedia.so.6" "ldconfig"
else
    printf '  [absent]  %-34s %s\n' "libQt6Multimedia.so.6" "ldconfig"
    optional_missing+=("libQt6Multimedia.so.6|qt6-multimedia|libqt6multimedia6")
fi
BALSAM=$(command -v balsam || true)
[ -z "$BALSAM" ] && [ -x /usr/lib/qt6/bin/balsam ] && BALSAM=/usr/lib/qt6/bin/balsam
if [ -n "$BALSAM" ]; then
    printf '  [ok]      %-34s %s\n' "balsam (glTF -> .mesh)" "$BALSAM"
else
    printf '  [absent]  %-34s %s\n' "balsam (glTF -> .mesh)" "qt6-quick3d"
    optional_missing+=("balsam|qt6-quick3d|qt6-quick3d-dev-tools")
fi

echo
echo "Development tools (optional, only for the quality gate):"
for tool in shfmt xmllint jq yamllint reuse codespell typos; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  [ok]      %-34s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '  [absent]  %-34s %s\n' "$tool" "not installed (optional)"
    fi
done

echo
echo "Feature catalog (package/contents/config/features.json):"
if ! python3 "$SCRIPT_DIR/check-features.py" --deps; then
    echo
    echo "RESULT: features.json is invalid — fix the catalog (make check fails too)."
    exit 1
fi

echo
if [ ${#optional_missing[@]} -gt 0 ]; then
    echo "Optional features disabled:"
    for entry in "${optional_missing[@]}"; do
        IFS='|' read -r label arch deb <<<"$entry"
        printf '  - %-26s pacman -S %s   |   apt install %s\n' "$label" "$arch" "$deb"
    done
    echo "  glTF/GLB/OBJ models and the 360 video background need these; everything else works without them."
    echo
fi

if [ "$fail" -ne 0 ]; then
    echo "RESULT: required dependency missing — the effect will not load."
    exit 1
fi
echo "RESULT: required dependencies OK."
[ ${#optional_missing[@]} -gt 0 ] && echo "        optional extras: ${#optional_missing[@]} missing (see above)."
exit 0
