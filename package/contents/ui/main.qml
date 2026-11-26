/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property bool activated: false
    readonly property int animationDuration: Kirigami.Units.longDuration

    // Output name under the pointer when the effect was last activated. The
    // ScreenView delegate asks for it when CursorScreenOnly is on (ADR-014).
    // Captured here, once per activation, because the requirement is "the
    // screen the pointer was on at activation", not "wherever it is now".
    // Workspace.cursorPos and Workspace.screenAt() exist in KWin 6.8
    // (src/scripting/workspace_wrapper.h, both exposed to QML); if an older
    // KWin lacks screenAt(), this falls back to the active window's output,
    // which is only an approximation of the pointer position.
    property string cursorScreenName: ""

    // The delegate of a SceneEffect is evaluated ONCE (KWin does not re-resolve
    // it when desktops are added or removed): Qt.createComponent() inside a
    // binding left the placeholder stuck at 3 desktops and the cube alive below
    // 2 (doc/trucos-aprendidos.md, "delegate de SceneEffect evaluado una vez").
    // Inline Components plus a count property re-evaluate the delegate binding,
    // and KWin recreates the SceneViews when the delegate changes.
    readonly property int desktopCount: KWinComponents.Workspace.desktops.length
    delegate: desktopCount < 3 ? placeholderComponent : cubeComponent

    Component {
        id: placeholderComponent
        PlaceholderView {}
    }

    Component {
        id: cubeComponent
        ScreenView {}
    }
    // Screen edges are stored as a comma-separated string ("1,7") so the generic
    // KCM (QLineEdit) can edit them; an older IntList value is also accepted.
    function toEdges(value) {
        if (value === undefined || value === null || value === "")
            return [];
        if (typeof value === "string")
            return value.split(",").map(part => parseInt(part.trim(), 10)).filter(n => !isNaN(n) && n >= 1 && n <= 8);
        return Array.from(value).map(n => Number(n)).filter(n => !isNaN(n) && n >= 1 && n <= 8);
    }

    Instantiator {
        model: effect.toEdges(effect.configuration.BorderActivate)
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Pointer
            edge: modelData
            onActivated: toggle()
        }
    }

    Instantiator {
        model: effect.toEdges(effect.configuration.TouchBorderActivate)
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: toggle()
        }
    }

    KWinComponents.ShortcutHandler {
        name: "Kube Effect"
        text: i18nd("kwin_effect_kube_effect", "Toggle Kube Effect")
        sequence: "Meta+K"
        onActivated: toggle()
    }

    Timer {
        id: deactivateTimer
        interval: effect.animationDuration
        onTriggered: effect.visible = false
    }

    function toggle() {
        if (activated) {
            deactivate();
        } else {
            activate();
        }
    }

    // Empty means "unknown": the delegate then draws on every screen instead of
    // on none. String(undefined) would be the literal "undefined", which matches
    // no screen, so only a real non-empty string name is accepted.
    function screenName(screen) {
        if (screen === null || screen === undefined) {
            return "";
        }
        const name = screen.name;
        return typeof name === "string" && name.length > 0 ? name : "";
    }

    // Name of the output under the pointer (or of the active window's output
    // when Workspace.screenAt is unavailable).
    function screenUnderCursorName() {
        try {
            return screenName(KWinComponents.Workspace.screenAt(KWinComponents.Workspace.cursorPos));
        } catch (error) {
            // Older KWin: no screenAt(). Fall through to activeScreen.
        }
        return screenName(KWinComponents.Workspace.activeScreen);
    }

    function activate() {
        if (activated) {
            return;
        }
        // Pressing the shortcut during the closing animation must reopen the
        // cube, not strand it: the old guard returned while deactivateTimer ran
        // and the timer then hid a freshly "activated" effect forever. Stop the
        // pending hide and continue with the activation.
        if (deactivateTimer.running) {
            deactivateTimer.stop();
        }
        cursorScreenName = screenUnderCursorName();
        visible = true;
        activated = true;
    }

    function deactivate() {
        if (!activated) {
            return;
        }
        activated = false;
        deactivateTimer.start();
    }
}
