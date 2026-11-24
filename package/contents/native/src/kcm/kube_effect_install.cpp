/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_install.h"

#include <QDir>

namespace KubeInstall
{
bool isSystemInstall(const QString &pluginFile)
{
    if (pluginFile.isEmpty()) {
        return false;
    }

    // cleanPath only normalizes text: symlinks are deliberately NOT resolved,
    // because distro packaging often links the .so and the link itself lives in
    // the system path that Qt actually scanned.
    const QString path = QDir::cleanPath(pluginFile);
    if (!path.startsWith(QLatin1Char('/'))) {
        return false;
    }

    // "/usr" covers both /usr and /usr/local.
    return path == QStringLiteral("/usr") || path.startsWith(QStringLiteral("/usr/"));
}
} // namespace KubeInstall
