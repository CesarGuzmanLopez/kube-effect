#!/usr/bin/env bash
# kube-effect — KWin ANIDADO para probar el cubo A MANO.
#
#   ./scripts/kwin-nested-test.sh              # compila native/ y abre el KCM
#   ./scripts/kwin-nested-test.sh --no-native  # experiencia SIN compilar
#   ./scripts/kwin-nested-test.sh --help
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
# se aconseja cerrar el anterior proceso para que no se consuma muchos recursos
#
# Lado nativo (ADR-015): si existe native/CMakeLists.txt se compila SIEMPRE
# antes de arrancar (make native) y se aborta si falla: nunca se prueba contra
# un binario viejo. Si el KCM nativo está instalado en el prefijo privado, se
# abre kcmshell6 kcm_kube_effect_plus DENTRO del anidado (su kwinrc es el del test).
# Sin lado nativo no se lanza nada: el efecto QML no lo necesita.
# --no-native reproduce esa experiencia (nada de make native, prefix.sh ni
# kcmshell6): sirve para ver la diferencia con el lado compilado.
set -u
cd "$(dirname "$0")/.." || exit 1

usage() {
    cat <<'EOF'
uso: scripts/kwin-nested-test.sh [--no-native] [--help]

  (sin opciones)  compila native/ antes de arrancar (aborta si falla) y abre
                  el KCM nativo dentro del anidado (ADR-015)
  --no-native     modo SIN COMPILAR: no compila native/, no sourcea prefix.sh
                  ni lanza kcmshell6. El efecto QML sigue completo.
  -h, --help      muestra esta ayuda

Variable de entorno:
  KUBE_NESTED_KEEP_EFFECTS="blur,screenshot"
                  conserva esos efectos del host en el anidado (por defecto se
                  apagan todos menos kube-effect)
EOF
}

NATIVE=1
for argument in "$@"; do
    case "$argument" in
    --no-native)
        NATIVE=0
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "error: argumento desconocido: $argument" >&2
        usage >&2
        exit 2
        ;;
    esac
done

echo "Deten el anterior escritorio anidado"
SOCK="kube-effect-nested-0"
# Second marker for the KCM guard (native/src/kcm/kube_effect_reload.cpp): the
# socket name already carries it, and this flag makes it explicit for any child
# that only inspects the environment.
export KUBE_NESTED=1
CFG="/tmp/kube-effect-test-config"
ADDR="/tmp/kube-effect-nested.addr"
PIDFILE="/tmp/kube-effect-nested.pid"
RUN="$(id -u)"
SAY() { echo "[$(date +%H:%M:%S)] $*"; }
KUBE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kube-effect"

# A pid found in /tmp is only our nested KWin when it is numeric AND its comm is
# kwin_wayland: a stale pidfile could otherwise name (and kill) any process.
is_nested_pid() {
    case "$1" in
    '' | *[!0-9]*) return 1 ;;
    esac
    ps -o comm= -p "$1" 2>/dev/null | grep -q 'kwin_wayland'
}

# Qt plugin dir of the private prefix (ECM writes it into prefix.sh). It is
# resolved by sourcing prefix.sh in a subshell (ECM expands variables unguarded,
# so relax 'set -u' there) instead of parsing the assignment with sed; the
# first absolute entry of QT_PLUGIN_PATH wins. The .so is checked by the caller.
kcm_plugin_dir() {
    local prefix_sh="$KUBE_DATA/prefix.sh"
    [ -f "$prefix_sh" ] || return 1
    local plugindir
    plugindir=$(
        set +u
        . "$prefix_sh" >/dev/null 2>&1
        printf '%s\n' "${QT_PLUGIN_PATH:-}" | tr ':' '\n' | grep -m1 '^/'
    )
    [ -n "$plugindir" ] || return 1
    printf '%s\n' "$plugindir"
}

# 0. Cerrar un anidado previo (solo si el pidfile apunta a un kwin_wayland).
if [ -f "$PIDFILE" ]; then
    PREVIOUS_PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if is_nested_pid "$PREVIOUS_PID"; then
        kill "$PREVIOUS_PID" 2>/dev/null || true
        sleep 1
    else
        SAY "aviso: $PIDFILE no apunta a un kwin_wayland vivo; no mato nada"
    fi
fi
rm -f "/run/user/$RUN/$SOCK" "/run/user/$RUN/$SOCK.lock" "$ADDR"

# 1. Lado nativo opcional: compilar ANTES de arrancar (ADR-015). Si falla se
#    aborta: nunca se prueba con un .so viejo. Con --no-native no se compila.
if [ "$NATIVE" -eq 0 ]; then
    SAY "modo sin compilar: KCM nativo desactivado (--no-native)"
