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

    // stored as a property to keep the component alive and cleanup afterwards
    property var mainDelegate: KWinComponents.Workspace.desktops.length < 3 ? Qt.createComponent("PlaceholderView.qml") : Qt.createComponent("ScreenView.qml")
    delegate: mainDelegate
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

    function activate() {
        if (activated || deactivateTimer.running) {
            return;
        }
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
