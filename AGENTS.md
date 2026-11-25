# AGENTS.md — kube-effect

Cubo de escritorios para KWin, en **QML puro**. Arranca como el cubo **virgen**
de KDE y crece feature a feature. Docs en español, código en inglés.

## Qué se hace

Clon del cubo KDE con Id `kube-effect`. Un cambio por vez, verificado antes de
pasar al siguiente.

## Reglas

- Solo QML en `package/`, con una excepción: `package/contents/native/` son
  fuentes de Kube Effect Plus que KWin **no carga**; solo existen para que el
  usuario compile el módulo extra desde la copia instalada. `native/` sigue
  siendo la fuente de verdad: `make sync-package-native` copia y `make check`
  falla si divergen.
- **Solo Wayland.** Nada de X11/Xwayland ni de rutas de compatibilidad con X11:
  el efecto es un `SceneEffect` de KWin Wayland y el arnés arranca el anidado
  **sin** `--xwayland` (levantar Xwayland dentro del anidado empantanaba al
  `MediaPlayer` de QtMultimedia: ver `doc/trucos-aprendidos.md`, sección A).
- **Prueba solo en KWin anidado. Nunca en sesión del host** (`scripts/kwin-nested-test.sh`).
- Código y comentarios en inglés. Docs en español.
- Todo lo comprueba `make lint`. Limpio antes de commit.
- Cada asset va con origen y licencia (cuando haya assets).
- Antes de implementar una feature, actualiza `doc/requerimientos.md`.

## Dónde va cada cosa

- `package/` — el efecto (sale a KDE Store). Solo QML, más
  `package/contents/native/` (copia de `native/` para compilar Plus desde la
  copia instalada; KWin no la carga).
- `native/` — **Kube Effect Plus** (C++/CMake), módulo nativo opcional
  (`kcm_kube_effect_plus`, «Kube Effect Plus»). Se compila a demanda con
  `make native` (sin root, prefijo privado; solo se abre con `prefix.sh`); `make
  native-install` lo pone en `/usr` y sí aparece en Preferencias → Gestión de
  ventanas. Ese target compila como tu usuario y solo invoca `sudo` en el paso
  de instalación (contraseña una vez, sin artefactos de root en el build), así
  que no se le pone `sudo` delante. `make native-status` dice si el stamp está
  viejo. `native/build.sh` también funciona desde
  `package/contents/native/build.sh` (calcula todo desde su propia ruta).
- `doc/` — requerimientos, estado del arte y trucos aprendidos.
- `scripts/` — checks y arnés de test anidado.
- `../kdeplasma-addons/kwin/effects/cube/` — cubo oficial KDE (referencia viva).
- `../kwin-effects-cube/` — cubo C++ de zzag (referencia de geometría).
- `../kwin-effect-kkube/` — proyecto anterior (exploración con features), referencia. no copiar codigo entenderlo

## Recarga de QML (CRÍTICO)

KWin cachea el QML compilado en memoria (bug KDE #514131). `unloadEffect` +
`loadEffect` **NO recarga**; `reconfigureEffect` tampoco. Para ver cambios:
reiniciar KWin o usar el **KWin anidado** (proceso nuevo, compila desde disco).
Detalle en `doc/trucos-aprendidos.md`. esto para probarlo en host pero durante
desarrollo no se usa esto

## Arnés de test anidado

`./scripts/kwin-nested-test.sh` — KWin privado (bus propio,
`XDG_CONFIG_HOME` y **`XDG_DATA_HOME`** temporales), nunca toca la sesión real.
**Arranca como una instalación limpia**: kwinrc de FÁBRICA (no se copia el del
host; solo se hereda la sección `[Effect-kube-effect]`, que es lo que se prueba),
3 escritorios virtuales, **una ventana por cara** (repartida por DBus
`setCurrentDesktop`, lista en `KUBE_NESTED_APPS`) y **plasmashell con el panel y
el wallpaper del sistema**. La data dir aislada hace que NO se cargue ningún
plasmoid descargado (verificado: con `XDG_DATA_HOME` temporal,
`Plasma.Flex.Hub`/`Plasma.Control.Hub` no aparecen; sin aislar sí) — verificado
2026-11-25. `--no-plasma` deja el anidado sin panel ni wallpaper;
`--no-apps` sin ventanas; `KUBE_NESTED_CONFIG=host` vuelve al comportamiento
antiguo (kwinrc completo del host y demás efectos apagados con
`KUBE_NESTED_KEEP_EFFECTS="blur,screenshot"`). No fuerza el modo de fondo.
Al terminar se queda **siguiendo los logs**; `Ctrl+C` deja de seguir y **para el
anidado** (`--no-follow` = imprimir el resumen y salir). **El atajo dentro del
anidado es `Meta+Shift+K`** (`KUBE_NESTED_SHORTCUT`), no `Meta+K`: el KWin del
host lo tiene registrado como atajo global (`[kwin] Kube Effect=Meta+K` en su
kglobalshortcutsrc) y se lo queda antes de que la ventana anidada reciba la
tecla, así que el efecto no se activa y no aparece nada en el log. Alternativa:
el borde superior (`BorderActivate=1`) con el puntero capturado (Ctrl derecho
captura/suelta).

- El arnés compila `native/` antes de arrancar y **aborta** si falla (nunca se
  prueba con un binario viejo). `--no-native` salta todo el lado nativo (sin
  `make native`, sin `prefix.sh`, sin `kcmshell6`): experiencia sin compilar.
- El comando de compilación que muestra el menú QML se **oculta en pruebas** (se
  compila a mano al lanzar el arnés).

## Verificación

`make lint` (qmllint + qmlformat + esquema + json/yaml + sincronía de
`package/contents/native/`). Si hay SonarQube local, `make lint` corre además el
escaneo; si no, `make check` basta.

## KConfigXT

Enum = **entero** en kwinrc (`Background=0`, `Shape=2`). Strings rompen el
entorno (`GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`). Grupo `[Effect-kube-effect]`.
Secretos: token Sonar en `.sonar-token` (600, gitignored), si se usa Sonar.

El usuario tiene que hacer la spruebas solo lanza el agente no tiene que hacer capturas salvo que se pida explicitamente pero el usuario siempre debe de hacer las pruebas y las verificaciones
