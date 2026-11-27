#!/usr/bin/env bash
# kube-effect — KWin ANIDADO para probar el cubo A MANO.
#
#   ./scripts/kwin-nested-test.sh              # compila native/ y abre el KCM
#   ./scripts/kwin-nested-test.sh --no-native  # experiencia SIN compilar
#   ./scripts/kwin-nested-test.sh --no-test-wallpaper # wallpaper del sistema
#   ./scripts/kwin-nested-test.sh --help
#
# Abre un escritorio KWin VIRTUAL (ventana 1600x900 sobre tu sesión) como si
# fuera una INSTALACIÓN LIMPIA: kwinrc de fábrica, 3 escritorios virtuales, una
# ventana por cara y plasmashell con el panel y un WALLPAPER DE PRUEBA
# direccional generado por el propio arnés (izquierda/derecha/arriba/abajo,
# flecha, esquina magenta y rejilla; --no-test-wallpaper vuelve al wallpaper
# del sistema). Como Plasma 6.8 no admite un wallpaper por escritorio virtual
# (medido 2026-11-27), cada escritorio lleva además una ventana maximizada
# E1/E2/E3 de color distinto. Los plasmoids descargados no se ven
# (XDG_DATA_HOME temporal), así que sus errores no ensucian la prueba.
#
# Dato para la prueba: dentro del anidado Meta+K NO llega (el KWin del host se
# lo queda como atajo global). El arnés registra un atajo propio, por defecto
# Meta+Shift+K (KUBE_NESTED_SHORTCUT=... para cambiarlo). Alternativa: el borde
# superior con el puntero capturado (Ctrl derecho captura/suelta).
#
# LOGS EN VIVO: al terminar de arrancar, el script se queda siguiendo lo que
# escriben kwin_wayland y, si se pidieron, plasmashell y el KCM del anidado.
# Ctrl+C para TODO: deja de seguir y para el anidado entero.
# --no-follow vuelve al comportamiento viejo (imprime el resumen y sale).
#
# NO saca capturas de pantalla. El usuario hace las pruebas DIRECTAMENTE en esa
# ventana anidada: le da foco y pulsa Meta+K para abrir/cerrar el cubo.
#
# Aislamiento (nunca toca tu sesión):
#   * bus D-Bus propio (dbus-run-session)
#   * XDG_CONFIG_HOME temporal con kwinrc DE FÁBRICA (KUBE_NESTED_CONFIG=clean):
#     como una instalación limpia de Plasma; solo se hereda [Effect-kube-effect].
#     El appletsrc también es de fábrica y se le apunta el wallpaper de prueba
#   * XDG_DATA_HOME temporal: no se ven los plasmoids descargados del host y el
#     paquete del efecto se instala ahí, no en ~/.local/share
#   * socket Wayland propio (kube-effect-nested-0)
#   * árbol privado por usuario en ${TMPDIR:-/tmp}/kube-effect-nested-$UID
#     (0700, dueño verificado, symlinks rechazados): config, data, logs, pid
#     y addr. Se reusa entre lanzamientos; solo se borra cuando el arnés
#     detiene su propio anidado (con --no-follow el anidado vive y persiste)
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
uso: scripts/kwin-nested-test.sh [--no-native] [--no-plasma] [--no-apps]
                      [--no-follow] [--no-test-wallpaper] [--help]

  Por defecto: como una INSTALACIÓN LIMPIA de Plasma — kwinrc de fábrica, 3
  escritorios virtuales, una ventana por cara y plasmashell con el panel y un
  WALLPAPER DE PRUEBA direccional generado al arrancar (IZQ/DER/ARR/ABA en los
  bordes, flecha centro→ARR, cuadrante magenta en la esquina superior-izquierda
  y rejilla cada 100 px) más una ventana maximizada E1/E2/E3 por escritorio.
  Sirve para ver de un vistazo rotaciones y espejos de caras y tapas (ADR-027),
  por dónde asoma el casco y que la cara k muestra el escritorio k (ADR-004).
  Los plasmoids DESCARGADOS no se cargan: el anidado usa XDG_DATA_HOME
  temporal, así que ni ~/.local/share/plasma/plasmoids (ni sus errores)
  aparece en la prueba; solo lo que trae el paquete del sistema.

  --no-native     modo SIN COMPILAR: no compila native/, no sourcea prefix.sh
                  ni lanza kcmshell6. El efecto QML sigue completo.
  --no-plasma     no lanza plasmashell: sin panel ni wallpaper de escritorio
                  (queda el casco del efecto y las ventanas; log más corto)
  --with-plasma   explícito (ya es el defecto)
  --no-apps       no lanza ventanas (las 3 caras salen vacías)
  --all           plasmashell + ventanas (es el defecto desde 2026-11-25)
  --no-follow     no sigue los logs: imprime el resumen y termina (el anidado
                  sigue vivo; se para con el 'kill' que imprime)
  --no-test-wallpaper  sin wallpaper de prueba: plasmashell conserva el
                  wallpaper por defecto de Plasma y no se lanzan las etiquetas
                  E1/E2/E3 (comportamiento anterior a 2026-11-27)
  -h, --help      muestra esta ayuda

