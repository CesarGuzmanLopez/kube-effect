/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KCModule>

#include <QString>

class QLabel;
class QPushButton;

/**
 * Independent "Kube Effect Plus" KCM (ADR-011 / ADR-018).
 *
 * It never duplicates the effect settings: those live in the QML generic KCM
 * (config.ui). This module only adds what QML cannot do: the compiled versions,
 * the native stamp check, the feature dependency list and reconfigureEffect().
 * Every piece degrades to an informational label when its data is missing.
 * The "reload compositor" button NEVER restarts KWin itself: on Wayland that
 * restart kills every client and leaves the desktop dead (2026-11-25), so it
 * asks first and then performs a clean logout (org.kde.Shutdown.logout), which
 * is the only safe way to make KWin recompile the QML. It also offers the
 * manual command and refuses to run inside the nested test compositor.
 */
class KubeEffectKcm : public KCModule
{
    Q_OBJECT

public:
    KubeEffectKcm(QObject *parent, const KPluginMetaData &data);

private:
    QWidget *buildVersionLabel();
    QWidget *buildStampBox();
    QWidget *buildCommandsBox(const QString &sourceRoot, QWidget *parent);
    QWidget *buildFeatureBox();
    QWidget *buildActionBox();

    void reconfigureEffect();
    void reloadCompositor();
    void requestLogout();

    QLabel *m_stampLabel = nullptr;
    QLabel *m_actionStatusLabel = nullptr;
    QLabel *m_reloadStatusLabel = nullptr;
    QPushButton *m_reloadButton = nullptr;
};
