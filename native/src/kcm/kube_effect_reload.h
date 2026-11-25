/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QProcessEnvironment>
#include <QString>
#include <QStringList>

/**
 * Pure helpers for the "Reload compositor" button (ADR-011/ADR-015).
 *
 * They live in their own file so the decisions that matter — is this the
 * throwaway nested session? which command does the safe path show? — are unit
 * tested without starting any process. The button never runs the restart: on
 * Wayland it kills the whole session (2026-11-25).
 */
namespace KubeReload
{
/**
 * True when the KCM runs inside the nested test compositor
 * (scripts/kwin-nested-test.sh uses the Wayland socket "kube-effect-nested-0").
 * The button refuses to offer anything there: that compositor belongs to the
 * script.
 */
bool isNestedSession(const QProcessEnvironment &environment);

/**
 * systemd unit that, when restarted by hand from a TTY, drops the compiled QML
 * cache: a new kwin_wayland process. It exists on Plasma 6 (plasma-workspace)
 * and is the one running the session; kwin_wayland --replace is not used (it
 * fights systemd). Restarting it from inside the session kills every Wayland
 * client, so the KCM only shows it.
 */
QString serviceUnit();

/**
 * systemctl argv for a full restart, i.e. {"systemctl", "--user", "restart",
 * serviceUnit()}. Shown to the user for a manual, TTY-only run: the KCM never
 * executes it.
 */
QStringList restartCommand();
} // namespace KubeReload
