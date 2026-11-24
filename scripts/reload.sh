#!/usr/bin/env bash
# kube-effect — recargar el efecto en la sesión REAL.
#
#   scripts/reload.sh
#
# Instala el paquete y REINICIA KWin para que recompile el QML (KWin cachea el
# QML compilado; unloadEffect+loadEffect NO recarga — bug #514131).
#
# ADVERTENCIA: reinicia KWin (las ventanas parpadean y se reabren, ~10 s). Úsalo
# cuando quieras ver tus CAMBIOS DE CÓDIGO en el escritorio real.
#
# Para DESARROLLO: usa el anidado (scripts/kwin-nested-test.sh), que no toca tu
# sesión. Para cambios SOLO de configuración (kwinrc), basta el botón Apply del
# KCM (llama a reconfigureEffect y no reinicia nada).

set -eu
cd "$(dirname "$0")/.."

echo "Instalando kube-effect desde package/ ..."
kpackagetool6 --type KWin/Effect --upgrade package/

echo "Reiniciando KWin para recargar el QML ..."
systemctl --user restart plasma-kwin_wayland.service

echo "Listo. El efecto ya corre el código nuevo."
