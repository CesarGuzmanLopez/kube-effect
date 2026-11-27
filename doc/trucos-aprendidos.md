# Trucos aprendidos — qué NO funciona y qué SÍ

Bitácora de trampas del pipeline real (KWin 6 + Qt 6.12 + QtQuick3D, QML
`declarativescript`). Cada punto se verificó en la sesión real o en el KWin
anidado. Si algo aquí contradice un tutorial, gana esta lista: son hechos
medidos en ESTA máquina.

## A. Recarga de código (el que más tiempo costó)

### ❌ TRAMPA: Xwayland dentro del anidado + MediaPlayer = bloqueo mutuo

Síntoma: el anidado **no lanza el efecto, se traba y no deja interactuar; no hay
nada en el log**. El hilo principal queda dormido (DBus no responde, `busctl call
… currentDesktop` expira) y la pila lo explica:

```
KWin::QuickSceneEffect::addScreen → QQml… → QQuickMediaPlayer → QMediaPlayer::QMediaPlayer
  → av_hwdevice_ctx_create → XOpenDisplay → xcb_connect_to_fd → __poll   (eterno)
```

El backend ffmpeg de QtMultimedia sondea dispositivos HW al construir el
`MediaPlayer` y uno de ellos abre el X11 *display*. En el anidado ese display era
su **propio** Xwayland (`--xwayland :2`), que aún no podía atender porque
necesita el bucle de eventos de KWin, y KWin estaba esperando al Xwayland.

Arreglo (y por qué el proyecto es **solo Wayland**):
1. El arnés arranca `kwin_wayland` **sin** `--xwayland`: no hay X que esperar.
2. Por seguridad, además `QT_FFMPEG_DECODING_HW_DEVICE_TYPES=""` en el entorno
   del anidado (el sondeo HW por X11 no tiene nada que hacer aquí).

Diagnóstico sin sudo gráfico: `eu-stack -p $(cat "${TMPDIR:-/tmp}/kube-effect-nested-$(id -u)/nested.pid")`
(37 pilas) y comprobar si el compositor responde por DBus.

### ❌ FALSO: `unloadEffect` + `loadEffect` recarga el QML

No. KWin cachea el QML compilado **en memoria por URL** (bug KDE #514131,
CONFIRMADO). Reinstalar el paquete y recargar deja corriendo la versión VIEJA.
Lo medimos: cambiar `animationDuration` a 777 y seguir viendo 400 tras recargar.

### ❌ FALSO: `reconfigureEffect` recarga el QML

No. Solo re-lee la CONFIG, no recompila QML.

### ❌ FALSO: borrar `~/.cache/kwin/qmlcache/*.qmlc`

No sirve. El caché que manda es el **en memoria** del `QQmlEngine`, no el disco.

### ✅ VERDADERO: reiniciar KWin, o usar un KWin anidado

- Recarga real: cerrar sesión y volver a entrar. `systemctl --user restart
  plasma-kwin_wayland.service` NO vale en Wayland (2026-11-25, medido): mata
  todos los clientes (plasmashell, kded, apps), el compositor nuevo sale en un
  socket nuevo sin registrar `org.kde.KWin` y nada reconecta; el escritorio
  queda muerto.
- **Mejor para desarrollar**: KWin anidado (`scripts/kwin-nested-test.sh`), que es
  un proceso NUEVO → compila desde disco. Aislado (bus privado, `XDG_CONFIG_HOME`
  propio).
- **Desde el KCM nativo**: botón «Aplicar cambios de código» → no reinicia KWin
  en caliente (2026-11-25, medido: restart mata la sesión Wayland y el
  escritorio queda muerto). Pide confirmación y hace un **logout limpio**
  (`org.kde.Shutdown /Shutdown org.kde.Shutdown.logout`); SDDM autologin
  devuelve la sesión y el `kwin_wayland` nuevo compila el QML desde disco. Botón
  secundario «Copiar comando» deja `systemctl --user restart
  plasma-kwin_wayland.service` para un TTY. No usa `reconfigureEffect` (solo
  re-lee la config) ni `kwin_wayland --replace` (X11; en Wayland peor). Se
  niega si `WAYLAND_DISPLAY` contiene `kube-effect-nested` o `KUBE_NESTED=1`
  (el arnés exporta el flag): dentro del anidado el compositor es del script, no
  se reinicia desde ahí. Además compara el PID de `org.kde.KWin` del bus con el
  `MainPID` de la unidad (`kwin_wayland_wr` es el envoltorio y `kwin_wayland` su
  hijo, por eso compara el árbol de procesos).

### ❌ TRAMPA: imagen configurada con «Modo de fondo» en Color no se pinta

`SkyBox` (la URL) solo se usa cuando `Background` (el enum) vale Image, y
`BackgroundVideo` solo con Video. kwinrc puede llevar una imagen de cuando el
enum se llamaba `SkyBox` y la clave de URL heredó el nombre viejo: el modo se
queda en su default Color y la imagen desaparece sin avisar. El KCM Plus lee
kwinrc y lo dice en negrita en la caja «Efecto» (también el caso inverso: modo
Imagen/Vídeo sin medio elegido). Si lo ves, elige el modo a mano.

### ❌ FALSO: un `VideoOutput` como `lightProbe` del SkyBox

No se pinta nada. Qt Quick 3D lo rechaza con «Cannot use QSGTexture from
Texture.sourceItem as light probe.» (medido 2026-11-25; además repetía el aviso
cada frame). `Texture.sourceItem` sí vale en el `baseColorMap` de un material.
Vídeo 360 = esfera vista desde dentro (ADR-020), no entorno.

Verificación automática (retirada por coste; sección P): `scripts/check-video-dome.py` cargaba el
`ScreenView.qml` real con un `org.kde.kwin` simulado y exige que el frame tenga
muchos colores; necesita pantalla real y en CI se salta.