Variables de entorno:
  KUBE_NESTED_CONFIG=clean|host
                  clean (defecto): config de FÁBRICA, como una instalación limpia
                  de Plasma (solo se hereda [Effect-kube-effect] del host)
                  host: copia el kwinrc completo del host y apaga los demás efectos
  KUBE_NESTED_KEEP_EFFECTS="blur,screenshot"
                  solo en modo host: conserva esos efectos
  KUBE_NESTED_SHORTCUT="Meta+Shift+K"
                  atajo con el que se abre el cubo DENTRO del anidado. Meta+K
                  no sirve: el KWin del host lo tiene como atajo global y se lo
                  queda antes de que la ventana anidada reciba la tecla
  KUBE_NESTED_APPS="konsole dolphin kate"
                  lista de ventanas a repartir entre los escritorios
  KUBE_NESTED_WALLPAPER=test|system
                  test (defecto): wallpaper direccional generado + ventanas
                  E1..EN (solo con plasmashell y KUBE_NESTED_CONFIG=clean)
                  system: equivale a --no-test-wallpaper
EOF
}

NATIVE=1
FOLLOW=1
PLASMA=1
APPS=1
DESKTOPS=3
NESTED_WIDTH=1600
NESTED_HEIGHT=900
# Empty until decided: --no-test-wallpaper forces 0; otherwise the
# KUBE_NESTED_WALLPAPER env (default test) picks.
TEST_WP=""
for argument in "$@"; do
  case "$argument" in
  --no-native)
    NATIVE=0
    ;;
  --no-plasma)
    PLASMA=0
    ;;
  --with-plasma)
    PLASMA=1
    ;;
  --no-apps)
    APPS=0
    ;;
  --all)
    PLASMA=1
    APPS=1
    ;;
  --no-follow)
    FOLLOW=0
    ;;
  --no-test-wallpaper)
    TEST_WP=0
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

if [ -z "$TEST_WP" ]; then
  case "${KUBE_NESTED_WALLPAPER:-test}" in
  test)
    TEST_WP=1
    ;;
  system)
    TEST_WP=0
    ;;
  *)
    echo "error: KUBE_NESTED_WALLPAPER vale '$KUBE_NESTED_WALLPAPER' (test|system)" >&2
    exit 2
    ;;
  esac
fi

echo "Deten el anterior escritorio anidado"
SOCK="kube-effect-nested-0"
# Second marker for the KCM guard (native/src/kcm/kube_effect_reload.cpp): the
# socket name already carries it, and this flag makes it explicit for any child
# that only inspects the environment.
export KUBE_NESTED=1
# El backend ffmpeg de QtMultimedia sondea dispositivos de aceleración por HW al
# construir el MediaPlayer, y uno de ellos (vaapi) abre el X11 display con
# XOpenDisplay. Dentro del anidado eso es un bloqueo MUTUO: el hilo principal de
# kwin_wayland se queda en xcb_connect_to_fd esperando a su propio Xwayland, y
# ese Xwayland necesita el bucle de eventos de KWin para terminar de nacer. El
# resultado es el "se traba, no lanza el efecto y no hay nada en el log" (pila
# tomada con eu-stack el 2026-11-25: QuickSceneEffect::addScreen → QQuickMediaPlayer
# → av_hwdevice_ctx_create → XOpenDisplay → __poll). Vaciar la lista deja el
# sondeo HW apagado y el MediaPlayer se construye sin tocar X11.
export QT_FFMPEG_DECODING_HW_DEVICE_TYPES="${QT_FFMPEG_DECODING_HW_DEVICE_TYPES-}"
RUN="$(id -u)"
SAY() { echo "[$(date +%H:%M:%S)] $*"; }

