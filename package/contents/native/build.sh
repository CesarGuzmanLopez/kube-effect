#!/usr/bin/env bash
# kube-effect — build and install the optional Kube Effect Plus KCM (ADR-012/ADR-018).
#
#   ./native/build.sh                  # configure + build + install into ~/.local, no root
#   KUBE_PREFIX=/opt/kube ./native/build.sh
#   ./native/build.sh --prefix /usr/local
#   ./native/build.sh --system         # install into /usr (one sudo for the install step)
#   ./native/build.sh --clean          # wipe the build directory first
#   KUBE_SKIP_TESTS=1 ./native/build.sh  # skip ctest (smoke test + restart helpers)
#
# It also runs from the copy shipped in the package
# (~/.local/share/kwin/effects/kube-effect/contents/native/), with no Makefile
# around: every path is derived from this script's own location.
#
# The private prefix (~/.local) is the default because the KCM is optional: it
# must never require root. A privately installed KCM is only visible through
# prefix.sh ($XDG_DATA_HOME/kube-effect/prefix.sh): ECM generates it at
# configure time and this script installs a copy next to the stamp.
#
# The cube itself is QML-only; this script is never called by the effect.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Where the commands block should point. From the repo, native/ sits next to the
# project Makefile and package/; from the copy shipped in the package
# (contents/native) there is neither, so the source is this folder itself.
PARENT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
if [ -f "$PARENT_DIR/Makefile" ] && [ -f "$PARENT_DIR/package/metadata.json" ]; then
    SOURCE_DIR="$PARENT_DIR"
else
    SOURCE_DIR="$SCRIPT_DIR"
fi
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kube-effect"
STAMP="$DATA_DIR/native-stamp.json"
PREFIX_SH="$DATA_DIR/prefix.sh"

prefix="${KUBE_PREFIX:-$HOME/.local}"
clean=0
system=0

usage() {
    sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
    --clean) clean=1 ;;
    --system) system=1 ;;
    --prefix)
        shift
        prefix="${1:?--prefix needs a directory}"
        ;;
    --prefix=*) prefix="${1#--prefix=}" ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "build.sh: unknown argument: $1" >&2
        exit 2
        ;;
    esac
    shift
done

# --system keeps an explicit KUBE_PREFIX if the caller set one.
if [ "$system" = 1 ] && [ -z "${KUBE_PREFIX:-}" ]; then
    prefix="/usr"
fi

# Separate build trees: a system install must not reuse a private-prefix cache
# (the install paths are baked into the config).
if [ "$prefix" = "/usr" ]; then
    build_dir="$SCRIPT_DIR/build-system"
else
    build_dir="$SCRIPT_DIR/build"
fi

if [ "$clean" = 1 ]; then
    rm -rf "$build_dir"
fi

echo "kube-effect native: prefix=$prefix build=$build_dir"
cmake -S "$SCRIPT_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build "$build_dir" --parallel

# The KCM is what installs into ~/.local: run its tests (smoke test + the pure
# restart helpers) before installing, so a broken module never lands there.
# KUBE_SKIP_TESTS=1 opts out for environments without kcmshell6.
if [ "${KUBE_SKIP_TESTS:-0}" != 1 ]; then
    ctest --test-dir "$build_dir" --output-on-failure
fi

if [ "$system" = 1 ]; then
    sudo cmake --install "$build_dir"
else
    cmake --install "$build_dir"
fi

# The compiled versions come from CMake at configure time, so the stamp cannot
# disagree with what the .so was actually built against.
info="$build_dir/kube-native-info.json"
if [ ! -f "$info" ]; then
    echo "build.sh: missing $info (configure failed?)" >&2
    exit 1
fi

json_field() {
    python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$info" "$1"
}

plasma=$(json_field plasma)
qt=$(json_field qt)
pkg=$(json_field pkg)
plugindir=$(json_field plugindir)
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$DATA_DIR"
python3 - "$STAMP" "$plasma" "$qt" "$pkg" "$built" "$prefix" "$SOURCE_DIR" <<'PY'
import json
import sys

path, plasma, qt, pkg, built, prefix, source = sys.argv[1:8]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "plasma": plasma,
            "qt": qt,
            "pkg": pkg,
            "built": built,
            "prefix": prefix,
            "source": source,
        },
        handle,
        indent=4,
    )
    handle.write("\n")
PY

# ECM generates prefix.sh at configure time with the exact install paths of this
# prefix (QT_PLUGIN_PATH, XDG_DATA_DIRS, ...). Keep a copy next to the stamp so
# the nested harness and the user can source a stable path.
if [ ! -f "$build_dir/prefix.sh" ]; then
    echo "build.sh: missing $build_dir/prefix.sh (ECM did not generate it?)" >&2
    exit 1
fi
install -m 0644 "$build_dir/prefix.sh" "$PREFIX_SH"
# ECM writes unguarded $VAR expansions; sourcing the copy with 'set -u' aborts.
# Guard them so the harness (set -u) and user shells can source it safely.
sed -i \
    -e 's/\$QT_PLUGIN_PATH/\${QT_PLUGIN_PATH:-}/g' \
    -e 's/\$QML2_IMPORT_PATH/\${QML2_IMPORT_PATH:-}/g' \
    -e 's/\$QT_QUICK_CONTROLS_STYLE_PATH/\${QT_QUICK_CONTROLS_STYLE_PATH:-}/g' \
    -e 's/\$PYTHONPATH/\${PYTHONPATH:-}/g' \
    "$PREFIX_SH"

echo
echo "kube-effect native: installed (Plasma $plasma, Qt $qt, package $pkg)"
echo "  stamp:     $STAMP"
echo "  prefix.sh: $PREFIX_SH"
echo "  plugin:    $plugindir/plasma/kcms/systemsettings/kcm_kube_effect_plus.so"
echo
echo "Open it with:"
echo "  source '$PREFIX_SH' && systemsettings"
echo "  source '$PREFIX_SH' && kcmshell6 kcm_kube_effect_plus"
