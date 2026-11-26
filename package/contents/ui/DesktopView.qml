/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import org.kde.kwin as KWinComponents

Item {
    id: desktopView

    required property QtObject desktop
    // Screen identity passed down ScreenView -> Cube -> CubeFace (ADR-022).
    // Resolving targetScreen through dynamic scope worked but was fragile: any
    // change in the object hierarchy silently breaks it, and qmllint cannot
    // see it at all.
    required property string screenName
    required property rect screenGeometry

    Repeater {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            desktop: desktopView.desktop
            screenName: desktopView.screenName
            windowModel: KWinComponents.WindowModel {}
        }

        KWinComponents.WindowThumbnail {
            // A null model row (transient during unload) must not throw.
            // Window::internalId is a QUuid in KWin 6 (verified in the
            // installed headers: /usr/include/kwin/effect/effectwindow.h
            // "QUuid internalId() const" and window.h "qmlproperty uuid"),
            // so the release value is an EMPTY STRING (null QUuid), which
            // detaches the thumbnail and frees its capture; an int 0 is not a
            // valid null wId here. x/y/z/visible guard the same null row.
            wId: model.window !== null && model.window !== undefined ? model.window.internalId : ""
            x: model.window !== null && model.window !== undefined ? model.window.x - desktopView.screenGeometry.x : 0
            y: model.window !== null && model.window !== undefined ? model.window.y - desktopView.screenGeometry.y : 0
            z: model.window !== null && model.window !== undefined ? model.window.stackingOrder : 0
            visible: model.window !== null && model.window !== undefined ? !model.window.minimized : false
        }
    }
}