# Private per-uid harness root under ${TMPDIR:-/tmp} (0700, owner-verified,
# symlinks refused): replaces the old fixed /tmp/kube-effect-test-config and
# the fixed /tmp/kube-effect-nested.{log,pid,addr}, which any local user
# could pre-create or symlink to hijack the nested config, the logs and the
# cleanup rm -rf. Reuse across runs is PRESERVED on purpose: the data dir
# keeps the installed effect package (kpackagetool6 --upgrade stays
# incremental) and --no-follow leaves a live nested reading $CFG, so the
# name is deterministic (uid-suffixed) instead of a fresh mktemp -d.
# shellcheck source=scripts/nested-harness-root.sh
. scripts/nested-harness-root.sh
if ! nested_harness_root_prepare; then
  SAY "error: la ruta del arnés es insegura; aborta"
  exit 1
fi
CFG="$HARNESS_ROOT/config"
# Data dir propia: una instalación limpia no tiene plasmoids descargados, así que
# el anidado tampoco debe ver los del host (~/.local/share/plasma/plasmoids).
# El paquete del efecto se instala aquí: kpackagetool6 respeta XDG_DATA_HOME, y
# NO se exporta global para no mover el stamp de make native
# (~/.local/share/kube-effect). Se pasa por línea de mando a cada proceso del
# anidado.
DATA="$CFG/data"
mkdir -p "$CFG" "$DATA"
chmod 700 "$CFG"
ADDR="$HARNESS_ROOT/nested.addr"
PIDFILE="$HARNESS_ROOT/nested.pid"
KWIN_LOG="$HARNESS_ROOT/nested.log"
PLASMA_LOG="$HARNESS_ROOT/plasma.log"
KCM_LOG="$HARNESS_ROOT/kcm.log"
BUILD_LOG="$HARNESS_ROOT/native-build.log"
CHILD_PIDS=()
KUBE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kube-effect"

# Migration notice for the old fixed path from earlier runs: only point at it,
# never touch it blindly (it could be a symlink or owned by someone else).
if [ ! -L /tmp/kube-effect-test-config ] && [ -O /tmp/kube-effect-test-config ]; then
  SAY "aviso: quedó config de lanzamientos viejos en /tmp/kube-effect-test-config; puedes borrarla"
fi

# Exit cleanup: the tree is removed ONLY when this run stopped its own nested
# (CLEAN_TREE=1, set by Ctrl+C/TERM and by the "compositor ended" path).
# With --no-follow the nested stays alive reading $CFG so the tree persists
# (same contract as before), and on error exits the logs stay for forensics.
# nested_harness_rm_rf refuses anything not anchored to $HARNESS_ROOT.
CLEAN_TREE=0
cleanup_on_exit() {
  [ "$CLEAN_TREE" -eq 1 ] || return 0
  if nested_harness_rm_rf "$HARNESS_ROOT"; then
    SAY "árbol del arnés borrado (config, data y logs): $HARNESS_ROOT"
  fi
}
trap cleanup_on_exit EXIT

# A pid read from the harness pidfile is only our nested KWin when it is
# numeric AND its comm is kwin_wayland: a stale pidfile could otherwise name
# (and kill) any process.
# The pidfile is written by the inner shell right before "exec kwin_wayland", so
# it holds the compositor itself and not dbus-run-session (killing that one left
# the old kwin_wayland orphaned).
is_nested_pid() {
  case "$1" in
  '' | *[!0-9]*) return 1 ;;
  esac
  ps -o comm= -p "$1" 2>/dev/null | grep -q 'kwin_wayland'
}

