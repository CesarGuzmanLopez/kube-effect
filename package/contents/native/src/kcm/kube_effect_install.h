/*
    SPDX-FileCopyrightText: 2026 Cesar Guzman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/**
 * Pure helpers for the install-location notice (ADR-011/ADR-012).
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
} // namespace KubeInstall
