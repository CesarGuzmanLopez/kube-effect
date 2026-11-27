#!/usr/bin/env python3
"""Runtime check of the generic KCM form (package/contents/ui/config.ui).

`check-schema.py` reads the XML and never loads the form; this script builds it
offscreen with QUiLoader, which is what KWin's KCM does at runtime, so it also
catches a widget class that cannot be created or a user property that does not
carry the KConfigXT type. It verifies, against contents/config/main.xml:

  * the form loads and QUiLoader reports no error;
  * every kcfg_* widget exists once (same names as the entries);
  * Url -> KUrlRequester with USER url:QUrl,
    Color -> KColorButton with USER color:QColor,
    Int -> QSlider/QSpinBox with an int USER property,
    Double -> QDoubleSpinBox, Enum -> QComboBox, Bool -> QCheckBox,
    String -> QLineEdit;
  * range widgets carry the schema min/max;
  * enum combos are not editable and list the choices in schema order;
  * the background mode combo really switches its QStackedWidget, i.e. the
    <connections> block survived QUiLoader (the generic KCM has no logic of its
    own, so this connection is the whole dynamic behaviour);
  * the Advanced tab behaves as designed: the dim amount starts disabled and
    follows its checkbox, the Plus block starts hidden and follows its toggle,
    and the two separators are real horizontal lines (ADR-018).

config.ui needs the KF6 designer plugins (kio6widgets, kwidgetsaddons6widgets)
for the pickers, and PySide6 for this script. Without PySide6 the check is
skipped (exit 0) so CI does not depend on it; run it locally before touching
the form.
"""

import sys

try:
    from PySide6.QtCore import QFile
    from PySide6.QtGui import QColor
    from PySide6.QtUiTools import QUiLoader
    from PySide6.QtWidgets import (
        QApplication,
        QCheckBox,
        QComboBox,
        QFrame,
        QSlider,
        QSpinBox,
        QStackedWidget,
        QWidget,
    )
except ImportError:  # pragma: no cover - optional dependency
    print("check-ui: skipped (PySide6 is not installed)")
    sys.exit(0)

import os
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENTS = ROOT / "package/contents"
KCFG = "{http://www.kde.org/standards/kcfg/1.0}"
CLASS_FOR_TYPE = {
    "Bool": {"QCheckBox"},
    "Enum": {"QComboBox"},
    "Int": {"QSlider", "QSpinBox"},
    "Double": {"QDoubleSpinBox"},
    "String": {"QLineEdit"},
    "Url": {"KUrlRequester"},
    "Color": {"KColorButton"},
}
# QComboBox is deliberately absent: KConfigDialogManager treats a plain
# QComboBox through its own code path and reads/writes currentIndex() (the enum
# index) instead of the USER property, so the check below is "not editable".
USER_TYPE_FOR_KCFG_TYPE = {
    "Bool": "bool",
    "Int": "int",
    "Double": "double",
    "String": "QString",
    "Url": "QUrl",
    "Color": "QColor",
}


def read_schema():
    entries = {}
    for entry in ET.parse(CONTENTS / "config/main.xml").getroot().iter(f"{KCFG}entry"):
        minimum = entry.find(f"{KCFG}min")
        maximum = entry.find(f"{KCFG}max")
        entries[entry.get("name")] = {
            "type": entry.get("type"),
            "choices": [c.get("name") for c in entry.iter(f"{KCFG}choice")],
            "min": float(minimum.text) if minimum is not None else None,
            "max": float(maximum.text) if maximum is not None else None,
        }
    return entries


def norm(value):
    return "".join(ch for ch in value.lower() if ch.isalnum())


def _load_form():
    form_file = QFile(str(CONTENTS / "ui/config.ui"))
    if not form_file.open(QFile.ReadOnly):
        print(f"check-ui: FAIL cannot open {form_file.fileName()}")
        return None
    loader = QUiLoader()
    form = loader.load(form_file)
    form_file.close()
    if form is None:
        print(
            f"check-ui: FAIL QUiLoader could not build the form: {loader.errorString()}"
        )
    return form


