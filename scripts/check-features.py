#!/usr/bin/env python3
"""Validate the feature catalog (package/contents/config/features.json).

features.json (ADR-016) is the single source of truth for "which feature needs
which module". It is consumed by scripts/check-deps.sh (make deps) and by the
optional native KCM; the QML never reads it. This script keeps the catalog
honest and tells whether this machine can run each entry's dependencies.

  python3 scripts/check-features.py          validate only (exit 1 on error)
  python3 scripts/check-features.py --deps   validate + probe the system
  python3 scripts/check-features.py --selftest   run the validator's own tests

An optional positional argument points at another catalog file (used by the
tests); it defaults to package/contents/config/features.json. Unknown options
and extra positionals are rejected with the usage text and exit 2.

Every since must be X.Y.Z[.W] and must not be newer than KPlugin.Version in
package/metadata.json: the catalog cannot promise a feature the package has not
released yet. A value later than the package version fails the gate.

The probe is informational: a missing optional module disables a feature, it
does not break the effect, so --deps always exits 0 when the JSON is valid.

The QML import root is discovered at run time (qtpaths6, then QML2_IMPORT_PATH,
then the usual distro prefixes), so the check is not tied to one packaging.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURES = ROOT / "package/contents/config/features.json"
METADATA = ROOT / "package/metadata.json"

REQUIRED_FIELDS = ("id", "label", "requires", "native", "notes", "status", "since")
VALID_STATUSES = {"stable", "planned", "needs-native"}
ID_PATTERN = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:\.\d+)?$")

# Requirement label -> path (relative to a QML import root) that must exist on a
# system able to run it. A label missing from this map is a catalog typo, not a
# new dependency.
REQUIREMENT_PROBES = {
    "QtQuick3D": "QtQuick3D/qmldir",
    "QtQuick3D.Helpers": "QtQuick3D/Helpers/qmldir",
    "QtQuick.Shapes": "QtQuick/Shapes/qmldir",
    "QtMultimedia": "QtMultimedia/qmldir",
    "org.kde.kwin": "org/kde/kwin",
    "Kirigami": "org/kde/kirigami/qmldir",
}

# Last resort when qtpaths is absent and no QML import path is exported. The
# first two are the real sources; these are the multiarch/prefix layouts of the
# common distros, so a non-Arch machine still gets a useful probe.
KNOWN_QML_ROOTS = (
    "/usr/lib/qt6/qml",
    "/usr/lib64/qt6/qml",
    "/usr/lib/x86_64-linux-gnu/qt6/qml",
    "/usr/lib/aarch64-linux-gnu/qt6/qml",
    "/usr/lib/qt/qml",
    "/usr/local/lib/qt6/qml",
    "/usr/local/lib64/qt6/qml",
)

USAGE = """usage: check-features.py [--deps] [--selftest] [CATALOG]

  (no option)    validate package/contents/config/features.json
  --deps         validate, then probe this system for every required module
  --selftest     run the validator's built-in tests (no arguments needed)
  CATALOG        validate another catalog file instead of the packaged one