# Stops everything this script started: sample apps, plasmashell, the KCM and
# finally the compositor (TERM, then KILL after 4 s).
stop_nested() {
  local pid
  for pid in ${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}; do
    kill "$pid" 2>/dev/null || true
  done
  if is_nested_pid "$NESTED_PID"; then
    kill "$NESTED_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      is_nested_pid "$NESTED_PID" || break
      sleep 0.2
    done
    is_nested_pid "$NESTED_PID" && kill -9 "$NESTED_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE" "$ADDR" "/run/user/$RUN/$SOCK" "/run/user/$RUN/$SOCK.lock"
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
    # ECM's prefix.sh lives outside the repo; nothing to follow statically.
    # shellcheck source=/dev/null
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
  if ! make native >"$BUILD_LOG" 2>&1; then
    SAY "error: make native falló; no arranco el anidado"
    tail -n 20 "$BUILD_LOG"
    exit 1
  fi
  SAY "native/: compilado e instalado (ver $KUBE_DATA/native-stamp.json)"
else
  SAY "native/: sin fuentes; sigo solo con el efecto QML"
fi

# 2. Instalar el efecto en la data aislada (para que el anidado lo encuentre,
#    y solo él: el host no se entera de esta copia).
if XDG_DATA_HOME="$DATA" kpackagetool6 --type KWin/Effect --upgrade "$(pwd)/package/" >/dev/null 2>&1; then
  SAY "efecto instalado/actualizado en $DATA"
elif XDG_DATA_HOME="$DATA" kpackagetool6 --type KWin/Effect --install "$(pwd)/package/" >/dev/null 2>&1; then
  SAY "efecto instalado en $DATA"
else
  SAY "aviso: no pude instalar el efecto; usa 'make install'"
fi

# 3. Config del anidado. KUBE_NESTED_CONFIG=clean (defecto) = FÁBRICA: no se
#    copia tu kwinrc, así que el anidado se comporta como una instalación limpia
#    de Plasma (sin tus efectos, atajos ni ajustes personales). Lo único que se
#    hereda es la sección [Effect-kube-effect], que es lo que se prueba (modo de
#    fondo, imagen, vídeo, bordes). KUBE_NESTED_CONFIG=host = comportamiento
#    antiguo: kwinrc completo del host y todos los demás efectos apagados.
nested_harness_rm_rf "$CFG/kwinrc" "$CFG/kwinrc.tmp"
CONFIG_MODE="${KUBE_NESTED_CONFIG:-clean}"

case "$CONFIG_MODE" in
clean)
  SAY "config de fábrica (KUBE_NESTED_CONFIG=clean)"
  ;;
host)
  SAY "config heredada del host (KUBE_NESTED_CONFIG=host)"
  [ -f "$HOME/.config/kwinrc" ] && cp "$HOME/.config/kwinrc" "$CFG/kwinrc"
  ;;
*)
  echo "error: KUBE_NESTED_CONFIG vale '$CONFIG_MODE' (limpia|host)" >&2
  exit 2
  ;;
esac

# 3 escritorios virtuales = 3 caras.
kwriteconfig6 --file "$CFG/kwinrc" --group Desktops --key Number "$DESKTOPS"
kwriteconfig6 --file "$CFG/kwinrc" --group Desktops --key Rows 1

