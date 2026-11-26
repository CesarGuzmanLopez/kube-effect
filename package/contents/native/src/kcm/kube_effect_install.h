/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/**
 * Pure helpers for the install-location notice (ADR-011/ADR-012) and the
 * copy/paste command block of the Plus page (ADR-022).
 *
 * A KCM is discovered by scanning the Qt plugin paths, so the same .so behaves
 * differently depending on where it landed: installed under /usr it shows up in
 * System Settings on its own, installed in a private prefix it only exists for
 * the process that sourced prefix.sh. The page says so instead of leaving the
 * user wondering why the module is missing from Preferencias.
 */
namespace KubeInstall
{
/**
 * True when \a pluginFile lives under a system prefix (/usr, which already
 * includes /usr/local). Those are readable without QT_PLUGIN_PATH tweaks, so
 * System Settings finds the module by itself.
 *
 * An empty path (built-in/unknown metadata) is NOT a system install: the page
 * keeps the hint visible rather than silently pretending everything is fine.
 */
bool isSystemInstall(const QString &pluginFile);

/**
 * POSIX single-quote escaping: inside '' nothing is expanded or interpreted,
 * and a literal quote closes the string, emits an escaped quote and reopens it
 * ('\''). The stamp's "source" is data the KCM must paste into a shell command
 * without letting it carry commands (ADR-022). An empty word becomes '' ,
 * which is a valid empty argument.
 */
QString shellQuote(const QString &word);

/**
 * Command block for the "Comandos" box: copy/paste ready, real project path
 * when the stamp carries an ABSOLUTE "source" (written by native/build.sh).
 * An old stamp without the field just gets the placeholder plus a note, never
 * an empty cd. The real path goes through shellQuote; the placeholder keeps
 * the leading ~ unquoted on purpose, because a quoted tilde never expands.
 */
QString commandsBlock(const QString &sourceRoot);
} // namespace KubeInstall
