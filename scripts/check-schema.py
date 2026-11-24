#!/usr/bin/env python3
"""Schema invariants for the KKube effect (stdlib only, runs in CI).

The generic scripted KCM binds config.ui widgets to config/main.xml entries by
name, and a non-editable QComboBox to the *stored integer index* of an Enum.
kwinrc therefore keeps the enum index, so a reordered choice or a constants.js
table out of sync silently changes what every user sees. The KCM also picks the
widget by the KConfigXT type: KConfigDialogManager writes the widget's user
property through the skeleton item, so a mismatched pair either drops the value
or silently truncates it (a QLineEdit for a Url, a QSpinBox for a Double, an
int widget for a Color). These checks catch exactly that drift, plus the layout
mistakes the KCM cannot report:

  * every Enum default is one of its choices, and choice names are unique;
  * constants.js mirrors main.xml: same enum names, same order, indexes 0..n;
  * every entry has exactly one kcfg_* widget and vice versa;
  * each widget class matches the entry type (Url -> KUrlRequester,
    Color -> KColorButton, Int -> QSlider/QSpinBox, Double -> QDoubleSpinBox,
    Enum -> QComboBox, Bool -> QCheckBox, String -> QLineEdit);
  * no two form items share a (row, column) cell within one QFormLayout (the
    second one is dropped); the layout is walked recursively so widgets nested
    in tabs, scroll areas and group boxes are checked too;
  * Enum combos list the choices in schema order;
  * range widgets (QSlider, spin boxes) use the schema min/max when declared.

Run: python3 scripts/check-schema.py   (exit 1 with one line per problem)
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "package/contents/config/main.xml"
UI = ROOT / "package/contents/ui/config.ui"
CONSTANTS = ROOT / "package/contents/ui/constants.js"

KCFG = "{http://www.kde.org/standards/kcfg/1.0}"
JS_ENUM = re.compile(r"const\s+(\w+)\s*=\s*\{(.*?)\};", re.DOTALL)
JS_FIELD = re.compile(r"(\w+)\s*:\s*(-?\d+)")
SPIN_CLASSES = {"QSpinBox", "QDoubleSpinBox"}
RANGE_CLASSES = SPIN_CLASSES | {"QSlider"}
# KConfigXT type -> widget classes the generic KCM can bind to it.
WIDGET_CLASSES = {
    "Bool": {"QCheckBox"},
    "Enum": {"QComboBox"},
    "Int": {"QSlider", "QSpinBox"},
    "Double": {"QDoubleSpinBox"},
    "String": {"QLineEdit"},
    "Url": {"KUrlRequester"},
    "Color": {"KColorButton"},
}


def text_of(entry, tag):
    node = entry.find(f"{KCFG}{tag}")
    return (node.text or "").strip() if node is not None else ""


def read_schema():
    """name -> type/choices/default/min/max, in file order."""
    entries = {}
    for entry in ET.parse(CONFIG).getroot().iter(f"{KCFG}entry"):
        entries[entry.get("name")] = {
            "type": entry.get("type"),
            "choices": [c.get("name") for c in entry.iter(f"{KCFG}choice")],
            "default": text_of(entry, "default"),
            "min": text_of(entry, "min"),
            "max": text_of(entry, "max"),
        }
    return entries


def read_constants():
    """Enum name -> [(member, index)], from the const tables in constants.js."""
    source = CONSTANTS.read_text(encoding="utf-8")
    return {
        match.group(1): [(k, int(v)) for k, v in JS_FIELD.findall(match.group(2))]
        for match in JS_ENUM.finditer(source)
    }


def _read_widgets(root):
    widgets = {}
    duplicates = []
    for widget in root.iter("widget"):
        name = widget.get("name") or ""
        if not name.startswith("kcfg_"):
            continue
        entry = name[len("kcfg_") :]
        if entry in widgets:
            duplicates.append(entry)
        widgets[entry] = widget
    return widgets, duplicates


def _occupied_cells(item):
    """(row, column) cells one layout item occupies, honouring row/col spans."""
    row, column = item.get("row"), item.get("column")
    if row is None or column is None:
        return []
    rowspan = int(item.get("rowspan") or 1)
    colspan = int(item.get("colspan") or 1)
    return [
        (r, c)
        for r in range(int(row), int(row) + rowspan)
        for c in range(int(column), int(column) + colspan)
    ]


def _layout_cells(layout):
    occupied = []
    for item in layout.findall("item"):
        occupied.extend(_occupied_cells(item))
    return occupied


def _read_form_cells(root):
    # Cells are only unique inside one layout: every tab/section has its own
    # QFormLayout, so a (row, column) pair repeats across them by design.
    # colspan/rowspan occupy several cells: an item spanning (0,0)-(0,1)
    # clashes with a separate (0,1) item, which QFormLayout would drop.
    return [
        _layout_cells(layout)
        for layout in root.iter("layout")
        if layout.get("class") == "QFormLayout"
    ]


def read_ui():
    """(kcfg widgets by entry, duplicated names, form cells per layout)."""
    root = ET.parse(UI).getroot()
    widgets, duplicates = _read_widgets(root)
    cells_by_layout = _read_form_cells(root)
    return widgets, duplicates, cells_by_layout


def norm(value):
    return "".join(ch for ch in value.lower() if ch.isalnum())


def combo_texts(widget):
    texts = []
    for item in widget.findall("item"):
        label = item.find("property[@name='text']/string")
        texts.append((label.text or "") if label is not None else "")
    return texts


def number_property(widget, name):
    for node in widget.findall(f"property[@name='{name}']/*"):
        if node.text is not None and node.text.strip():
            return float(node.text)
    return None


def check_enums(entries, constants, problems):
    for name, info in entries.items():
        if info["type"] != "Enum":
            continue
        choices = info["choices"]
        if len(set(choices)) != len(choices):
            problems.append(f"main.xml {name}: duplicate choice names {choices}")
        if info["default"] not in choices:
            problems.append(
                f"main.xml {name}: default {info['default']!r} is not one of {choices}"
            )
        table = constants.get(name)
        if table is None:
            problems.append(f"constants.js: missing enum table {name}")
            continue
        members = [member for member, _ in table]
        values = [value for _, value in table]
        if members != choices:
            problems.append(
                f"constants.js {name}: {members} does not match main.xml {choices}"
            )
        elif values != list(range(len(choices))):
            problems.append(
                f"constants.js {name}: values {values} must be indexes "
                f"0..{len(choices) - 1}"
            )


def check_widget_sets(entries, widgets, problems):
    missing_widget = sorted(set(entries) - set(widgets))
    orphan_widget = sorted(set(widgets) - set(entries))
    if missing_widget:
        problems.append(f"config.ui: entry without widget {missing_widget}")
    if orphan_widget:
        problems.append(f"config.ui: widget without entry {orphan_widget}")


def check_duplicate_cells(cells_by_layout, problems):
    for index, cells in enumerate(cells_by_layout, 1):
        duplicated = sorted({cell for cell in cells if cells.count(cell) > 1})
        if duplicated:
            problems.append(
                f"config.ui: duplicated form cells in form layout #{index} "
                f"(row, column) {duplicated}"
            )


def check_widget_class(name, widget, info, problems):
    allowed = WIDGET_CLASSES.get(info["type"])
    klass = widget.get("class")
    if allowed is None:
        problems.append(
            f"config.ui kcfg_{name}: no widget class known for KConfigXT type "
            f"{info['type']!r} (add it to WIDGET_CLASSES)"
        )
    elif klass not in allowed:
        expected = "/".join(sorted(allowed))
        problems.append(
            f"config.ui kcfg_{name}: {klass} cannot bind a {info['type']} entry "
            f"(expected {expected})"
        )


def check_combo(name, widget, info, problems):
    if widget.get("class") != "QComboBox" or not info["choices"]:
        return
    # An editable combo makes KConfigDialogManager save the text instead of the
    # index, silently corrupting the enum stored in kwinrc.
    editable = widget.find("property[@name='editable']/bool")
    if editable is not None and (editable.text or "").strip() == "true":
        problems.append(f"config.ui kcfg_{name}: enum combo must not be editable")
    texts = combo_texts(widget)
    if len(texts) != len(info["choices"]):
        problems.append(
            f"config.ui kcfg_{name}: {len(texts)} items, {len(info['choices'])} choices"
        )
    else:
        for choice, text in zip(info["choices"], texts):
            if norm(choice) not in norm(text):
                problems.append(
                    f"config.ui kcfg_{name}: item {text!r} does not match "
                    f"choice {choice!r} (order must follow main.xml)"
                )


def check_bounds(name, widget, info, problems):
    if widget.get("class") not in RANGE_CLASSES or not info["min"] or not info["max"]:
        return
    minimum = number_property(widget, "minimum")
    maximum = number_property(widget, "maximum")
    if minimum is None or maximum is None:
        problems.append(f"config.ui kcfg_{name}: range widget without bounds")
    elif abs(minimum - float(info["min"])) > 1e-6:
        problems.append(f"config.ui kcfg_{name}: minimum {minimum} != {info['min']}")
    elif abs(maximum - float(info["max"])) > 1e-6:
        problems.append(f"config.ui kcfg_{name}: maximum {maximum} != {info['max']}")


def check_ui(entries, widgets, duplicates, cells_by_layout, problems):
    check_widget_sets(entries, widgets, problems)
    if duplicates:
        problems.append(
            f"config.ui: duplicated kcfg_ widget names {sorted(set(duplicates))}"
        )
    check_duplicate_cells(cells_by_layout, problems)

    for name, widget in widgets.items():
        info = entries.get(name)
        if info is None:
            continue
        check_widget_class(name, widget, info, problems)
        check_combo(name, widget, info, problems)
        check_bounds(name, widget, info, problems)


def main():
    entries = read_schema()
    constants = read_constants()

    problems = []
    check_enums(entries, constants, problems)

    if not UI.exists():
        # A virgin cube (e.g. the upstream KDE cube) ships no config.ui: it
        # relies on the generic scripted KCM, which auto-generates the form from
        # main.xml. There is no UI to cross-check then, so only the enum/schema
        # and constants.js checks run.
        print(
            f"schema: {len(entries)} entries, no config.ui (generic KCM); UI checks skipped"
        )
        if problems:
            print("FAIL")
            for problem in problems:
                print(f" - {problem}")
            return 1
        print("OK: enum defaults/order, constants.js (no config.ui)")
        return 0

    widgets, duplicates, cells_by_layout = read_ui()
    cells = sum(len(occupied) for occupied in cells_by_layout)
    check_ui(entries, widgets, duplicates, cells_by_layout, problems)

    enums = sum(1 for info in entries.values() if info["type"] == "Enum")
    print(
        f"schema: {len(entries)} entries ({enums} enums), "
        f"{len(widgets)} kcfg widgets, {cells} form cells"
    )
    if problems:
        print("FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print("OK: enum defaults/order, constants.js, widgets and form cells")
    return 0


if __name__ == "__main__":
    sys.exit(main())