Un paquete instalado **viejo** se ve igual que un bug: antes de probar, `make
install` (kpackagetool6) y relogin, porque KWin cachea el QML en memoria.

### ✅ VERDADERO: `Texture.sourceItem` solo existe si el item se renderiza

Un `VideoOutput` oculto (`visible: false`) no produce textura: la cúpula/skybox
sale en blanco. Hay que dejar la capa 2D del vídeo visible detrás del `View3D`
(la cúpula opaca la tapa) para que su textura exista.

## B. Fondo y casco

### ❌ PROHIBIDO: pintar el fondo con `window.color`

Bug real de la sesión: **el fondo se veía aunque el efecto estuviera
desactivado**. Causa: el atajo del cubo upstream
`Binding { target: root.Window.window; property: "color"; value: ... }` (opaco,
alpha 1) + `SceneEnvironment.Transparent` pinta la **superficie de la ventana del
efecto**, no la escena; ese color persiste al desactivar y tapa el escritorio
hasta reiniciar KWin. **Nunca** pintar color/degradado/imagen plana con
`window.color`.

### ✅ VERDADERO: girar el degradado es un transform; el radial hay que enfocarlo

- Un `Rectangle` con `Gradient` + `Rotation` (transform) gira **sin recrear objetos
  por frame**; para que no asomen esquinas sin pintar hay que sobredimensionarlo al
  diagonal (`Math.hypot(w, h)`) y centrarlo. Si no se remapean los stops a la franja
  visible, `Fixed` se ve distinto (solo la banda central del degradado).
- Girar un `RadialGradient` **centrado no se ve** (es radialmente simétrico): hay que
  mover el foco (`focalX`/`focalY`) sobre un círculo pequeño para que el giro se note.

### ✅ VERDADERO: pintar el casco DENTRO de la escena

`Rectangle` fullscreen (color sólido, `Gradient` o `Image` con
`PreserveAspectCrop`) detrás del `View3D`, con `visible: effect.visible` y el
modo del enum. El `View3D` usa `SceneEnvironment.Transparent` y el escritorio se
ve por los huecos entre caras. Al desactivar (`visible = false` cuando termina la
animación) no queda nada pintado. El 360 va con `SceneEnvironment.SkyBox` solo
cuando la imagen es equirect y una sonda `Image` (64 px de ancho, invisible) está
en `Image.Ready`; si no, capa plana con color de respaldo. **`Texture` de
QtQuick3D no expone `status` en Qt 6.12** (verificado en
`qquick3dtexture_p.h`): sin sonda, una ruta rota deja el SkyBox en negro.

### ❌ FALSO: atenuar un SkyBox 360 con el mismo velo 2D

El velo negro (`Rectangle` entre el casco y el `View3D`) oscurece color,
degradado e imagen plana, pero **no** un fondo `SceneEnvironment.SkyBox`: esa
panorámica la pinta el entorno 3D, no la capa 2D. Poner el velo delante del
`View3D` sí la oscurecería, pero taparía también las caras del cubo.

### ✅ VERDADERO: `SceneEnvironment.probeExposure` para atenuar el entorno

`probeExposure` (float, default 1.0; verificado en `Quick3D.qmltypes`) es el
brillo del entorno: bajarlo oscurece la panorámica y nada más. La fórmula vive
en `constants.js` (`skyBoxExposure(enabled, rotating, amount)`) = `1.0` si
`DimWhileRotating` está apagado o el cubo no gira, si no `1 - dimOpacity(...)`
recortado a `[0, 1]`, la misma señal de giro (`cameraController.busy` /
`rotationAnimation.running`) y el mismo `Behavior` de 120 ms que el velo 2D.
El `SceneEnvironment` vive en un `Loader`: se cambia el binding, no se recrea
el objeto por frame. **No** se aplican los dos a la vez: con SkyBox listo el velo
2D queda apagado (`hullDim` solo cubre el respaldo de color mientras la
sonda carga), así que no hay doble atenuado.

### ✅ VERDADERO: aislar un import opcional en su propio fichero + `Loader`

Un `import` que falla en el fichero raíz se lleva **todo** el efecto: `ScreenView.qml`
no cargaría y no habría ni cubo ni fallback. QtMultimedia es opcional (paquete
`qt6-multimedia`), así que su import vive SOLO en `package/contents/ui/HullVideo.qml`
y `ScreenView.qml` lo carga con `Loader { source: "HullVideo.qml" }`. Si el módulo
no está, el `Loader` queda en `Error` (`status === Loader.Error`), no crea item, se
avisa con `console.warn` **una vez** (no por frame) y el `Rectangle` de
`BackgroundColor` sigue pintando el casco. Mismo patrón para cualquier dependencia
QML opcional futura.

### ✅ VERDADERO: `Texture.sourceItem` acepta el `VideoOutput` (Qt 6.12)

Verificado en `Quick3D.qmltypes` de Qt 6.12: `Texture.sourceItem` es un
`QQuickItem` y `VideoOutput` lo es, así que el SkyBox 360 puede muestrear el vídeo
con `lightProbe: Texture { sourceItem: videoOutput }`. El `VideoOutput` va oculto
(`visible: false`): `QQuick3DTexture::setSourceItem` registra el item como
	extit{effect item} (`refFromEffectItem`) y lo renderiza a una capa offscreen, así
que no necesita estar visible. Alternativa si una versión futura de Qt dejara de
renderizar sourceItems ocultos: degradar el vídeo a **capa plana** (ya soportada) en
vez de dejar un SkyBox negro.

### ⚠️ `MediaPlayer` no tiene `muted` en Qt 6.12

`muted` es una propiedad de `AudioOutput`, no del reproductor. El vídeo de fondo
se silencia con `audioOutput: AudioOutput { muted: true }`; sin ese objeto, Qt
muestra el clip con su audio.

