/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kube_effect_install.h"

#include <KLocalizedString>
#include <QDir>
#include <QFileInfo>
#include <QStringList>

namespace KubeInstall
{
  bool isSystemInstall(const QString &pluginFile)
  {
    if (pluginFile.isEmpty())
    {
      return false;
    }

    // cleanPath only normalizes text: symlinks are deliberately NOT resolved,
    // because distro packaging often links the .so and the link itself lives in
    // the system path that Qt actually scanned.
    const QString path = QDir::cleanPath(pluginFile);
    if (!path.startsWith(QLatin1Char('/')))
    {
      return false;
    }

    // "/usr" covers both /usr and /usr/local.
    return path == QStringLiteral("/usr") || path.startsWith(QStringLiteral("/usr/"));
  }

  QString shellQuote(const QString &word)
  {
    // POSIX: inside single quotes nothing expands or interprets; a literal
    // quote is produced by closing the string, emitting an escaped quote and
    // reopening it: '\''. Wrapping the whole word means a path with spaces,
    // quotes or $(...) stays a single inert argument (ADR-022).
    QString quoted = word;
    quoted.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + quoted + QLatin1Char('\'');
  }

  QString commandsBlock(const QString &sourceRoot)
  {
    // Only an absolute stamp path is honoured: a relative one would cd
    // somewhere unpredictable, and the field is data, not trust (ADR-022).
    const bool sourceExists = QDir::isAbsolutePath(sourceRoot) && QFileInfo(sourceRoot).isDir();
    // A store install keeps the sources under contents/native, so build.sh sits
    // directly in the stamp source; a build from the repo points at the repo
    // root (build.sh lives in native/, one level down). Both are supported by
    // build.sh itself, which derives everything from its own location.
    const bool packagedCopy =
        sourceExists && QFileInfo(sourceRoot + QStringLiteral("/build.sh")).isFile();
    const QString directory =
        sourceExists ? sourceRoot
                     : QStringLiteral("~/.local/share/kwin/effects/kube-effect/contents/native");

    // The real path is quoted (it came from the stamp: shellQuote above). The
    // placeholder keeps its tilde UNQUOTED, because '~' inside single quotes
    // never expands and the example would not work after pasting.
    const QString target = sourceExists ? shellQuote(directory) : directory;
    QString firstLine = QStringLiteral("cd %1").arg(target);
    if (!sourceExists)
    {
      firstLine += QStringLiteral("  # ") + i18n("ruta no encontrada, ajústala");
    }

    // Comments start in the same column so the block reads as a table when
    // pasted into the shell (a long cd line simply pushes its own comment).
    const auto commandLine = [](const QString &command, const QString &comment)
    { return command.leftJustified(28, QLatin1Char(' ')) + QStringLiteral("# ") + comment; };

    if (packagedCopy)
    {
      return QStringList{
                 firstLine,
                 commandLine(QStringLiteral("./build.sh"),
                             i18n("instala para tu usuario (sin root)")),
                 commandLine(QStringLiteral("./build.sh --system"),
                             i18n("aparece en Preferencias (pide contraseña)")),
                 commandLine(QStringLiteral("./build.sh --clean"),
                             i18n("borra los árboles de build")),
             }
                 .join(QLatin1Char('\n')) +
             QLatin1Char('\n');
    }

    return QStringList{
               firstLine,
               commandLine(QStringLiteral("make native"),
                           i18n("instala para tu usuario (sin root)")),
               commandLine(QStringLiteral("make native-install"),
                           i18n("pide la contraseña solo al instalar")),
               commandLine(QStringLiteral("make native-status"),
                           i18n("comprueba versión compilada vs instalada")),
           }
               .join(QLatin1Char('\n')) +
           QLatin1Char('\n');
  }
} // namespace KubeInstall