elif [ -f "native/CMakeLists.txt" ]; then
    SAY "compilando native/ (KCM opcional)..."
    if ! make native >"/tmp/kube-effect-native-build.log" 2>&1; then
        SAY "error: make native falló; no arranco el anidado"
        tail -n 20 "/tmp/kube-effect-native-build.log"
        exit 1
    fi
    SAY "native/: compilado e instalado (ver $KUBE_DATA/native-stamp.json)"
else
    SAY "native/: sin fuentes; sigo solo con el efecto QML"
fi

# 2. Instalar el efecto (para que el anidado lo encuentre).
if kpackagetool6 --type KWin/Effect --upgrade "$(pwd)/package/" >/dev/null 2>&1; then
    SAY "efecto instalado/actualizado"
elif kpackagetool6 --type KWin/Effect --install "$(pwd)/package/" >/dev/null 2>&1; then
    SAY "efecto instalado"
else
    SAY "aviso: no pude instalar el efecto; usa 'make install'"
fi

# 3. Config aislada: copia tu kwinrc y ajusta desktops + efecto.
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

# 4. Arrancar el KWin anidado en una ventana 1600x900, bus privado.
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

# 5. plasmashell dentro del anidado (wallpaper real del escritorio).
DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
    plasmashell >/tmp/kube-effect-nested-plasma.log 2>&1 </dev/null &
sleep 6

# 6. Programas de ejemplo (en el escritorio actual). Reparte ventanas entre
#    escritorios a tu gusto o cambia esta lista.
for app in konsole dolphin kate; do
    if command -v "$app" >/dev/null 2>&1; then
        DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
            "$app" >/dev/null 2>&1 </dev/null &
        SAY "lanzado $app"
        sleep 2
    fi
done

# 7. KCM nativo opcional DENTRO del anidado (ADR-015): mismo bus D-Bus y mismo
#    XDG_CONFIG_HOME, así que escribe en el kwinrc del test, no en el del host.
#    prefix.sh solo exporta QT_PLUGIN_PATH/XDG_DATA_DIRS al proceso, por eso se
#    carga en un subshell.
if [ "$NATIVE" -eq 0 ]; then
    KCM_STATUS="desactivado (--no-native); el efecto QML sigue completo"
    SAY "modo sin compilar: no abro el KCM nativo (sería el del host, no el del test)"
else
    KCM_PLUGIN_DIR=$(kcm_plugin_dir || true)
    KCM_SO="$KCM_PLUGIN_DIR/plasma/kcms/systemsettings/kcm_kube_effect_plus.so"
    if [ -z "$KCM_PLUGIN_DIR" ]; then
        KCM_STATUS="sin $KUBE_DATA/prefix.sh; el efecto QML sigue completo"
        SAY "aviso: no encuentro $KUBE_DATA/prefix.sh; ejecuta make native para el KCM"
    elif [ ! -f "$KCM_SO" ]; then
        KCM_STATUS="compilado pero no instalado ($KCM_SO); el efecto QML sigue completo"
        SAY "aviso: falta $KCM_SO; no lanzo kcmshell6 (make native lo instala)"
    else
        KCM_STATUS="abierto dentro del anidado (log: /tmp/kube-effect-nested-kcm.log)"
        SAY "lanzando kcmshell6 kcm_kube_effect_plus dentro del anidado"
        (
            # ECM's prefix.sh expands variables unguarded; the harness runs with
            # 'set -u', so relax it while sourcing.
            set +u
            # shellcheck source=/dev/null
            . "$KUBE_DATA/prefix.sh"
            set -u
            DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
                kcmshell6 kcm_kube_effect_plus >/tmp/kube-effect-nested-kcm.log 2>&1 </dev/null &
        )
        # System Settings only finds KCMs through the Qt plugin paths: a private
        # install shows up there only with prefix.sh in the environment (or a
        # system-wide install). Say it, so nobody hunts for a missing entry.
        SAY "nota: en Preferencias del sistema solo aparece tras 'make native-install' (pide contraseña al instalar) o abriendo Preferencias con prefix.sh"
    fi
fi

if [ "$NATIVE" -eq 1 ]; then
    NATIVE_LABEL="nativo ACTIVADO (compilado antes de arrancar)"
else
    NATIVE_LABEL="--no-native = experiencia SIN compilar"
fi

# The hint is informational only: do not advertise a kill for a pid that is no
# longer a nested kwin_wayland (or never was one).
if is_nested_pid "$NESTED_PID"; then
    STOP_HINT="kill $NESTED_PID"
else
    STOP_HINT="el anidado ya no está vivo (no hay PID que matar)"
fi

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

   KCM nativo 'Kube Effect Plus' (escribe en $CFG/kwinrc): $KCM_STATUS

   Engranaje del efecto = menú QML (config.ui), exista o no el nativo.
   'Kube Effect Plus' = KCM nativo, solo en Personalización.
   Modo de este arnés: $NATIVE_LABEL

   Parar el anidado:   $STOP_HINT
======================================================================
EOF