## C. Animaciones de `vector3d` (el flood de NaN)

### ❌ FALSO: `NumberAnimation on scale` / `on position` / `on eulerRotation`

Un `NumberAnimation` anima un `real`; si el destino es un `vector3d` escribe UN
solo double y Qt llena el journal con
`Could not find any constructor for value type QQuickVector3DValueType ...
QVariant(double, nan/0)` (~200/s), corrompiendo la escena.

### ❌ FALSO: `Vector3dAnimation` en un `Behavior on scale` o `SequentialAnimation on scale`

En esta versión también produjo NaN (el patrón value-source sobre `scale` con
varios consumidores choca).

### ✅ VERDADERO: animar un ESCALAR y derivar el vector

```qml
property real pulse: 1.6
scale: Qt.vector3d(pulse, pulse, pulse)
SequentialAnimation on pulse { NumberAnimation { from: 1.5; to: 1.7; ... } }
```

Lo mismo para rotación: `property real orbit; eulerRotation: Qt.vector3d(tilt, orbit, 0)`
con `NumberAnimation on orbit`. Nunca animar `scale`/`eulerRotation`/`position`
directamente.

## D. Diagnóstico en caliente

### ❌ FALSO: `console.log` / `console.warn` desde QML

En este KWin NO llegan al journal (ni `journalctl -b` ni `--user`). Inútil para
depurar en caliente.

### ❌ FALSO: `supportInformation` expone propiedades QML

Añadir `readonly property string dbgX: ...` al `SceneEffect` (main.qml) y leer:

```
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.supportInformation kube-effect
```

Devuelve **cadena vacía** (medido 2026-11-25, KWin 6.8.3): ni las propiedades
declaradas en el QML del efecto ni su valor vivo llegan ahí.
`supportInformation` es un hook C++ de los datos de soporte del efecto
(`Effect::supportInformation()`), sin puente con el grafo de objetos QML. No
hay forma, desde QML puro, de leer estado del efecto por D-Bus.

### ✅ VERDADERO: pintar el estado en pantalla (`DebugOverlay`)

Como ni el journal ni el D-Bus son un canal de lectura, el único sitio fiable
es la pantalla: un `Text` anclado a la esquina del `ScreenView` que ensambla
el estado vivo (cámara, fondo, vídeo, geometría, op por cara). Eso es la clave
`DebugOverlay` (pestaña Advanced, default false, ADR-023), y así se
diagnosticó el bug del LOD de caras.

## E. Geometría y culling (QtQuick3D)

- La cámara mira hacia **-Z**. Un quad hijo de la cámara a `z = -d` muestra su
  cara **trasera** → con `BackFaceCulling` desaparece. Usar `Material.NoCulling`
  para quads colgados de la cámara.
- Hoja 2D (2 escritorios): doble cara; DOS quads `NoCulling` (uno por
  escritorio, 0°/180°, separados ±`sheetGap`) para ver cada lado por delante
  (ADR-024).
- **Cilindro sin shader**: el cilindro es desarrollable (K=0), así que curvar el
  escritorio sobre él es isométrico (no estira). Se construye con
  `ProceduralMesh` (`import QtQuick3D.Helpers`): posiciones `(R·sin φ, t, R·cos φ)`
  con `φ = s/R`, UV `u = s/W`, `v = t/H`, y `θ = W/R`. Material estándar
  (`PrincipledMaterial.NoLighting` + `baseColorMap`) — **sin vertex shader**.
  El primitivo `#Cylinder` NO sirve (cilindro completo, UV propias, no un arco).
- Curvar el contenido sobre una superficie **no desarrollable** (K>0) SÍ estira →
  exige shader/teselado → fuera de alcance.

### ⚠️ OJO: los `PropertyChanges` de `states` son bindings que mata la primera escritura directa

Síntoma: con el efecto abierto, cambiar la forma / el nº de escritorios / R deja
la cámara apuntando al escritorio viejo (o con el radio del sólido viejo): 2→1
escritorios con yaw 170 no aplicó el nuevo clamp ±80 (se vio el dorso espejado),
2→3 dejó yaw 180 (Enter/click seleccionaban el escritorio 3, no el actual), y el
radio quedó 2616 en vez de 2080. Causa: los `PropertyChanges` de los `states` de
`CubeCameraController` (close/distant) crean **bindings vivos**, pero la primera
escritura directa (drag, flechas, rueda) los **MATA**; un cambio posterior de
entrada (shape/desktops/R/faceSize) ya no re-evalúa el `radius`/`rotation` del
estado. Fix: `resyncToState()` en `CubeCameraController` re-escribe
`rotation`/`radius` desde las fórmulas del estado activo, y `ScreenView` lo llama
en `onFaceCountChanged` / `onCylinderActiveChanged` / `onCylinderRadiusChanged` /
`onFaceSizeChanged` y en `onCurrentDesktopChanged` (un desktop removido cae en
vecino). Idempotente mientras el binding sigue vivo, y sobrevive a su muerte: el
próximo flip de estado (cada deactivate/activate) reconstruye el `PropertyChanges`.
**Patrón general para cualquier estado futuro**: si un estado deriva de entradas
que pueden cambiar con el efecto abierto, re-sincroniza explícitamente; nunca
confíes en que el binding del `PropertyChanges` se re-evalúe solo.

## G. KConfigXT y formato

- **Enum = ENTERO en kwinrc** (p. ej. `Background=0`). Un string rompe el
  entorno (`GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`). Grupo `[Effect-kube-effect]`.
- Renombrar la CLAVE de un enum (no solo las choices) evita migrar índices:
  `BackgroundImageMapping=1` queda huérfano y se ignora en vez de convertirse en
  `Flat`. Cambia la clave cuando cambie el significado de los índices.
- `make check` compara con el ÍNDICE: ejecutar `qmlformat -i`, luego `git add -A`,
  luego `make check` (si no, el `git diff` da "falso rojo").
