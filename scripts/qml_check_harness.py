"""Shared scaffolding for the offscreen QML checks in scripts/.

check-cap.py and check-cylinder.py (and, later, the rest of the mesh checks)
load a real QML harness in a headless QML engine, read vertex data back and
validate it in Python. What they had in common lives here, once:

  * require_pyside(): the PySide6 import guard with the skip contract the CI
    depends on — a missing PySide6 (or QtQuick3D.Helpers at load time) makes
    the check print "<label>: skipped (...)" and exit 0, never fail.
  * ROOT: the repository root, derived from this module (scripts/ sits one
    level below the root, exactly like the check scripts themselves), so the
    checks run from any working directory.
  * messages / collect_errors / qml_problems(): the qInstallMessageHandler
    sink that keeps only the QML errors that break a run.
  * boot_qml(): offscreen engine start + QML load + component create, with
    the shared failure prints parameterised by the label.
  * view_boot(): the RENDER boot the grab gates share (check-cylinder-overlap
    and check-cap-overlap): warm-up load with no Python message handler (a
    handler from the first load deadlocks the QML type-loader thread against
    the GIL), then qInstallMessageHandler, then the real QQuickView; returns
    (view, error-list) so the caller only adds its scenario logic.
  * pump(): processEvents-until-deadline, the one wait helper every grab
    gate needs after writing QML properties.
  * read_mesh() (+ to_xyz/to_xy): reading positions/normals/uv0s back from a
    ProceduralMesh; the indexes arrive as a JSON string (QList<uint> has no
    Python converter, see the check-*.qml harnesses).
  * mesh_size_problems(): the array-length preamble every mesh validator
    needs. The message strings are literal on purpose: the selftests of both
    check scripts compare detections by text.
  * dispatch(): the --selftest switch, so each check's main() is only the
    check itself, and selftest_verdict(): the shared --selftest verdict
    print plus exit code.
"""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Only these signatures fail a render scenario (the check-constants.py list,
# mirrored by check-video-dome.py): other qWarnings are legitimate Qt chatter
# (shader backend, vsync, ...) and must NOT break a gate.
QML_ERROR_SIGNATURES = ("TypeError", "ReferenceError", "is not defined")

messages: list[str] = []


def collect_errors(_mode, _context, message):
    """QML handler: keep only the errors that sink a check run."""
    if (
        "TypeError" in message
        or "ReferenceError" in message
        or "is not defined" in message
        or "Cannot assign" in message
        or "non-existent" in message
    ):
        messages.append(message)


def qml_problems():
    """The collected QML errors, formatted the way every check prints them."""
    return [f"qml: {message.strip()}" for message in messages]


def selftest_verdict(label, failures):
    """Print the selftest verdict the way every check's --selftest does.

    Returns the process exit code: 1 when any validator gap was found."""
    print(f"{label} --selftest:", "OK" if not failures else "FAIL")
    for failure in failures:
        print(f" - {failure}")
    return 0 if not failures else 1


def require_pyside(label):
    """Honour the skip contract at import time: no PySide6, no CI failure.

    The check scripts call this at module level, so --selftest is reached
    only when the dependency really imports (the skip print must come
    before anything else the script could print).
    """
    try:
        # The real names the checks bind; boot_qml re-imports them cheaply
        # from the module cache. Guarding the names (not just the packages)
        # is what let the per-script try/except skip a broken PySide6.
        from PySide6.QtCore import QUrl, qInstallMessageHandler  # noqa: F401
        from PySide6.QtGui import QGuiApplication  # noqa: F401
        from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: F401
    except ImportError:  # pragma: no cover - optional dependency
        print(f"{label}: skipped (PySide6 is not installed)")
        sys.exit(0)


def boot_qml(label, qml_file):
    """Start the offscreen QML engine and create the harness at qml_file.

    Returns (application, engine, component, harness, status); status is
    None on success, 0 when QtQuick3D.Helpers is missing (skipped) and 1 on
    a load or create error. The caller keeps application/engine/component
    alive for as long as it uses the harness (Qt object lifetimes).
    """
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine

    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    # Same software-only setup as the other load checks: no GPU, no window.
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    qInstallMessageHandler(collect_errors)
    application = QGuiApplication(sys.argv)
    engine = QQmlEngine()
    component = QQmlComponent(engine)
    component.loadUrl(QUrl.fromLocalFile(str(qml_file)))
    if component.isError():
        errors = " ".join(error.toString() for error in component.errors())
        if "QtQuick3D.Helpers" in errors or "not installed" in errors:
            print(f"{label}: skipped (QtQuick3D.Helpers is not installed)")
            return application, engine, component, None, 0
        print(f"{label}: FAIL")
        for error in component.errors():
            print(f" - {error}")
        return application, engine, component, None, 1
    harness = component.create()
    if harness is None:
        print(f"{label}: FAIL could not create the harness")
        return application, engine, component, None, 1
    return application, engine, component, harness, None


def view_boot(label, engine, qml_file, size, error_signatures=QML_ERROR_SIGNATURES):
    """Render boot shared by the grab gates (QQuickView, real platform).

    The warm-up load runs BEFORE any Python message handler is installed: a
    handler from the first load deadlocks the QML type-loader thread against
    the GIL (measured in check-video-dome.py: 12 s hang inside
    QQmlTypeLoader::getType). With every type cached, the handler below only
    ever runs on the main thread and collects the failing signatures.

    Returns (view, errors) — view is None on a warm-up or engine failure
    (the message is printed with `label`, the caller maps it to its exit
    code); errors is the live list the caller checks before each verdict.
    The caller keeps the view alive; the view is shown and pumped once
    before being returned, ready for property writes + pump() + grab.
    """
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtQuick import QQuickView

    url = QUrl.fromLocalFile(str(qml_file))

    warm = QQuickView(engine, None)
    warm.setSource(url)
    if warm.status() != QQuickView.Status.Ready:
        print(f"{label}: FAIL (warm-up)")
        for error in warm.errors():
            print(f" - {error.toString()}")
        return None, []
    warm.destroy()

    errors: list[str] = []

    def forward_qml_warnings(_mode, _context, message):
        if any(signature in message for signature in error_signatures):
            errors.append(message)

    qInstallMessageHandler(forward_qml_warnings)

    view = QQuickView(engine, None)
    view.resize(*size)
    view.setSource(url)
    if view.status() != QQuickView.Status.Ready:
        print(f"{label}: FAIL (engine)")
        for error in view.errors():
            print(f" - {error.toString()}")
        return None, errors
    view.show()
    # First frame: the scene graph needs a few loop passes before the
    # Texture.sourceItem grabs (faces, caps) hold real pixels.
    pump(1.5)
    return view, errors


def pump(seconds):
    """Drive the event loop for a bounded wall-clock stretch.

    After a property write the QML bindings, the Loader activation and the
    Texture.sourceItem re-grab need loop passes before the next grabWindow()
    shows the new frame; a busy wait without processEvents starves them (the
    same deadline loop check-cap.py uses for its asynchronous Image).
    """
    import time

    from PySide6.QtGui import QGuiApplication

    application = QGuiApplication.instance()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        application.processEvents()
        time.sleep(0.005)


def to_xyz(value):
    """QML list items arrive as QVector2D/3D or plain numbers; normalise."""
    if callable(getattr(value, "x", None)):
        return value.x(), value.y(), value.z()
    return float(value[0]), float(value[1]), float(value[2])


def to_xy(value):
    if callable(getattr(value, "x", None)):
        return float(value.x()), float(value.y())
    return float(value[0]), float(value[1])


def read_mesh(mesh, indexes):
    positions = [to_xyz(v) for v in mesh.property("positions")]
    normals = [to_xyz(v) for v in mesh.property("normals")]
    uvs = [to_xy(v) for v in mesh.property("uv0s")]
    # QList<uint> has no Python converter: the QML harness hands the indexes
    # as a JSON string.
    index_list = [int(v) for v in json.loads(indexes)]
    return positions, normals, uvs, index_list


def mesh_size_problems(
    positions, normals, uvs, indexes, vertex_count, expected_indexes
):
    """Check the mesh arrays against the expected sizes (validator preamble).

    Returns (problems, malformed): malformed is True when the position count
    itself is wrong, so the caller must stop validating — the per-vertex
    loops assume the array lengths. The messages are the literal strings
    both check validators printed before this helper existed; their
    selftests compare detections by text."""
    problems = []
    if len(positions) != vertex_count:
        problems.append(
            f"positions: {len(positions)} vertices, expected {vertex_count}"
        )
        return problems, True
    if len(normals) != vertex_count:
        problems.append(f"normals: {len(normals)}, expected {vertex_count}")
    if len(uvs) != vertex_count:
        problems.append(f"uvs: {len(uvs)}, expected {vertex_count}")
    if len(indexes) != expected_indexes:
        problems.append(f"indexes: {len(indexes)}, expected {expected_indexes}")
    return problems, False


def dispatch(argv, selftest_main, check_main):
    """Route --selftest to the validator's selftest, else run the check.

    The PySide6 guard (require_pyside) has already run at import time, so
    without the dependency both branches are unreachable — exactly the
    old behaviour of every check script that exits 0 with a skip notice."""
    if "--selftest" in argv[1:]:
        return selftest_main()
    return check_main()
