/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KCModule>

#include <QString>

class QLabel;
class QProcess;
class QProgressBar;
class QPushButton;

/**
 * Independent "Kube Effect Plus" KCM (ADR-011 / ADR-018).
 *
 * It never duplicates the effect settings: those live in the QML generic KCM
 * (config.ui). This module only adds what QML cannot do: the compiled versions,
 * the native stamp check, the feature dependency list, reconfigureEffect() and
 * a real compositor restart (the only thing that drops KWin's in-memory QML
 * cache, bug #514131).
 * Every piece degrades to an informational label when its data is missing. The
 * restart is the single exception to "no dialogs": it closes every window, so
 * it asks first, and it refuses to run inside the nested test compositor.
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
    void startReload(const QString &program);
    void finishReload(bool succeeded, int exitCode, const QString &program, const QString &errorText);

    QLabel *m_stampLabel = nullptr;
    QLabel *m_actionStatusLabel = nullptr;
    QLabel *m_reloadStatusLabel = nullptr;
    QPushButton *m_reloadButton = nullptr;
    QProgressBar *m_reloadSpinner = nullptr;
    QProcess *m_reloadProcess = nullptr;
};