- El KCM genérico (`kcm_kwin4_genericscripted`) auto-genera el formulario desde
  `main.xml` si falta `config.ui`; con `config.ui` lo carga tal cual.

## I. KCM genérico: UI dinámica sin C++

El KCM genérico solo carga `contents/config/main.xml` y `contents/ui/config.ui`
con QUiLoader: no hay `config.qml` ni lógica, y `KConfigDialogManager` no admite
dependencias entre entries (solo deshabilita los `immutable`). Aun así **QUiLoader
respeta el bloque `<connections>` de Qt Designer**, así que la UI puede reaccionar
a un combo (es lo que hace el KCM oficial del cubo KDE).

Snippet que funciona (verificado cargando el .ui con QUiLoader en
`scripts/check-ui.py`):

```xml
<connections>
  <connection>
    <sender>kcfg_Background</sender>
    <signal>currentIndexChanged(int)</signal>
    <receiver>bgModeStack</receiver>
    <slot>setCurrentIndex(int)</slot>
  </connection>
</connections>
```

- `kcfg_Background` lo rellena KConfigDialogManager con el entero guardado en
  kwinrc; ese cambio dispara la conexión, así que la página inicial la fija el
  valor guardado (no el `currentIndex` del .ui).
- Las páginas del `QStackedWidget` van EN EL ORDEN DEL ENUM (0 Color, 1 Imagen,
  2 Degradado).
- **Limitación**: el combo emite un `int`, que solo encaja con slots `int`
  (`setCurrentIndex(int)`). Para alternar `setEnabled(bool)` harían falta radio
  buttons (o un grupo excluyente), no un combo.
- Un `kcfg_<Entry>` = un único widget: el mismo entry no puede repetirse en dos
  páginas. Los campos comunes (p. ej. `BackgroundColor`: color sólido, primer
  color del degradado y respaldo de la imagen) van fuera del stack.

**Dónde está esto en upstream** (verificado en el código):

- `GenericScriptedConfig`: `plasma/kwin/src/kcms/common/genericscriptedconfig.cpp`
  — carga **solo** `contents/config/main.xml` (KConfigLoader) y
  `contents/ui/config.ui` (QUiLoader). No existe `config.qml` ni `config.js` en
  Plasma 6.0–6.6.
- `KConfigDialogManager`: `frameworks/kconfigwidgets/src/kconfigdialogmanager.cpp`
  — no implementa dependencias entre entries; solo deshabilita los `immutable`.
- `kcfg.xsd` no tiene atributos `enabled`/`visible`/`depends`.
- KCM oficial del cubo KDE:
  `kdeplasma-addons/kwin/effects/cube/kcm/cubeeffectkcm.ui` — usa este mismo
  patrón `<connections>` con radio buttons.

Guardas del repo:

- `scripts/check-schema.py` valida que cada `<connection>` apunte a widgets
  existentes (QUiLoader **descarta en silencio** una conexión con typo) y recorre
  las páginas del `QStackedWidget` (cada página es un `QFormLayout`) como celdas
  del formulario, detectando celdas solapadas.
- `scripts/check-ui.py` carga el `.ui` con QUiLoader (lo mismo que hace el KCM),
  fija cada índice del combo y comprueba que la página del stack sigue (1→1, 2→2,
  0→0); sin `<connections>` o con receiver mal escrito → desync.

## H. Flujo de prueba recomendado

1. Editar QML.
2. `./scripts/kwin-nested-test.sh` (KWin anidado aislado, nunca tu sesión).
3. Verificar el cubo en la ventana WL-0 (Meta+K ahí, o `toggleEffect` por D-Bus).
4. Iterar. NUNCA reiniciar la sesión real del usuario para probar.

## I.b. Atajo de teclado: KGlobalAccel manda, no el KCM

**❌ FALSO: poner el atajo en `main.xml` + `KKeySequenceWidget` lo hace configurable.**

`KConfigDialogManager` **sí** sabe usar `KKeySequenceWidget` (mapea la clase a la propiedad
`keySequence` y engancha su señal `keySequenceChanged`), pero no sirve aquí:

- `ShortcutHandler` (`plasma/kwin/src/scripting/shortcuthandler.cpp`) registra con
  `KGlobalAccel::self()->setShortcut(action, {m_keySequence})` y **Autoloading**: el valor
  guardado en `kglobalshortcutsrc` tiene precedencia sobre el `sequence` del QML.
- `sequence` es inmutable tras construir el handler: `"ShortcutHandler.sequence cannot be
  changed"`. Un binding a `configuration.X` solo valora el atajo por defecto al crear el
  handler, y aun así perdería contra el valor ya guardado.

**✅ VERDADERO: el atajo se edita en Preferencias del sistema → Atajos de teclado → KWin.**

Es la única fuente persistente. El efecto declara `name` (nombre de la acción en
`kglobalshortcutsrc`), `text` (etiqueta traducida) y `sequence` (default). En el KCM del
efecto solo se pone un `QLabel` con la ruta; ningún efecto scripted upstream duplica el atajo
en su `config.ui`.

## J. Arnés de test anidado (qué cambió)

- El arnés **apaga todos los efectos del host** en el anidado: reescribe los
  `*Enabled` de `[Plugins]` con awk y deja solo `kube-effectEnabled=true`.
  `KUBE_NESTED_KEEP_EFFECTS="blur,screenshot"` conserva los que indiques
  (`screenshot` hará falta para thumbnails/wallpapers reales). Motivo: menos
  GPU/CPU y menos ruido en las pruebas.
- Los efectos **builtin** (screenedge, slidingpopups, sessionquit…) los carga
  KWin siempre y **no se pueden apagar**.
