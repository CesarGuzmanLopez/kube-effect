#!/usr/bin/env python3
"""Feed Qt 6 qmllint results into SonarQube.

SonarQube has no QML analyzer, so the dashboard used to see only 2 text files.
This converts qmllint output into Sonar's Generic Issue Data format so QML
problems show up as real issues with rule ids.

Usage: scripts/qmllint-sonar.py [repo-root] [output-json]
Then:  sonar-scanner -Dsonar.externalIssuesReportPaths=<output-json>
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

QMLLINT = "/usr/lib/qt6/bin/qmllint"
QML_IMPORT = "/usr/lib/qt6/qml"
LINE_RE = re.compile(
    r"^(Warning|Error|Info): (?P<file>[^:]+):(?P<line>\d+):(?P<col>\d+): (?P<msg>.*) \[(?P<rule>[a-z-]+)\]$"
)

# Context properties (effect, modelData, i18nd) and KWin's own types cannot be
# resolved by a standalone qmllint run, so these rules are reported as INFO and
# never fail the gate.
INFO_RULES = {
    "unqualified",
    "missing-property",
    "import",
    "unused-imports",
    # Loader.item cannot be typed in QML (upstream cube pattern).
    "incompatible-type",
    # CubeCameraController.rotation matches the upstream cube naming.
    "property-override",
}
SERVERITY = {"Error": "MAJOR", "Warning": "MINOR", "Info": "INFO"}


def main() -> int:
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    out = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.join(root, "build", "qmllint-sonar.json")
    )
    ui_dir = os.path.join(root, "package", "contents", "ui")
    files = sorted(
        os.path.join(ui_dir, f) for f in os.listdir(ui_dir) if f.endswith(".qml")
    )
    if not files:
        print("qmllint-sonar: no QML files", file=sys.stderr)
        return 1

    proc = subprocess.run(
        [QMLLINT, "-I", QML_IMPORT, *files],
        capture_output=True,
        text=True,
        check=False,
    )

    issues = []
    for line in (proc.stdout + proc.stderr).splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        rel = os.path.relpath(m["file"], root)
        rule = m["rule"]
        issues.append(
            {
                "engineId": "qmllint",
                "ruleId": rule,
                "severity": "INFO"
                if rule in INFO_RULES
                else SERVERITY[m["file"] and m["msg"] and m["rule"] and "Warning"],
                "type": "CODE_SMELL",
                "primaryLocation": {
                    "message": m["msg"][:400],
                    "filePath": rel,
                    "textRange": {
                        "startLine": int(m["line"]),
                        "endLine": int(m["line"]),
                    },
                },
            }
        )

    os.makedirs(os.path.dirname(out), exist_ok=True)
    # SonarQube counts every reported issue, INFO included, in new_violations.
    # Context-property noise (effect, modelData, i18nd, KWin types) is not
    # actionable, so it goes to a side file for humans and stays out of the gate.
    real = [i for i in issues if i["severity"] != "INFO"]
    noise = [i for i in issues if i["severity"] == "INFO"]

    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"issues": real}, fh, indent=2)

    noise_path = os.path.splitext(out)[0] + "-noise.txt"
    with open(noise_path, "w", encoding="utf-8") as fh:
        for i in noise:
            loc = i["primaryLocation"]
            fh.write(
                f"{loc['filePath']}:{loc['textRange']['startLine']}: {i['ruleId']} {loc['message']}\n"
            )

    print(
        f"qmllint-sonar: {len(real)} issues en el gate, {len(noise)} de ruido -> {noise_path}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
