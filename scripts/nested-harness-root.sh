#!/usr/bin/env bash
# kube-effect — private harness root for scripts/kwin-nested-test.sh.
# Source this file; do NOT execute it. It only defines two functions.
#
# WHY THIS EXISTS: the harness used to hardcode /tmp/kube-effect-test-config
# plus fixed log/pid/addr files in /tmp. /tmp is world-shared: another local
# user could pre-create those paths (our writes then fail or land in their
# tree) or leave a symlink (mkdir/write/rm -rf follow it: config hijack of
# the nested session and an rm -rf punching through the link). The root now
# embeds the uid, is created with mode 700, and is refused outright when the
# path is a symlink or a foreign/not-a-directory entry.
#
# WHAT IS PRESERVED: the old path was reused across runs ON PURPOSE (the
# data dir keeps the installed effect package so kpackagetool6 --upgrade is
# incremental, and --no-follow leaves a live nested compositor reading $CFG
# and its logs). So this is a deterministic uid-suffixed name, not a fresh
# mktemp -d every run: log/config reuse behaves exactly as before.

# Sets HARNESS_ROOT to a private 0700 directory under ${TMPDIR:-/tmp}. On
# failure prints the reason to stderr, empties HARNESS_ROOT and returns 1.
nested_harness_root_prepare() {
  local tmpbase="${TMPDIR:-/tmp}"
  tmpbase="${tmpbase%/}"
  [ -n "$tmpbase" ] || tmpbase="/tmp"
  HARNESS_ROOT="$tmpbase/kube-effect-nested-$(id -u)"

  if [ -L "$HARNESS_ROOT" ]; then
    printf 'error: %s es un symlink; otro usuario podria secuestrar la config del anidado\n' \
      "$HARNESS_ROOT" >&2
    HARNESS_ROOT=""
    return 1
  fi
  if [ -e "$HARNESS_ROOT" ] && { [ ! -d "$HARNESS_ROOT" ] || [ ! -O "$HARNESS_ROOT" ]; }; then
    printf 'error: %s existe y no es un directorio del uid %s\n' \
      "$HARNESS_ROOT" "$(id -u)" >&2
    HARNESS_ROOT=""
    return 1
  fi
  # -m 700 covers the leaf from the very first instant (no 0755 window
  # where someone else could plant a symlink inside); with -p, intermediate
  # dirs of an unusual TMPDIR keep the umask, which is fine because only
  # the leaf holds our state. The chmod below normalises a pre-existing dir
  # of ours that had laxer bits. Safe: the checks above prove it is our own
  # real directory, never a link.
  # shellcheck disable=SC2174
  if ! mkdir -m 700 -p "$HARNESS_ROOT" 2>/dev/null; then
    printf 'error: no pude crear %s\n' "$HARNESS_ROOT" >&2
    HARNESS_ROOT=""
    return 1
  fi
  chmod 700 "$HARNESS_ROOT"
  # Re-verify after creation before anything is written inside.
  if [ -L "$HARNESS_ROOT" ] || [ ! -d "$HARNESS_ROOT" ] || [ ! -O "$HARNESS_ROOT" ]; then
    printf 'error: %s no quedo como directorio propio; aborto\n' "$HARNESS_ROOT" >&2
    HARNESS_ROOT=""
    return 1
  fi
  return 0
}

# rm -rf anchored to the harness root: every argument must be $HARNESS_ROOT
# itself or live under it, and the root must still be a real directory owned
# by us. Empty or foreign arguments are refused, so a cleared/unset variable
# can never reach rm -rf.
nested_harness_rm_rf() {
  local target
  [ -n "${HARNESS_ROOT:-}" ] || return 1
  if [ -L "$HARNESS_ROOT" ] || [ ! -d "$HARNESS_ROOT" ] || [ ! -O "$HARNESS_ROOT" ]; then
    return 1
  fi
  # Anchor on the RESOLVED root, and compare resolved targets. A textual
  # prefix test is not enough: "$HARNESS_ROOT/../elsewhere" starts with
  # "$HARNESS_ROOT/" and would rm OUTSIDE the tree (reproduced: a sibling
  # directory was removed with rc=0). Resolving is also what keeps a
  # legitimate TMPDIR that contains ".." working - a literal ".." guard
  # would refuse "$HARNESS_ROOT/config" whenever the root path itself
  # carried one. readlink -f resolves the existing part of a missing path
  # too, so "$CFG/kwinrc" before it is written still compares correctly.
  local root_real target_real
  root_real=$(readlink -f "$HARNESS_ROOT" 2>/dev/null)
  [ -n "$root_real" ] || return 1
  for target in "$@"; do
    target_real=$(readlink -f "$target" 2>/dev/null)
    case "$target_real" in
    "$root_real" | "$root_real"/*) ;;
    *)
      printf 'error: me niego a borrar %s (fuera de %s)\n' \
        "$target" "$root_real" >&2
      return 1
      ;;
    esac
  done
  rm -rf -- "$@"
}