- Verificación por D-Bus del anidado:
  `org.kde.kwin.Effects.isEffectLoaded <id>`, con el bus propio en
  `${TMPDIR:-/tmp}/kube-effect-nested-$(id -u)/nested.addr`.
- El KCM del **host no afecta** al anidado: se configura dentro del anidado
  (System Settings) o editando
  `${TMPDIR:-/tmp}/kube-effect-nested-$(id -u)/config/kwinrc`
  (`[Effect-kube-effect]`).
- **Raíz del arnés privada (2026-11-26)**: config, data, logs, pid y addr viven
  en `${TMPDIR:-/tmp}/kube-effect-nested-$UID` (0700, dueño verificado; symlink
  o ruta ajena = aborta, nunca se sigue). Sustituye a la antigua ruta fija
  `/tmp/kube-effect-test-config`, que cualquier usuario local podía pre-crear o
  enlazar para secuestrar la config del anidado o hacer que el `rm -rf` de
  limpieza borrase a través del symlink. La raíz **se reusa** entre lanzamientos
  (como antes) y solo se borra cuando el arnés para su propio anidado
  (`Ctrl+C`); con `--no-follow` el anidado queda vivo y el árbol persiste.
- El efecto instalado se refresca con
  `kpackagetool6 --type KWin/Effect --upgrade package/` (el arnés ya lo hace).
- `--no-native` reproduce la experiencia **sin compilar** (nada de `make native`,
  `prefix.sh` ni `kcmshell6`): sirve para comprobar que el efecto QML está completo
  sin el lado nativo y para ver la diferencia con el anidado compilado.
- **El engranaje del efecto NO cambia al compilar**: el botón Configurar abre
  siempre `config.ui` (KCM genérico) porque la metadata del efecto sigue apuntando a
  `kcm_kwin4_genericscripted` (KF6 no hace fallback, ADR-011). El KCM nativo aparece
  como módulo aparte en Preferencias → Gestión de ventanas → «Kube Effect Plus».
- **Ruido benigno del anidado** (no son bugs del efecto, no perseguirlos):
  `Activated service 'org.kde.KSplash' failed` (no hay splash en la sesión
  anidada), `kf.coreaddons ... explicitly states an 'Id' in the embedded
  metadata` (aviso de metadata de un plugin KF6) y `qt.qpa.services: Failed to
  register with host portal ... App info not found for 'kcm_kube_effect_plus'`
  (el KCM nativo lanzado dentro del anidado no puede registrarse en el portal
  del host).

- **Wallpaper de prueba en el anidado (2026-11-27)**: la estructura real del
  appletsrc medida en Plasma 6.8.3 (host, solo lectura) es un bloque
  `[Containments][N]` con `wallpaperplugin=org.kde.image` y las claves del
  plugin en `[Containments][N][Wallpaper][org.kde.image][General]` → `Image=`
  (URL `file://` con ruta absoluta). Trampeos:
  * el id del plugin es `org.kde.image`, **no** `image`
    (`ls /usr/share/plasma/wallpapers/`);
  * la clave es `Image` (`type="String"` en
    `/usr/share/plasma/wallpapers/org.kde.image/contents/config/main.xml`); no
    existe `url`;
  * **no hay claves por escritorio virtual** (`Image1`/`Desktop1` no existen):
    Plasma 6.8.3 sigue sin admitir un wallpaper por escritorio (bug upstream
    155150 abierto; comprobado también en el QML del plugin, que no itera
    escritorios). El único truco conocido es por ACTIVIDADES (un containment por
    actividad), inservible aquí: el cubo rota escritorios de UNA actividad. El
    arnés usa un patrón direccional único
    (`scripts/make-test-wallpaper.py`, PNG generado en la raíz privada, nunca
    commiteado) y ventanas maximizadas `E1..EN` por escritorio
    (`scripts/test-wallpaper-label.py`) para identificar cada cara;
  * el containment de ESCRITORIO es el bloque con `formfactor=0` (los paneles
    traen `formfactor=2`; medido en el host);
  * plasmashell **no relee ediciones externas** del appletsrc en caliente: el
    arnés lo lanza una vez (etapa 1) para que él mismo escriba su containment de
    fábrica — nunca adivinar el `id` ni el vínculo con la actividad —, lo para,
    parchea con `kwriteconfig6` (varios `--group` = grupos anidados; produce
    `[Containments][N][Wallpaper][org.kde.image][General]` idéntico al del host)
    y lo relanza (etapa 2). Validado con `kreadconfig6` (round-trip de la ruta)
    y con `configparser` estricto de Python sobre el fichero generado.

## K. Ficha rápida de comandos

```bash
make check                      # qmllint (allowlist) + qmlformat + check-schema + check-ui + check-constants + json/yaml
make lint                       # make check + SonarQube en localhost:9000 (requiere .sonar-token y kkube-sonar)
kpackagetool6 --type KWin/Effect --upgrade package/   # instala/actualiza el efecto
./scripts/kwin-nested-test.sh   # arranca el KWin anidado
ROOT="${TMPDIR:-/tmp}/kube-effect-nested-$(id -u)"   # raíz del arnés (0700)
kill $(cat "$ROOT/nested.pid")                       # para el anidado
DBUS_SESSION_BUS_ADDRESS=$(cat "$ROOT/nested.addr") \
  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kube-effect
```

## L. KCM nativo y prefijo privado

### ❌ FALSO: declarar `X-KDE-ConfigModule` al nativo y que caiga al genérico si no está compilado

KF6 no hace fallback (`plasma/kwin/src/kcms/common/effectsmodel.cpp`): si el
módulo declarado no existe, el botón Configurar queda roto. Por eso la metadata
apunta SIEMPRE a `kcm_kwin4_genericscripted` y el nativo es un KCM aparte
(`kcm_kube_effect_plus`).

### ❌ FALSO: instalar el KCM en `~/.local/share/kservices6` y que aparezca solo