def _collect_widgets(form, problems):
    widgets = {}
    for widget in form.findChildren(QWidget):
        name = widget.objectName()
        if not name.startswith("kcfg_"):
            continue
        key = name[len("kcfg_") :]
        if key in widgets:
            problems.append(f"kcfg_{key}: created twice")
        widgets[key] = widget
    return widgets


def _check_widget_sets(entries, widgets, problems):
    missing = sorted(entries.keys() - widgets.keys())
    orphan = sorted(widgets.keys() - entries.keys())
    if missing:
        problems.append(f"entry without widget: {missing}")
    if orphan:
        problems.append(f"widget without entry: {orphan}")


def _check_widget_type(name, widget, info, problems):
    meta = widget.metaObject()
    expected = CLASS_FOR_TYPE.get(info["type"])
    if expected is None:
        problems.append(f"kcfg_{name}: no widget class known for {info['type']!r}")
        return None
    if meta.className() not in expected:
        problems.append(
            f"kcfg_{name}: {meta.className()} cannot bind a {info['type']} entry "
            f"(expected {'/'.join(sorted(expected))})"
        )
        return None
    return meta


def _check_widget_properties(name, widget, info, meta, problems):
    user = meta.userProperty()
    wanted = USER_TYPE_FOR_KCFG_TYPE.get(info["type"])
    if wanted is not None and user.typeName() != wanted:
        problems.append(
            f"kcfg_{name}: user property {user.name()}:{user.typeName()} != {wanted}"
        )
    if info["type"] == "Color" and not isinstance(widget.property("color"), QColor):
        problems.append(f"kcfg_{name}: color property is not a QColor")


def _check_range(name, widget, info, meta, problems):
    if info["min"] is None or info["max"] is None:
        return
    if isinstance(widget, QSlider):
        minimum, maximum = widget.minimum(), widget.maximum()
    elif meta.className() == "QDoubleSpinBox":
        minimum, maximum = (
            widget.property("minimum"),
            widget.property("maximum"),
        )
    else:
        minimum = maximum = None
    if minimum is not None and (
        abs(minimum - info["min"]) > 1e-6 or abs(maximum - info["max"]) > 1e-6
    ):
        problems.append(
            f"kcfg_{name}: range {minimum}..{maximum} != {info['min']}..{info['max']}"
        )


def _check_combo(name, widget, info, problems):
    if not isinstance(widget, QComboBox) or not info["choices"]:
        return
    if widget.isEditable():
        problems.append(f"kcfg_{name}: enum combo must not be editable")
    texts = [widget.itemText(i) for i in range(widget.count())]
    if len(texts) != len(info["choices"]):
        problems.append(
            f"kcfg_{name}: {len(texts)} items, {len(info['choices'])} choices"
        )
    else:
        for choice, text in zip(info["choices"], texts):
            if norm(choice) not in norm(text):
                problems.append(
                    f"kcfg_{name}: item {text!r} does not match choice "
                    f"{choice!r} (order must follow main.xml)"
                )


def _check_mode_stack(form, problems):
    """The mode combo must switch the QStackedWidget through <connections>.

    The generic KCM keeps no logic: it loads the form with QUiLoader and lets
    KConfigDialogManager write the saved enum index into the combo. If the
    <connection> is missing or malformed, the combo changes and the stack does
    not, so this runtime check is the only guard on that behaviour.
    """
    combo = form.findChild(QComboBox, "kcfg_Background")
    stack = form.findChild(QStackedWidget, "bgModeStack")
    if combo is None or stack is None:
        problems.append("config.ui: kcfg_Background and bgModeStack are required")
        return
    if combo.count() != stack.count():
        problems.append(
            f"bgModeStack: {stack.count()} pages for {combo.count()} background modes"
        )
        return
    # Visit every mode, starting with one that differs from the initial page so
    # the first step also proves the connection fires.
    order = list(range(1, combo.count())) + [0]
    for index in order:
        combo.setCurrentIndex(index)
        if stack.currentIndex() != index:
            problems.append(
                f"bgModeStack: combo index {index} leaves page {stack.currentIndex()} "
                "(the <connection> is missing or does not match)"
            )


