/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import org.kde.kwin as KWinComponents

// The flat grab of one desktop: one WindowThumbnail per window row, all
// composited into a single texture (the face's baseColorMap). With
// WindowLayering (ADR-028) the ids present in `layeredIds` are released
// (wId = "") so the compound keeps a transparent HOLE exactly where each
// layered window was; the quad behind that hole lives in WindowLayers.qml
// and is fed from the same window model, never from this grab.
Item {
  id: desktopView

  required property QtObject desktop
  // Screen identity passed down ScreenView -> Cube -> CubeFace (ADR-022).
  // Resolving targetScreen through dynamic scope worked but was fragile: any
  // change in the object hierarchy silently breaks it, and qmllint cannot
  // see it at all.
  required property string screenName
  required property rect screenGeometry
  // Object id -> true of the windows that won a layer (WindowLayers'
  // data-derived snapshot; the empty default is the flag-off/pixel-parity
  // case: every window keeps its id in the grab).
  property var layeredIds: ({})

  Repeater {
    id: thumbRepeater

    model: KWinComponents.WindowFilterModel {
      activity: KWinComponents.Workspace.currentActivity
      desktop: desktopView.desktop
      screenName: desktopView.screenName
      windowModel: KWinComponents.WindowModel {}
    }

    KWinComponents.WindowThumbnail {
      // The row's window kept readable for the layers gate (a property
      // declared on the instance, harmless outside the tests).
      readonly property QtObject srcWindow: model.window
      // A null model row (transient during unload) must not throw.
      // Window::internalId is a QUuid in KWin 6 (verified in the
      // installed headers: /usr/include/kwin/effect/effectwindow.h
      // "QUuid internalId() const" and window.h "qmlproperty uuid"),
      // so the release value is an EMPTY STRING (null QUuid), which
      // detaches the thumbnail and frees its capture; an int 0 is not a
      // valid null wId here. x/y/z/visible guard the same null row.
      // Layered ids are released too — that is the hole of model H
      // (ADR-028): the quad behind it carries the capture instead.
      wId: {
        const win = model.window;
        if (win === null || win === undefined) {
          return "";
        }
        const id = win.internalId;
        if (desktopView.layeredIds[id] === true) {
          return "";
        }
        return id;
      }
      x: model.window !== null && model.window !== undefined ? model.window.x - desktopView.screenGeometry.x : 0
      y: model.window !== null && model.window !== undefined ? model.window.y - desktopView.screenGeometry.y : 0
      z: model.window !== null && model.window !== undefined ? model.window.stackingOrder : 0
      visible: model.window !== null && model.window !== undefined ? !model.window.minimized : false
    }
  }

  // --- gate accessors (scripts/check-layers.py reads the live tree) --------
  readonly property int thumbnailCount: thumbRepeater.count
  // Repeater (2D) exposes itemAt, not objectAt (the Repeater3D API the
  // window layers use for their quads).
  function thumbnailAt(i) {
    return thumbRepeater.itemAt(i);
  }
}