No. `systemsettings` usa `KPluginMetaData::findPlugins` sobre los Qt plugin
paths; `~/.local/lib/qt6/plugins` no se escanea sin `prefix.sh` (o
`QT_PLUGIN_PATH`+`XDG_DATA_DIRS` limitados al proceso).

### ❌ FALSO: instalar el KCM en `~/.local` y esperar que aparezca en Preferencias

No aparece. `systemsettings` solo ve los módulos de los Qt plugin paths
(`KPluginMetaData::findPlugins`); `~/.local/lib/plugins` no está ahí, así que el
`.so` existe pero nadie lo escanea. La única vía con prefijo privado es
`prefix.sh` (exporta `QT_PLUGIN_PATH`/`XDG_DATA_DIRS`) + `kcmshell6` /
`systemsettings`.

### ✅ VERDADERO: `make native-install` (prefijo `/usr`) sí sale en Preferencias

Prefijo `/usr` → `/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so`,
que ya está en los plugin paths por defecto: **Preferencias → Gestión de
ventanas → «Kube Effect Plus»**. Verificado con staging, sin root:
`DESTDIR=<stage> cmake --install native/build-system` deja exactamente
`<stage>/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so`
(`build-system` es el árbol que configura `--system`, `KDE_INSTALL_USE_QT_SYS_PATHS`).

### ✅ VERDADERO: prefijo privado + `prefix.sh` + `kcmshell6` para desarrollo sin root

El KCM lo dice en su propia página: si `metaData().fileName()` no empieza por
`/usr`, la sección «Instalación nativa» muestra el aviso de instalación de
usuario (y siempre la línea `make native-install`), en vez de dejar al
usuario buscando el módulo que no sale en Preferencias. El target compila como
el usuario que lo lanza y solo llama a `sudo` en `cmake --install`; por eso no
lleva `sudo` delante ni deja artefactos de root en el árbol de build.

### ✅ VERDADERO: `QtQuick.Shapes.RadialGradient` para degradado radial sin shader

Expone `centerX/centerY/centerRadius/focal*` y `stops`. Deja de caer a vertical.

### ✅ VERDADERO: versión estampada + stamp JSON para detectar ABI desactualizada

`native-stamp.json` (`plasma`, `qt`, `pkg`, `built`, `prefix`, `source`) escrito
por `build.sh`; el `.so` se estampa con `KUBE_PLASMA_VERSION`, `KUBE_QT_VERSION`,
`KUBE_PKG_VERSION`. `source` es la raíz del repo, y existe para que el KCM
imprima el bloque de comandos con la ruta real en vez de un placeholder (un
stamp viejo sin `source` no rompe nada: el bloque avisa y pone una ruta de
ejemplo).

### ❌ FALSO: el `BackgroundImageFit` del usuario vale también para la cúpula 360

Síntoma: el vídeo 360 «se ve cortado» — falta cielo y suelo y el horizonte
salta al girar; con Contain aparecen bandas negras arriba y abajo dentro de la
esfera. Causa: la cúpula muestrea el mismo `VideoOutput` que pinta la capa 2D,
y ese item llevaba el `fillMode` del fit del usuario. Cover
(`PreserveAspectCrop`) recorta el frame para llenar el item (un equirect 2:1
en pantalla 16:9 pierde franjas superior/inferior); Contain
(`PreserveAspectFit`) cartonea con barras negras. Como textura de la esfera,
ambas deforman el panorama: la envoltura la hace la geometría, no el ajuste.
Fix: propiedad `dome` en `HullVideo.qml` — con Equirect + girar el `fillMode`
es `Stretch` (fotograma completo); el fit solo aplica a la capa plana.
`scripts/check-video-dome.py` (retirado, sección P) exigía `fillMode == Stretch` en el caso 360.
Medido 2026-11-25 con clip 608×304. (ADR-020, corrección.)

### ⚠️ OJO: delegate de SceneEffect evaluado una vez

Síntoma: el cubo nunca aparece tras crear el escritorio nº 3 con el efecto ya
cargado — el PlaceholderView queda clavado (y al inverso: con 2 escritorios
sigue vivo el ScreenView). Causa: `delegate` se resuelve UNA vez por
SceneEffect; un binding con `Qt.createComponent(...)` sobre
`Workspace.desktops.length` no vuelve a evaluarse, así que la alternativa
placeholder/cubo no cambia nunca. Fix (ADR-022): dos `Component` inline
(`placeholderComponent`, `cubeComponent`) y `delegate:` enlazado a
`readonly property int desktopCount: Workspace.desktops.length` — al
re-evaluarse el binding, KWin **recrea los SceneViews** cuando cambia el
delegate. No sirve `reconfigureEffect` ni timers: la recreación es del
propio SceneEffect al ver otro componente. Verificado en la fuente de KWin
(`QuickSceneEffect`: los SceneViews se recrean cuando cambia el delegate) y con
`make check` (qmllint); **confirmación manual en el anidado pendiente** (pasar
de 2 a 4 escritorios con el efecto cargado).

> **SUPERSEDED por ADR-024 (2026-11-25)**: el gate `desktopCount < 3 ?
> placeholder : cube` ya no existe — `PlaceholderView.qml` se retiró y el
delegate de `main.qml` es **único** (`ScreenView`), porque `Cube` cambia solo a
> hoja con <3 escritorios. La lección sigue viva (el delegate se evalúa una vez
> por SceneEffect: si mañana volviera a haber dos componentes, el binding sobre
> un `count` reactivo sigue siendo obligatorio), pero el código que describía
> este apartado ya no está en el repo.

### ⚠️ OJO: `Number(null) === 0` (el vacío no es el suelo)