def _check_cap_stack(form, problems):
    """The cap content combo must switch the cap pages (ADR-027).

    Same guard as _check_mode_stack, for the second stacked block of the
    form: the pages follow the CapContent enum order (Color=0, Gradient=1,
    Image=2) and the only thing that moves them is the designer connection
    recreated by QUiLoader, so the wiring has to be exercised, not parsed.
    """
    combo = form.findChild(QComboBox, "kcfg_CapContent")
    stack = form.findChild(QStackedWidget, "capContentStack")
    if combo is None or stack is None:
        problems.append("config.ui: kcfg_CapContent and capContentStack are required")
        return
    if combo.count() != stack.count():
        problems.append(
            f"capContentStack: {stack.count()} pages for {combo.count()} cap contents"
        )
        return
    order = list(range(1, combo.count())) + [0]
    for index in order:
        combo.setCurrentIndex(index)
        if stack.currentIndex() != index:
            problems.append(
                f"capContentStack: combo index {index} leaves page {stack.currentIndex()} "
                "(the <connection> is missing or does not match)"
            )


def _check_advanced_behaviour(form, problems):
    """The Advanced tab is the only dynamic part left besides the mode stack.

    Nothing here is kcfg-bound logic: the whole behaviour is the <connections>
    block, so it has to be exercised, not just parsed.
    """
    dim = form.findChild(QCheckBox, "kcfg_DimWhileRotating")
    amount = form.findChild(QSpinBox, "kcfg_DimWhileRotatingAmount")
    if dim is None or amount is None:
        problems.append("config.ui: dim checkbox and amount spin box are required")
    else:
        if amount.isEnabled():
            problems.append("kcfg_DimWhileRotatingAmount: must start disabled")
        dim.setChecked(True)
        if not amount.isEnabled():
            problems.append(
                "kcfg_DimWhileRotatingAmount: toggled(true) does not enable it"
            )
        dim.setChecked(False)
        if amount.isEnabled():
            problems.append(
                "kcfg_DimWhileRotatingAmount: toggled(false) does not disable it"
            )

    toggle = form.findChild(QCheckBox, "showPlusSection")
    section = form.findChild(QWidget, "plusSection")
    if toggle is None or section is None:
        problems.append("config.ui: showPlusSection and plusSection are required")
    else:
        if not section.isHidden():
            problems.append("plusSection: must start hidden")
        toggle.setChecked(True)
        if section.isHidden():
            problems.append("plusSection: toggled(true) does not show it")
        toggle.setChecked(False)
        if not section.isHidden():
            problems.append("plusSection: toggled(false) does not hide it")

    for name in ("advancedSeparator1", "advancedSeparator2"):
        separator = form.findChild(QFrame, name)
        if separator is None:
            problems.append(f"config.ui: missing separator {name}")
        elif separator.frameShape() != QFrame.Shape.HLine:
            problems.append(f"{name}: frameShape is not HLine")


def _check_widget(name, widget, info, problems):
    meta = _check_widget_type(name, widget, info, problems)
    if meta is None:
        return
    _check_widget_properties(name, widget, info, meta, problems)
    _check_range(name, widget, info, meta, problems)
    _check_combo(name, widget, info, problems)


def main():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    QApplication(sys.argv)

    entries = read_schema()
    form = _load_form()
    if form is None:
        return 1

    problems = []
    widgets = _collect_widgets(form, problems)
    _check_widget_sets(entries, widgets, problems)

    for name, info in sorted(entries.items()):
        widget = widgets.get(name)
        if widget is None:
            continue
        _check_widget(name, widget, info, problems)

    _check_mode_stack(form, problems)
    _check_cap_stack(form, problems)
    _check_advanced_behaviour(form, problems)

    print(f"check-ui: {len(entries)} entries, {len(widgets)} widgets created")
    if problems:
        print("check-ui: FAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1
    print(
        "check-ui: OK (widgets, user property types, bounds, combo order, "
        "mode combo -> stacked pages, Advanced toggles and separators)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
