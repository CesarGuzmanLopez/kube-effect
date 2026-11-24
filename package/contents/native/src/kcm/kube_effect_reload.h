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
 * throwaway nested session? which unit do we restart? how do we show a failure
 * in three lines? — are unit tested without starting any process.
 */
namespace KubeReload
{
/**
 * True when the KCM runs inside the nested test compositor
 * (scripts/kwin-nested-test.sh uses the Wayland socket "kube-effect-nested-0").
 * Restarting the session compositor from there would be pointless and could hit
 * the real session if the detection ever failed, so the button refuses.
 */
bool isNestedSession(const QProcessEnvironment &environment);

/**
 * systemd unit that really drops the compiled QML cache: a new kwin_wayland
 * process. It exists on Plasma 6 (plasma-workspace) and is the one running the
 * session; kwin_wayland --replace is not used (it fights systemd).
 */
QString serviceUnit();

/**
 * systemctl argv for a full restart, i.e. {"systemctl", "--user", "restart",
 * serviceUnit()}. Not typed in the shell: explicit argv only.
 */
QStringList restartCommand();

/**
 * Second, independent guard: is \a pid the session compositor \a ancestorPid or
 * one of its descendants (maxDepth levels up)? On this distro systemd's MainPID
 * is the kwin_wayland_wr wrapper and org.kde.KWin belongs to its child
 * kwin_wayland, so a plain equality check would always fail.
 *
 * Reads /proc/<pid>/stat; unknown processes return false.
 */
bool isInProcessTree(uint pid, uint ancestorPid, int maxDepth = 3);

/**
 * Keep at most maxLines non-empty lines of a command's stderr, so the label
 * stays readable (systemctl prints a lot of context). When lines are dropped
 * the result carries one extra "…" line as a marker.
 */
QString summarizeError(const QString &stderrText, int maxLines = 3);

/**
 * Actionable message for a failed restart, without jargon.
 * When \a program is empty, systemctl was not found and the text says so.
 */
QString failureHint(const QString &program, int exitCode, const QString &stderrText);
} // namespace KubeReload