Síntoma: un valor vacío del KCM (`null` o `""` antes de guardar) se comporta
como el mínimo del rango en vez del default: `FaceOpacity` vacío → 0.1
(caras casi invisibles), `FaceFadeMs` vacío → 0 ms (corte seco). Causa:
guardar solo con `!isFinite(Number(value))`; en JavaScript `Number(null)` es
`0` y `Number("")` es `0`, ambos finitos, así que el default nunca se
alcanza y el clamp deja pasar el suelo. Fix (ADR-022): en `constants.js`
(`faceOpacity`, `faceFadeDuration`, `dimOpacity`, `gradientStopPosition`)
tratar `value === null || value === ""` como no-numérico → default de la
rama activa; `scripts/check-constants.qml` lo clava (`face(rest null -> 1)`,
`fade(null) -> 120`, `dim(on, null) -> 0.4`, `stop(null) -> 0.5`).

## M. QtQuick3D: pintado, orden y enums

### ⚠️ OJO: NUNCA hardcodear los ints de `Material.CullMode`

En Qt 6.12.1 el enum vale `BackFaceCulling = 1, FrontFaceCulling = 2,
NoCulling = 3` (medido en
`/usr/include/qt6/QtQuick3D/6.12.1/QtQuick3D/private/qquick3dmaterial_p.h`).
Un `2` hardcodeado habría dado `FrontFaceCulling` — el cull **opuesto** al
buscado (mostrar solo la pared interior en vez de la piel exterior). Pasa
siempre los enums simbólicos `Material.X`. La semilla `cylinderCullMode` de
`constants.js` devuelve tokens (1/0) y se mapea simbólicamente por eso; el
runtime ni siquiera la usa hoy (`faceCullMode` está clavado a
`Material.NoCulling`, ADR-025 pt.12 / ADR-026).

### ⚠️ OJO: `DefaultMaterial` con `diffuseMap: Texture { sourceItem }` entra SIEMPRE en la pasada transparente

Síntoma: con `opacity === 1` las caras igual se solapaban (la pared interior se
pintaba sobre la frontal). Causa: el motor marca transparencia cuando la textura
del item capturado tiene canal alfa (`prepareImage`, caso `Type::Diffuse` en
`qssglayerrenderdata.cpp`); el grab de un `DesktopView` la tiene siempre, así que
**aunque `opacity` valga 1** la cara acaba en la pasada transparente. Y esa pasada
ordena por el **centro del bbox del objeto en mundo proyectado sobre el eje de
visión** (`getCameraDistanceSq` usa `worldCenterPoint =
globalTransform(bounds.center())`, medido en `qssglayerrenderdata.cpp` de Qt
6.12.1): las caras que comparten origen (0,0,0) **empatan** → orden arbitrario.
Fix en ADR-026: malla re-centrada en el nodo (cada arco lleva su radio en la
`position`, N centroides distintos como el polígono) + `PrincipledMaterial` con
`alphaMode` explícito (ver abajo). Con `PrincipledMaterial` el `baseColorMap` NO
dispara transparencia (el tipo `BaseColor` se salta a propósito), así que la
pasada la decide el umbral, no el contenido.

### ⚠️ OJO: `alphaMode: Mask` descarta alpha<cutoff y pinta el resto OPACO escribiendo profundidad

### ❌ FALSO: "180° sobre X" es el espejo que deja un anillo de tapas en su sitio (ADR-027 enmienda 2)

La tapa inferior se construye como "la MISMA malla girada 180°" y se documentó
`eulerRotation.x: 180` "mandando α → −α" sobre un conjunto de azimuts
invariante bajo α → −α. Cada premisa suelta era cierta; la combinación, no:
**una rotación 180° sobre X manda (x,z) → (x,−z), es decir azimut α → 180°−α**,
que NO es simetría del anillo de esquinas (sus aristas largas abrazan las
normales de cara {0°,120°,240°} y sus cuerdas cortas los huecos
{60°,180°,300°}); el resultado es el anillo GIRADO MEDIO TICK: vértices a 928
sobre planos de cara a 472 (la tapa "atravesaba el sólido") y frontera del
hueco caída de 928 a 472 ("no tapa el hueco"). El giro de 180° que SÍ respeta
el anillo y vuelca la normal es **sobre Z** ((x,z) → (−x,z), α → −α). Truco
transferible: cuando una malla compuesta "se ve igual por el otro lado" es una
premisa de diseño, medirla con píxeles — renderizar la malla rotada y SIN
rotar y comparar siluetas (gate de píxeles retirado, sección P; variantes v3/v4: con X,
78–220 celdas de diferencia; con Z, 0 en 14 filas del barrido). Un razonamiento
solo con conjuntos de azimuts no basta: hay que comprobar qué mapa implementa
CADA eje.

### ⚠️ OJO: en un gate de píxeles, el color de prueba no puede chocar con los colores del stub

La tapa "azul puro" del reporte del usuario es píxel-idéntica al azul del
escritorio 3 del stub compartido (gate de vídeo retirado, sección P): la pared interior de
esa cara alimentaba el contador "fuera de silueta" con 218 falsos positivos.
Los colores de un gate deben ser clases DISJUNTAS de todo lo demás en escena
(aquí: tapa naranja #ff8000; el fondo del casco, negro; el marcador del
contenido, magenta/cian — y las mezclas al 80 % de opacidad tienen que seguir
dentro de su clase, que es lo que fija la tabla `classify()` del
`--selftest`).

`Mask` descarta los fragmentos con alpha < `alphaCutoff` (el escritorio se sigue
viendo por los huecos de la textura de cara) y pinta el resto **opaco escribiendo
profundidad**: un arco lejano no puede quedar encima de uno cercano ni aunque el
orden falle. `SetToOpaque` **no existe** en Qt 6.12: el enum es
`AlphaMode { Default, Mask, Blend, Opaque }` (medido en
`qquick3dprincipledmaterial_p.h` / `qquick3dspecularglossymaterial_p.h`). Ojo:
`Opaque` (el «SetToOpaque» histórico) **pinta de negro los huecos** — ignora el
alpha del mapa y borra el escritorio que se ve a través de la cara (medido,
ADR-026) — por eso el reposo es `Mask`, no `Opaque`. `alphaCutoff` se fija
explícito en `0.5` (no depende del default de Qt, para que un cambio de motor no
mueva el borde duro/suave de los huecos). El `Mask` queda solo en las caras
cilíndricas en reposo: `faceOpacity < 0.99 || cylinderMesh === null → Blend`
(polígono y hoja nunca tuvieron solape y su look virgen manda, ADR-023).