"""


def display_path(path):
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def _qtpaths_qml_root():
    """QT_INSTALL_QML from qtpaths6/qtpaths, or None when neither answers."""
    for command in ("qtpaths6", "qtpaths"):
        try:
            completed = subprocess.run(
                [command, "--query", "QT_INSTALL_QML"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        path = completed.stdout.strip()
        if completed.returncode == 0 and path and Path(path).is_dir():
            return Path(path)
    return None


def qml_roots():
    """Qt QML import roots, best first, without duplicates.

    qtpaths knows where this Qt installs its modules (Arch, Fedora, Debian, a
    private KDE prefix, a Qt online installer): asking it beats guessing.
    QML2_IMPORT_PATH/QML_IMPORT_PATH come next (the engine honours them), and
    the known distro paths are only a fallback.
    """
    candidates = []
    qt_root = _qtpaths_qml_root()
    if qt_root is not None:
        candidates.append(qt_root)
    for variable in ("QML2_IMPORT_PATH", "QML_IMPORT_PATH"):
        for entry in os.environ.get(variable, "").split(os.pathsep):
            if entry:
                candidates.append(Path(entry))
    candidates.extend(Path(path) for path in KNOWN_QML_ROOTS)

    roots = []
    for candidate in candidates:
        if candidate not in roots:
            roots.append(candidate)
    return roots


def requirement_path(relative, roots):
    """First existing root/relative, else the first root (reported as absent)."""
    for root in roots:
        candidate = root / relative
        if candidate.exists():
            return candidate
    return roots[0] / relative


def parse_version(text):
    """X.Y.Z[.W] -> comparable (X, Y, Z, W) tuple, or None when invalid."""
    if not isinstance(text, str) or not VERSION_PATTERN.match(text):
        return None
    parts = [int(part) for part in text.split(".")]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)


def package_version(path=METADATA):
    """KPlugin.Version from metadata.json; raises ValueError when unusable."""
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {display_path(path)}: {error}") from error
    plugin = data.get("KPlugin") if isinstance(data, dict) else None
    version = plugin.get("Version") if isinstance(plugin, dict) else None
    if parse_version(version) is None:
        raise ValueError(
            f"{display_path(path)}: KPlugin.Version {version!r} must be X.Y.Z[.W]"
        )
    return version


def load_features(path):
    """Catalog as a list of dicts; raises ValueError with a readable message."""
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {display_path(path)}: {error}") from error
    if not isinstance(data, list):
        raise TypeError("top level must be a JSON array of feature objects")
    if not data:
        raise ValueError("the catalog has no features")
    return data


def _check_field(feature, field, where, problems):
    if field not in feature:
        problems.append(f"{where}: missing field {field!r}")
        return False
    return True


def check_feature(feature, index, problems):
    where = f"feature #{index + 1}"
    if not isinstance(feature, dict):
        problems.append(f"{where}: must be a JSON object")
        return
    for field in REQUIRED_FIELDS:
        _check_field(feature, field, where, problems)

    feature_id = feature.get("id")
    if "id" in feature:
        if not isinstance(feature_id, str) or not ID_PATTERN.match(feature_id):
            problems.append(f"{where}: id {feature_id!r} is not kebab-case")
        else:
            where = f"{feature_id}"

    if "label" in feature and (
        not isinstance(feature["label"], str) or not feature["label"]
    ):
        problems.append(f"{where}: label must be a non-empty string")

    native = feature.get("native")
    if "native" in feature and not isinstance(native, bool):
        problems.append(f"{where}: native must be true or false")

    if "notes" in feature and not isinstance(feature["notes"], str):
        problems.append(f"{where}: notes must be a string")

    status = feature.get("status")
    if "status" in feature and status not in VALID_STATUSES:
        problems.append(
            f"{where}: status {status!r} is not one of {sorted(VALID_STATUSES)}"
        )

    since = feature.get("since")
    if "since" in feature:
        if not isinstance(since, str) or not since:
            problems.append(f"{where}: since must be a non-empty string")
        elif parse_version(since) is None:
            problems.append(f"{where}: since {since!r} must be X.Y.Z[.W]")

    requires = feature.get("requires")
    if "requires" in feature:
        if not isinstance(requires, list) or not all(
            isinstance(item, str) for item in requires
        ):
            problems.append(f"{where}: requires must be an array of strings")
        else:
            for requirement in requires:
                if requirement not in REQUIREMENT_PROBES:
                    problems.append(
                        f"{where}: unknown requirement {requirement!r} "
                        f"(known: {sorted(REQUIREMENT_PROBES)})"
                    )


def validate(features, current_version):
    problems = []
    seen = {}
    current = parse_version(current_version)
    for index, feature in enumerate(features):
        check_feature(feature, index, problems)
        feature_id = feature.get("id") if isinstance(feature, dict) else None
        if isinstance(feature_id, str):
            if feature_id in seen:
                problems.append(f"duplicated id {feature_id!r}")
            seen[feature_id] = True
        since = feature.get("since") if isinstance(feature, dict) else None
        since_version = parse_version(since)
        if (
            current is not None
            and since_version is not None
            and since_version > current
        ):
            where = (
                feature_id if isinstance(feature_id, str) else f"feature #{index + 1}"
            )
            problems.append(
                f"{where}: since {since!r} is newer than the package version "
                f"{current_version}"
            )
    return problems


def requirements_in_use(features):
    """Requirement label -> feature ids that need it, in catalog order."""
    in_use = {}
    for feature in features:
        for requirement in feature.get("requires", []):
            in_use.setdefault(requirement, []).append(feature["id"])
    return in_use


def print_dependencies(features, roots):
    in_use = requirements_in_use(features)
    if not in_use:
        print("features.json: no feature needs an optional module")
        return
    print(f"QML import roots: {', '.join(str(root) for root in roots)}")
    print("Optional modules required by the catalog (informative):")
    missing = []
    for requirement in sorted(in_use):
        path = requirement_path(REQUIREMENT_PROBES[requirement], roots)
        if path.exists():
            print(f"  [ok]      {requirement:<24} {path}")
        else:
            print(f"  [absent]  {requirement:<24} {path}")
            missing.append((requirement, in_use[requirement]))
    if not missing:
        print("All feature requirements are available.")
        return
    print()
    print("Features that stay disabled without them (make deps is informative):")
    for requirement, feature_ids in missing:
        print(f"  - {requirement}: {', '.join(feature_ids)}")


def _selftest_feature(**overrides):
    feature = {
        "id": "sample",
        "label": "Sample",
        "requires": [],
        "native": False,
        "notes": "",
        "status": "stable",
        "since": "0.0.0.1",
    }
    feature.update(overrides)
    return feature


def _selftest_problems(content, version="0.0.0.2"):
    """Problems for a catalog written as JSON text; load errors count as one."""
    with tempfile.TemporaryDirectory() as directory:
        catalog = Path(directory) / "features.json"
        catalog.write_text(content, encoding="utf-8")
        try:
            features = load_features(catalog)
        except (TypeError, ValueError) as error:
            return [str(error)]
        return validate(features, version)


def selftest():
    """Exit 0 when the validator still catches the four classic catalog bugs."""
    cases = (
        ("invalid JSON", "{ not json", "invalid JSON"),
        (
            "duplicated id",
            json.dumps([_selftest_feature(), _selftest_feature()]),
            "duplicated id",
        ),
        (
            "invalid status",
            json.dumps([_selftest_feature(status="shipped")]),
            "status",
        ),
        ("non-object entry", json.dumps(["nope"]), "must be a JSON object"),
        (
            "since newer than the package",
            json.dumps([_selftest_feature(since="0.0.0.3")]),
            "newer than the package version",
        ),
        (
            "since with a bad format",
            json.dumps([_selftest_feature(since="1.2")]),
            "X.Y.Z[.W]",
        ),
    )
    failed = 0
    for name, content, expected in cases:
        problems = _selftest_problems(content)
        if any(expected in problem for problem in problems):
            print(f"selftest: PASS {name}")
        else:
            print(f"selftest: FAIL {name} (problems: {problems})")
            failed += 1
    print("selftest:", "OK" if failed == 0 else "FAIL")
    return 0 if failed == 0 else 1


def main(argv):
    show_deps = False
    paths = []
    for argument in argv:
        if argument in ("-h", "--help"):
            print(USAGE)
            return 0
        if argument == "--deps":
            show_deps = True
        elif argument == "--selftest":
            return selftest()
        elif argument.startswith("-"):
            print(f"features: unknown option {argument!r}", file=sys.stderr)
            print(USAGE, file=sys.stderr)
            return 2
        else:
            paths.append(argument)

    if len(paths) > 1:
        print(f"features: too many catalog paths {paths}", file=sys.stderr)
        print(USAGE, file=sys.stderr)
        return 2

    catalog = Path(paths[0]) if paths else FEATURES
    try:
        features = load_features(catalog)
        version = package_version()
    except (TypeError, ValueError) as error:
        print(f"features: FAIL {error}")
        return 1

    problems = validate(features, version)
    if problems:
        print("features: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    stable = sum(1 for feature in features if feature.get("status") == "stable")
    planned = len(features) - stable
    print(
        f"features: {len(features)} entries ({stable} stable, {planned} planned/needs-native)"
    )
    print(
        "features: OK (fields, statuses, unique ids, known requirements, "
        f"since <= {version})"
    )

    if show_deps:
        print()
        print_dependencies(features, qml_roots())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