# En limpio: solo la sección del efecto, copiada del host si existe.
if [ "$CONFIG_MODE" = "clean" ] && [ -f "$HOME/.config/kwinrc" ]; then
  awk '
        /^\[/ { inGroup = ($0 == "[Effect-kube-effect]") }
        inGroup { print }
    ' "$HOME/.config/kwinrc" >"$CFG/kube-effect-section.tmp"
  if [ -s "$CFG/kube-effect-section.tmp" ]; then
    cat "$CFG/kube-effect-section.tmp" >>"$CFG/kwinrc"
    SAY "ajustes de [Effect-kube-effect] heredados del host"
  else
    SAY "el host no tiene [Effect-kube-effect]: fondo por defecto (Color)"
  fi
  rm -f "$CFG/kube-effect-section.tmp"
fi

# En modo host se apagan los demás efectos (menos carga y menos ruido); en modo
# limpio no hay efectos del host que apagar. KUBE_NESTED_KEEP_EFFECTS="blur,"
# "screenshot" conserva los que indiques (screenshot hace falta para thumbnails
# y wallpapers reales).
if [ "$CONFIG_MODE" = "host" ]; then
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
fi
kwriteconfig6 --file "$CFG/kwinrc" --group Plugins --key kube-effectEnabled true
# 3b. Atajo del anidado. Con o sin captura de puntero, el teclado pasa ANTES por
#     el compositor del host: si el host tiene kube-effect activo, su KWin tiene
#     "[kwin] Kube Effect=Meta+K" registrado y se come la tecla, así que dentro
#     del anidado no pasa nada. Si el host NO lo tiene activo, Meta+K está libre
#     y es lo más cómodo. KUBE_NESTED_SHORTCUT manda siempre.
HOST_KUBE_ON=$(kreadconfig6 --file "$HOME/.config/kwinrc" --group Plugins \
  --key kube-effectEnabled 2>/dev/null || true)
if [ -n "${KUBE_NESTED_SHORTCUT:-}" ]; then
  NESTED_SHORTCUT="$KUBE_NESTED_SHORTCUT"
elif [ "$HOST_KUBE_ON" = "true" ]; then
  NESTED_SHORTCUT="Meta+Shift+K"
else
  NESTED_SHORTCUT="Meta+K"
fi
SAY "atajo del cubo en el anidado: $NESTED_SHORTCUT (host kube-effect=$HOST_KUBE_ON)"
kwriteconfig6 --file "$CFG/kglobalshortcutsrc" --group kwin --key "Kube Effect" \
  "$NESTED_SHORTCUT,$NESTED_SHORTCUT,Toggle Kube Effect"
# NO se fuerza el modo de fondo: el anidado prueba la configuración del efecto.
# Forzar Background=1 (Image) sobre un kwinrc con Background=Video y SkyBox
# apuntando a un .mp4 dejaba el casco sin pintar y parecía un fallo del efecto.

# 3c. Wallpaper de prueba: un PNG direccional generado por el propio arnés
#    (sin asset binario en el repo) aplicado al containment de escritorio del
#    anidado. Plasma 6.8.3 no admite un wallpaper distinto por escritorio
#    virtual (medido 2026-11-27: sin claves por escritorio en el main.xml del
#    plugin org.kde.image ni lógica por desktop en el plugin; la petición
#    upstream sigue abierta: KDE bug 155150), así que el patrón es ÚNICO y
#    cada escritorio se identifica además con una ventana maximizada E1..EN
#    (scripts/test-wallpaper-label.py). En modo host y sin plasmashell no se
#    impone nada: conserva el comportamiento antiguo.
WP_PNG=""
WP_STATUS=""
LABELS_ON=0
if [ "$TEST_WP" -eq 0 ]; then
  SAY "wallpaper de prueba desactivado: plasmashell usara el del sistema"
  WP_STATUS="del sistema (desactivado)"
elif [ "$CONFIG_MODE" = "host" ]; then
  SAY "wallpaper de prueba omitido: KUBE_NESTED_CONFIG=host conserva el tuyo"
  WP_STATUS="del sistema (modo host)"
elif [ "$PLASMA" -eq 0 ]; then
  SAY "wallpaper de prueba omitido: sin plasmashell no hay escritorio que vestir"
  WP_STATUS="sin escritorio (--no-plasma)"
elif ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import PIL' 2>/dev/null; then
  SAY "aviso: falta python3 o PIL; el anidado usara el wallpaper del sistema"
  WP_STATUS="del sistema (falta python3+PIL)"
else
  WP_DIR="$HARNESS_ROOT/wallpaper"
  WP_PNG="$WP_DIR/directional.png"
  if python3 scripts/make-test-wallpaper.py --output "$WP_PNG" \
    --width "$NESTED_WIDTH" --height "$NESTED_HEIGHT" >/dev/null; then
    SAY "wallpaper de prueba generado: $WP_PNG (${NESTED_WIDTH}x${NESTED_HEIGHT})"
    WP_STATUS="de prueba (direccional): $WP_PNG"
    if python3 -c 'import PySide6.QtWidgets' 2>/dev/null; then
      LABELS_ON=1
    else
      SAY "aviso: sin PySide6; no se lanzan las ventanas E1..EN (el wallpaper vale igual)"
    fi
  else
    SAY "aviso: el generador del wallpaper fallo; el anidado usara el del sistema"
    WP_STATUS="del sistema (fallo al generar)"
    WP_PNG=""
  fi
fi

# Undo a wallpaper patch from an earlier run: the config tree is REUSED across
# launches, so a stale appletsrc would keep pointing at the test PNG even with
# --no-test-wallpaper. Only files that reference OUR generated wallpaper are
# removed (plasmashell rebuilds them factory-default on the next start); the
# rm goes through the anchored helper.
if [ -z "$WP_PNG" ]; then
  while IFS= read -r old_appletsrc; do
    [ -n "$old_appletsrc" ] || continue
    if grep -qF "$HARNESS_ROOT/wallpaper/" "$old_appletsrc" 2>/dev/null; then
      nested_harness_rm_rf "$old_appletsrc"
      SAY "appletsrc previo con wallpaper de prueba borrado: arranca de fabrica"
    fi
  done < <(find "$CFG" -maxdepth 1 -name '*appletsrc*' -type f 2>/dev/null)
fi

# 4. Arrancar el KWin anidado en una ventana 1600x900, bus privado. SOLO
#    Wayland: sin --xwayland. El proyecto no apunta a X11, y levantar un Xwayland
#    dentro del anidado abre un bloqueo mutuo con el sondeo HW de ffmpeg (ver el
#    export QT_FFMPEG_DECODING_HW_DEVICE_TYPES de arriba).
SAY "arrancando KWin anidado (ventana ${NESTED_WIDTH}x${NESTED_HEIGHT}, solo Wayland)..."
XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" setsid \
  dbus-run-session -- \
  sh -c 'echo $$ > "$1"; echo "$DBUS_SESSION_BUS_ADDRESS" > "$2"; exec kwin_wayland --socket "$3" --no-lockscreen --width "$4" --height "$5"' _ \
  "$PIDFILE" "$ADDR" "$SOCK" "$NESTED_WIDTH" "$NESTED_HEIGHT" \
  >"$KWIN_LOG" 2>&1 </dev/null &
NESTED_PID=$!

for _ in $(seq 1 30); do
  [ -s "$ADDR" ] && break
  sleep 1
done
NBA=$(cat "$ADDR" 2>/dev/null || true)
if [ -z "$NBA" ]; then
  SAY "error: el bus del anidado no arrancó; mira $KWIN_LOG"
  exit 1
fi
# The pidfile now carries the compositor pid (written by the inner sh before
# exec): $! is only dbus-run-session, which is why killing it used to orphan
# kwin_wayland.
NESTED_PID=$(cat "$PIDFILE" 2>/dev/null || true)
SAY "nested pid=$NESTED_PID bus=$NBA socket=$SOCK"

# 5. plasmashell dentro del anidado: panel y wallpaper. Con XDG_DATA_HOME
#    temporal no se carga ningún plasmoid descargado (ni sus errores con Plasma
#    6.8): solo los de /usr/share. Para quitarlo: --no-plasma.
#    Con wallpaper de prueba el arranque va en DOS ETAPAS: (1) plasmashell
#    arranca con config limpia y escribe él mismo su appletsrc de fábrica en
#    $CFG (así no hay que adivinar el id del containment ni el vínculo con la
#    actividad/pantalla); (2) se para, se le pone el PNG al containment del
#    escritorio con las claves medidas del host —
#    [Containments][N] wallpaperplugin=org.kde.image y
#    [Containments][N][Wallpaper][org.kde.image][General] Image=file://... —
#    y se relanza leyendo esa config.
start_plasmashell() {
  # Ruido ajeno al cubo, silenciado SOLO en el shell del anidado: Qt 6.12 avisa
  # "Final member StackingOrder is overridden in class QQmlDMAbstractItemModelData"
  # cada vez que un applet de Plasma monta un delegate sobre el WindowModel de
  # KWin (el rol viene marcado final en C++). Medido 2026-11-25: 20 avisos, todos
  # de plasmashell y 0 de kwin_wayland, o sea ni del efecto ni de KWin. No se
  # puede arreglar desde aquí (es de plasma-workspace/Qt); taparlo en el log del
  # anidado deja legible lo que sí importa (las líneas kube-effect:).
  # Si el usuario trae sus propias QT_LOGGING_RULES se conservan detrás.
  local rules="qt.qml.propertyCache.append=false${QT_LOGGING_RULES:+;$QT_LOGGING_RULES}"
  DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
    QT_LOGGING_RULES="$rules" \
    plasmashell >>"$PLASMA_LOG" 2>&1 </dev/null &
  PLASMA_PID=$!
  CHILD_PIDS+=("$PLASMA_PID")
  sleep 6
}

if [ "$PLASMA" -eq 1 ]; then
  SAY "lanzado plasmashell en el anidado (solo plasmoids de sistema)"
  start_plasmashell
  if [ -n "$WP_PNG" ]; then
    SAY "wallpaper de prueba: esperando el appletsrc de fábrica (etapa 1)..."
    APPLETSRC=""
    for _ in $(seq 1 25); do
      APPLETSRC=$(find "$CFG" -maxdepth 1 -name '*appletsrc*' -type f -print -quit 2>/dev/null)
      [ -n "$APPLETSRC" ] && grep -q '^\[Containments\]\[[0-9]*\]$' "$APPLETSRC" && break
      sleep 1
    done
    # El containment de ESCRITORIO es el bloque [Containments][N] con
    # formfactor=0 (los paneles traen formfactor=2; medido en el host).
    DESKTOP_CID=""
    [ -n "$APPLETSRC" ] && DESKTOP_CID=$(
      awk '
            /^\[Containments\]\[[0-9]+\]$/ {
                id = $0
                sub(/^\[Containments\]\[/, "", id)
                sub(/\]$/, "", id)
                next
            }
            # Any other section header leaves the containment-root block: a
            # formfactor=0 inside some applet config must NOT count.
            /^\[/ { id = "" }
            /^formfactor=0$/ && id != "" { print id
            exit }
            ' "$APPLETSRC"
    )
    if [ -n "$DESKTOP_CID" ]; then
      kill "$PLASMA_PID" 2>/dev/null || true
      for _ in $(seq 1 20); do
        kill -0 "$PLASMA_PID" 2>/dev/null || break
        sleep 0.5
      done
      if kwriteconfig6 --file "$APPLETSRC" --group Containments --group "$DESKTOP_CID" \
        --key wallpaperplugin org.kde.image &&
        kwriteconfig6 --file "$APPLETSRC" --group Containments --group "$DESKTOP_CID" \
          --group Wallpaper --group org.kde.image --group General \
          --key Image "file://$WP_PNG" &&
        [ "$(kreadconfig6 --file "$APPLETSRC" --group Containments --group "$DESKTOP_CID" \
          --group Wallpaper --group org.kde.image --group General --key Image)" = "file://$WP_PNG" ]; then
        SAY "wallpaper de prueba aplicado al containment $DESKTOP_CID de $(basename "$APPLETSRC")"
      else
        SAY "aviso: no pude parchear el appletsrc; queda el wallpaper del sistema"
        WP_STATUS="del sistema (no pude parchear el appletsrc)"
      fi
      SAY "relanzando plasmashell con la config parcheada (etapa 2)..."
      start_plasmashell
    else
      SAY "aviso: plasmashell no dejó un containment de escritorio en el appletsrc; wallpaper del sistema"
      WP_STATUS="del sistema (appletsrc sin containment)"
    fi
  fi
else
  SAY "sin plasmashell en el anidado (--no-plasma): sin panel ni wallpaper de escritorio"
fi

# 5b. Ventanas etiqueta E1..EN (maximizadas, color distinto por escritorio):
#     identifican el escritorio de cada cara mientras Plasma no sepa poner un
#     wallpaper por escritorio virtual. Se reparten igual que las apps del
#     paso 6: por DBus setCurrentDesktop antes de lanzar cada una.
if [ "$LABELS_ON" -eq 1 ]; then
  for desktop in $(seq 1 "$DESKTOPS"); do
    busctl --address="$NBA" call org.kde.KWin /KWin org.kde.KWin \
      setCurrentDesktop i "$desktop" >/dev/null 2>&1 || true
    DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
      python3 scripts/test-wallpaper-label.py --desktop "$desktop" >/dev/null 2>&1 </dev/null &
    CHILD_PIDS+=("$!")
    SAY "etiqueta E$desktop lanzada (maximizada) en el escritorio $desktop"
    sleep 1
  done
fi

# 6. Ventanas: una por escritorio virtual, para que las 3 caras tengan contenido.
#    Se cambia de escritorio por DBus (setCurrentDesktop) antes de lanzar cada
#    app; así la prueba siempre empieza con las caras llenas. Lista editable con
#    KUBE_NESTED_APPS="konsole dolphin kate".
if [ "$APPS" -eq 1 ]; then
  index=0
  for app in ${KUBE_NESTED_APPS:-konsole dolphin kate}; do
    if ! command -v "$app" >/dev/null 2>&1; then
      SAY "aviso: no encuentro $app; sigo con la siguiente"
      continue
    fi
    desktop=$(((index % DESKTOPS) + 1))
    busctl --address="$NBA" call org.kde.KWin /KWin org.kde.KWin \
      setCurrentDesktop i "$desktop" >/dev/null 2>&1 || true
    DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
      "$app" >/dev/null 2>&1 </dev/null &
    CHILD_PIDS+=("$!")
    SAY "lanzado $app en el escritorio $desktop"
    sleep 2
    index=$((index + 1))
  done
  # De vuelta al primer escritorio: la prueba empieza siempre igual.
  busctl --address="$NBA" call org.kde.KWin /KWin org.kde.KWin \
    setCurrentDesktop i 1 >/dev/null 2>&1 || true
else
  SAY "sin ventanas en el anidado (--no-apps: las 3 caras salen vacías)"
fi

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
    KCM_STATUS="abierto dentro del anidado (log: $KCM_LOG)"
    SAY "lanzando kcmshell6 kcm_kube_effect_plus dentro del anidado"
    (
      # ECM's prefix.sh expands variables unguarded
      the harness runs with
      # 'set -u', so relax it while sourcing.
      set +u
      # shellcheck source=/dev/null
      . "$KUBE_DATA/prefix.sh"
      set -u
      DBUS_SESSION_BUS_ADDRESS="$NBA" XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$CFG" WAYLAND_DISPLAY="$SOCK" \
        kcmshell6 kcm_kube_effect_plus >"$KCM_LOG" 2>&1 </dev/null &
      CHILD_PIDS+=("$!")
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

   1. Dale foco a la ventana del anidado (clic dentro).
   2. Pulsa $NESTED_SHORTCUT para abrir / cerrar el cubo. Meta+K NO vale:
      el compositor del host se queda ese atajo global y dentro del anidado
      nunca llega a KWin. Alternativa sin teclado: el borde superior
      (BorderActivate=1) con el puntero capturado (Ctrl derecho captura/suelta).
   3. Configura el efecto DENTRO del anidado (System Settings), o edita
      $CFG/kwinrc  sección [Effect-kube-effect].
   4. Rota los escritorios/fondos y comprueba lo que quieras.
      Con el wallpaper de prueba: la flecha debe apuntar a ARR y el cuadrante
      magenta debe quedar en la esquina superior-IZQUIERDA; si el patrón sale
      espejado o girado, esa cara (o tapa) está mapeando la textura al revés.
      La ventana E<k> debe verse SOLO en la cara del escritorio k (ADR-004).

   KCM nativo 'Kube Effect Plus' (escribe en $CFG/kwinrc): $KCM_STATUS

   Engranaje del efecto = menú QML (config.ui), exista o no el nativo.
   'Kube Effect Plus' = KCM nativo, solo en Personalización.
   Modo de este arnés: $NATIVE_LABEL
   Wallpaper del anidado: $WP_STATUS

   Parar el anidado:   $STOP_HINT
   Raíz del arnés:     $HARNESS_ROOT (config, data y logs)
   Logs:               $KWIN_LOG
                       $PLASMA_LOG
                       $KCM_LOG
======================================================================
EOF

# 8. Seguir los logs en vivo. Ctrl+C para todo (deja de seguir y para el
#    anidado); con --no-follow se sale dejándolo vivo, como antes.
if [ "$FOLLOW" -eq 1 ] && is_nested_pid "$NESTED_PID"; then
  trap 'echo; SAY "Ctrl+C: parando el anidado…"; stop_nested; SAY "anidado parado"; CLEAN_TREE=1; exit 0' INT TERM
  LOGS=("$KWIN_LOG")
  [ -f "$PLASMA_LOG" ] && LOGS+=("$PLASMA_LOG")
  [ -f "$KCM_LOG" ] && LOGS+=("$KCM_LOG")
  SAY "siguiendo logs en vivo (Ctrl+C para parar el anidado)"
  # Un solo tail: sin tuberías que dejen procesos huérfanos y con una sola
  # señal para cortarlo. Con varios ficheros imprime la cabecera '==> x <=='.
  tail -n +1 -F "${LOGS[@]}" 2>/dev/null &
  TAIL_PID=$!
  while is_nested_pid "$NESTED_PID" && kill -0 "$TAIL_PID" 2>/dev/null; do
    sleep 1
  done
  kill "$TAIL_PID" 2>/dev/null || true
  wait "$TAIL_PID" 2>/dev/null || true
  trap - INT TERM
  if is_nested_pid "$NESTED_PID"; then
    SAY "dejo de seguir los logs; el anidado sigue vivo (kill $NESTED_PID)"
  else
    SAY "el compositor anidado terminó; limpio lo que lanzó el arnés"
    stop_nested
    CLEAN_TREE=1
  fi
elif [ "$FOLLOW" -eq 0 ]; then
  SAY "logs en $KWIN_LOG · $PLASMA_LOG · $KCM_LOG (--no-follow: no los sigo)"
  SAY "el anidado sigue vivo: $HARNESS_ROOT se conserva (se reusa en el próximo arranque)"
fi