## N. KWin 6: modelo de ventanas y testing (PySide6 + stubs)

### ⚠️ OJO: `Window.internalId` es QUuid en KWin 6 → el wId nulo de `WindowThumbnail` es `""`, no `0`

Verificado en `/usr/include/kwin/window.h` (`\qmlproperty uuid Window::internalId`,
`Q_PROPERTY(QUuid internalId ...)`) y `/usr/include/kwin/effect/effectwindow.h`
(`QUuid internalId() const`). Por eso el valor de liberación del `wId` de
`WindowThumbnail` es **cadena vacía** (`""`, el QUuid nulo), que desengancha el
thumbnail y libera su captura; un `0` entero no convierte a QUuid y **no libera**
la captura. En `DesktopView.qml`:
`wId: model.window ? model.window.internalId : ""`.

### ⚠️ OJO: `qInstallMessageHandler` ANTES de `setSource` DEADLOCKEA (PySide6 + QML)

Medido con faulthandler: el hilo main se bloquea en `QQmlTypeLoader::getType`
(`setSource`) mientras el hilo QML espera el GIL para entregar su `qWarning` de
parseo (hang de ~12 s, traza bajo `QWaitCondition`). Sin handler instalado, este
PySide6 **se traga en silencio** todos los mensajes QML (ni logging ni stderr los
ven): un `TypeError` silencioso deja bindings rotos con el test en verde. Fix
(gate de vídeo retirado, sección P): carga de **calentamiento sin handler** (parsea
todos los tipos y llena la caché del motor), **después** se instala el handler y
se crea la vista real (los mensajes restantes llegan al hilo main), y **un
subproceso por escenario** (un segundo `QGuiApplication.exec()` tras el primer
`exit()` nunca retornó).

### ⚠️ OJO: un `Component` hijo de `ListModel` se parsea como `ListElement` y rompe

En el stub de `org.kde.kwin` para los tests de render, declarar el escritorio/la
ventana como `Component { ... }` hijo del `ListModel` hace que QML lo interprete
como `ListElement` (y falla). Fix: inyectar **objetos reales** con
`Qt.createQmlObject` (desktops con `x11DesktopNumber`, parentados al singleton
para que sobrevivan al binding) y `append({ "desktop": desktop, ... })` — el role
lleva un `QObject` real que los delegates leen de vuelta (`CubeFace` declara
`required property QtObject desktop`; `Cube.desktopAzimuth` lee
`.x11DesktopNumber`, que con `null` tiraba un `TypeError` matando el binding sin
fallar el test). Ver `scripts/qml_check_harness.py` (STUB_MODULE, `VirtualDesktopModel.qml`
y `WindowFilterModel.qml`).

## P. Gates de render retirados por coste (2026-11-27)

Tres gates dibujaban la escena real y se comparaban píxel a píxel:

| fichero | qué protegía |
|---|---|
| `scripts/check-cap-overlap.py` + `.qml` + `scripts/cap_overlap_oracle.py` | orden de pintado y silueta de las tapas (ADR-027 enmiendas 1 y 2) |
| `scripts/check-cylinder-overlap.py` + `.qml` | que la pared lejana no quedara encima de las caras (ADR-026) |
| `scripts/check-video-dome.py` | el vídeo 360 forzado a Stretch y la cúpula pintada (ADR-020) |

**Por qué se fueron:** cada pasada costaba minutos (un proceso hijo por pitch,
42 filas de grabs) y `check-video-dome` fallaba con la VRAM saturada, así que el
gate local se había convertido en la fuente de trabajo en vez del filtro. El
intentó intermedio —separar `check` rápido de `check-render` con disparo
automático si la geometría estaba tocada— funcionaba, pero seguía corriendo los
lentos en cuanto la geometría cambiaba, que es casi siempre que algo va mal.

**Qué se pierde:** el orden de pintado de tapas y cilindro vuelve a ser
invisible para las máquinas. La geometría sigue cubierta (offscreen, segundos):
`check-cap.py` + `cap_contract.py` (apotema/esquinas/vinding/UVs/malla compartida)
y `check-cylinder.py` + `check-cylinder-wiring.py`. La orientación de la tapa
inferior se comprueba a ojo con el marcador `CapContent=Arrow` (flecha +
cuadrante magenta) y con el wallpaper direccional del arnés.

**Cómo recuperarlos** (están en el historial, borrados en el commit que los
retiró):

```bash
git log --diff-filter=D --name-only -- 'scripts/check-cap-overlap.*' 'scripts/cap_overlap_oracle.py'
git log --diff-filter=D --name-only -- 'scripts/check-cylinder-overlap.*'
git log --diff-filter=D --name-only -- scripts/check-video-dome.py
# y resucitarlos desde ese commit padre:
git checkout <commit>~1 -- scripts/check-cap-overlap.py scripts/check-cap-overlap.qml \
    scripts/cap_overlap_oracle.py scripts/check-cylinder-overlap.py \
    scripts/check-cylinder-overlap.qml scripts/check-video-dome.py
```

El stub `org.kde.kwin` que compartían vive ahora en `scripts/qml_check_harness.py`
(`STUB_MODULE`, `write_stub_module`, `QML_ERROR_SIGNATURES`): lo usa
`check-cylinder-wiring.py`, que sí se queda.
