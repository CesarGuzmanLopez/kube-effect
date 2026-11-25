/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_reload.h"

#include <QStringList>

namespace KubeReload
{
namespace
{
// The nested harness points WAYLAND_DISPLAY at its own socket; KUBE_NESTED is
// the explicit opt-in flag for wrappers that launch the KCM in the same way.
constexpr auto kNestedSocketMarker = "kube-effect-nested";
constexpr auto kNestedFlag = "KUBE_NESTED";
} // namespace

bool isNestedSession(const QProcessEnvironment &environment)
{
    if (environment.value(QString::fromLatin1(kNestedFlag)) == QLatin1String("1")) {
        return true;
    }
    return environment.value(QStringLiteral("WAYLAND_DISPLAY")).contains(QString::fromLatin1(kNestedSocketMarker));
}

QString serviceUnit()
{
    return QStringLiteral("plasma-kwin_wayland.service");
}

QStringList restartCommand()
{
    return {
        QStringLiteral("systemctl"),
        QStringLiteral("--user"),
        QStringLiteral("restart"),
        serviceUnit(),
    };
}

} // namespace KubeReload
