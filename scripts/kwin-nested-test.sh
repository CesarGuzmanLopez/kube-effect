#!/usr/bin/env bash
# kube-effect — KWin ANIDADO para probar el cubo A MANO.
#
#   ./scripts/kwin-nested-test.sh
#
# Abre un escritorio KWin VIRTUAL (ventana 1600x900 sobre tu sesión) con 3
# escritorios virtuales (= 3 caras del cubo) y unos programas de ejemplo.
#
# NO saca capturas de pantalla. El usuario hace las pruebas DIRECTAMENTE en esa
# ventana anidada: le da foco y pulsa Meta+K para abrir/cerrar el cubo.
#
# Aislamiento (nunca toca tu sesión):
#   * bus D-Bus propio (dbus-run-session)
#   * XDG_CONFIG_HOME temporal (copia de tu kwinrc como base)
#   * socket Wayland propio (kube-effect-nested-0)
# Para parar: kill del pid que se imprime al final.

set -u
cd "$(dirname "$0")/.." || exit 1

SOCK="kube-effect-nested-0"
CFG="/tmp/kube-effect-test-config"
ADDR="/tmp/kube-effect-nested.addr"
PIDFILE="/tmp/kube-effect-nested.pid"
RUN="$(id -u)"
SAY() { echo "[$(date +%H:%M:%S)] $*"; }

# 0. Cerrar un anidado previo.
if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    sleep 1
fi
rm -f "/run/user/$RUN/$SOCK" "/run/user/$RUN/$SOCK.lock" "$ADDR"

# 1. Instalar el efecto (para que el anidado lo encuentre).
if kpackagetool6 --type KWin/Effect --upgrade "$(pwd)/package/" >/dev/null 2>&1; then
    SAY "efecto instalado/actualizado"
elif kpackagetool6 --type KWin/Effect --install "$(pwd)/package/" >/dev/null 2>&1; then
    SAY "efecto instalado"
else
    SAY "aviso: no pude instalar el efecto; usa 'make install'"
fi

# 2. Config aislada: copia tu kwinrc y ajusta desktops + efecto.
rm -rf "$CFG"
mkdir -p "$CFG"
[ -f "$HOME/.config/kwinrc" ] && cp "$HOME/.config/kwinrc" "$CFG/kwinrc"

# 3 escritorios virtuales = 3 caras.
kwriteconfig6 --file "$CFG/kwinrc" --group Desktops --key Number 3
kwriteconfig6 --file "$CFG/kwinrc" --group Desktops --key Rows 1
# Solo kube-effect activo en el anidado: cualquier otro efecto del host se apaga
# (menos efectos cargados = menos GPU/CPU y menos ruido en las pruebas).
# KUBE_NESTED_KEEP_EFFECTS="blur,screenshot" conserva esos (p.ej. screenshot hace
# falta para WindowThumbnail/wallpapers reales).
KEEP_EFFECTS="${KUBE_NESTED_KEEP_EFFECTS:-}"
awk -v keep="$KEEP_EFFECTS" '
    /^\[/ { inGroup = ($0 == "[Plugins]") }
    inGroup && /^[A-Za-z0-9_.-]+Enabled=/ {
        split($0, kv, "=")
        id = kv[1]; sub(/Enabled$/, "", id)
        split(keep, keepList, ",")
        wanted = 0
        for (i in keepList) if (keepList[i] == id) wanted = 1
        print id "Enabled=" (wanted ? "true" : "false")
        next
    }
    { print }
' "$CFG/kwinrc" >"$CFG/kwinrc.tmp" && mv "$CFG/kwinrc.tmp" "$CFG/kwinrc"
kwriteconfig6 --file "$CFG/kwinrc" --group Plugins --key kube-effectEnabled true
# Fondo del cubo por defecto del anidado: SkyBox (panorámica incluida).
kwriteconfig6 --file "$CFG/kwinrc" --group Effect-kube-effect --key Background 1
kwriteconfig6 --file "$CFG/kwinrc" --group Effect-kube-effect --key CubeFaceDisplacement 100

# 3. Arrancar el KWin anidado en una ventana 1600x900, bus privado.
SAY "arrancando KWin anidado (ventana 1600x900)..."
XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" setsid \
    dbus-run-session -- \
    sh -c 'echo $DBUS_SESSION_BUS_ADDRESS > '"$ADDR"'; exec kwin_wayland --socket '"$SOCK"' --xwayland :2 --no-lockscreen --width 1600 --height 900' \
    >/tmp/kube-effect-nested.log 2>&1 </dev/null &
NESTED_PID=$!
echo "$NESTED_PID" >"$PIDFILE"

for _ in $(seq 1 30); do
    [ -s "$ADDR" ] && break
    sleep 1
done
NBA=$(cat "$ADDR" 2>/dev/null || true)
if [ -z "$NBA" ]; then
    SAY "error: el bus del anidado no arrancó; mira /tmp/kube-effect-nested.log"
    exit 1
fi
SAY "nested pid=$NESTED_PID bus=$NBA socket=$SOCK"

# 4. plasmashell dentro del anidado (wallpaper real del escritorio).
DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
    plasmashell >/tmp/kube-effect-nested-plasma.log 2>&1 </dev/null &
sleep 6

# 5. Programas de ejemplo (en el escritorio actual). Reparte ventanas entre
#    escritorios a tu gusto o cambia esta lista.
for app in konsole dolphin kate; do
    if command -v "$app" >/dev/null 2>&1; then
        DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
            "$app" >/dev/null 2>&1 </dev/null &
        SAY "lanzado $app"
        sleep 2
    fi
done

cat <<EOF

======================================================================
 KWin anidado LISTO. 3 escritorios virtuales = 3 caras del cubo.

 >>> LAS PRUEBAS LAS HACES TÚ, DIRECTAMENTE EN LA VENTANA ANIDADA. <<<
     (Este script NO toma capturas de pantalla.)

   1. Haz clic en la ventana del anidado para darle foco.
   2. Pulsa Meta+K para abrir / cerrar el cubo.
   3. Configura el efecto DENTRO del anidado (System Settings), o edita
      $CFG/kwinrc  sección [Effect-kube-effect].
   4. Rota los escritorios/fondos y comprueba lo que quieras.

   Parar el anidado:   kill $NESTED_PID
   (o: kill \$(cat $PIDFILE))
======================================================================
EOF
