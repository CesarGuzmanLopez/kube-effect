/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_reload.h"

#include <KLocalizedString>

#include <QFile>
#include <QStringList>

namespace KubeReload
{
namespace
{
// The nested harness points WAYLAND_DISPLAY at its own socket; KUBE_NESTED is
// the explicit opt-in flag for wrappers that launch the KCM in the same way.
constexpr auto kNestedSocketMarker = "kube-effect-nested";
constexpr auto kNestedFlag = "KUBE_NESTED";

// Parent PID from /proc/<pid>/stat. The comm field may contain spaces and
// parentheses, so fields are counted after the LAST ')'.
uint parentPid(uint pid)
{
    if (pid == 0) {
        return 0;
    }
    QFile file(QStringLiteral("/proc/%1/stat").arg(pid));
    if (!file.open(QIODevice::ReadOnly)) {
        return 0;
    }
    const QString stat = QString::fromLatin1(file.readAll());
    const int commEnd = stat.lastIndexOf(QLatin1Char(')'));
    if (commEnd < 0) {
        return 0;
    }
    // After "comm)": state is field 3, so field 4 (ppid) is tokens[1].
    const QStringList tokens = stat.mid(commEnd + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (tokens.size() < 2) {
        return 0;
    }
    bool ok = false;
    const uint parsed = tokens.at(1).toUInt(&ok);
    return ok ? parsed : 0;
}
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

bool isInProcessTree(uint pid, uint ancestorPid, int maxDepth)
{
    if (pid == 0 || ancestorPid == 0) {
        return false;
    }
    uint current = pid;
    for (int depth = 0; depth <= maxDepth && current > 1; ++depth) {
        if (current == ancestorPid) {
            return true;
        }
        current = parentPid(current);
    }
    return false;
}

QString summarizeError(const QString &stderrText, int maxLines)
{
    if (stderrText.isEmpty() || maxLines <= 0) {
        return {};
    }

    QStringList lines;
    const QStringList rawLines = stderrText.split(QLatin1Char('\n'));
    for (const QString &rawLine : rawLines) {
        const QString line = rawLine.trimmed();
        if (!line.isEmpty()) {
            lines << line;
        }
    }

    // systemctl repeats the unit name first and the real cause last, so keep
    // the tail; the label is a hint, not a log.
    if (lines.size() > maxLines) {
        lines = lines.mid(lines.size() - maxLines);
        lines.prepend(QStringLiteral("…"));
    }
    return lines.join(QLatin1Char('\n'));
}

QString failureHint(const QString &program, int exitCode, const QString &stderrText)
{
    if (program.isEmpty()) {
        return i18n("No encuentro el comando systemctl en el sistema: no puedo reiniciar "
                    "el compositor desde aquí. Reinicia la sesión a mano.");
    }

    const QString detail = summarizeError(stderrText);
    if (detail.isEmpty()) {
        return i18n("No se pudo reiniciar el compositor (código %1). Reinicia la sesión a mano.", exitCode);
    }
    return i18n("No se pudo reiniciar el compositor (código %1):\n%2", exitCode, detail);
}
} // namespace KubeReload
