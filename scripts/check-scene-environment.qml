import QtQuick
import QtQuick3D

// Runs inside scripts/check-scene-environment.py. The scene environment is
// declared the way ScreenView.qml declares it since ADR-022: ONE inline
// SceneEnvironment object (no Loader), with probeExposure fed by a binding and
// a Behavior to blend the change. The goal is to catch a property that does
// not exist (TypeError at runtime) or a binding that breaks when the value is
// animated on a non-Item QtQuick3D object. No KWin and no renderer: the engine
// is set to the null backend.
Item {
  id: root

  property real exposure: 1.0
  property bool ok: true
  property string log: ""

  readonly property QtObject environment: sceneEnvironment

  function check(name, actual, expected) {
    const passed = actual === expected;
    const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected " + expected + ")");
    log = log.length > 0 ? log + "\n" + line : line;
    if (!passed)
      ok = false;
  }

  function checkClose(name, actual, expected, epsilon) {
    const tolerance = epsilon === undefined ? 1e-5 : epsilon;
    const passed = Math.abs(actual - expected) <= tolerance;
    const line = (passed ? "PASS " : "FAIL ") + name + " = " + actual + (passed ? "" : " (expected ~" + expected + ")");
    log = log.length > 0 ? log + "\n" + line : line;
    if (!passed)
      ok = false;
  }

  // Untouched environment: pins the engine's default, which is the "no dim"
  // value the helper returns (probeExposure 1.0).
  SceneEnvironment {
    id: defaultEnvironment
  }

  // Same shape as ScreenView's inline environment: a plain child object of
  // the root (Item.data accepts QObjects), not a loaded component.
  SceneEnvironment {
    id: sceneEnvironment
    backgroundMode: SceneEnvironment.SkyBox
    probeExposure: root.exposure
    Behavior on probeExposure {
      NumberAnimation {
        duration: 120
        easing.type: Easing.OutQuad
      }
    }
  }

  Component.onCompleted: {
    check("environment created", environment !== null, true);
    if (environment === null) {
      return;
    }
    check("default probeExposure", defaultEnvironment.probeExposure, 1);
    check("exposure at start", environment.probeExposure, root.exposure);
  }
}
