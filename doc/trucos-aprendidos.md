# Trucos aprendidos — qué NO funciona y qué SÍ

Bitácora de trampas del pipeline real (KWin 6 + Qt 6.12 + QtQuick3D, QML
`declarativescript`). Cada punto se verificó en la sesión real o en el KWin
anidado. Si algo aquí contradice un tutorial, gana esta lista: son hechos
medidos en ESTA máquina.

## A. Recarga de código (el que más tiempo costó)

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

Verificación automática: `scripts/check-video-dome.py` (en `make check`) carga el
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

### ✅ VERDADERO: exponer propiedades y leerlas por D-Bus

Añadir `readonly property string dbgX: ...` al `SceneEffect` (main.qml) y leer:

```
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.supportInformation kube-effect
```

Muestra el valor vivo (incluye `activated`, `visible`). Sirve para confirmar qué
versión está cargada (`animationDuration`) y qué config resuelve.

## E. Geometría y culling (QtQuick3D)

- La cámara mira hacia **-Z**. Un quad hijo de la cámara a `z = -d` muestra su
  cara **trasera** → con `BackFaceCulling` desaparece. Usar `Material.NoCulling`
  para quads colgados de la cámara.
- Hoja 2D (2 escritorios): doble cara; un quad `NoCulling` (o dos quads) para
  verla por delante y por detrás.
- **Cilindro sin shader**: el cilindro es desarrollable (K=0), así que curvar el
  escritorio sobre él es isométrico (no estira). Se construye con
  `ProceduralMesh` (`import QtQuick3D.Helpers`): posiciones `(R·sin φ, t, R·cos φ)`
  con `φ = s/R`, UV `u = s/W`, `v = t/H`, y `θ = W/R`. Material estándar
  (`PrincipledMaterial.NoLighting` + `baseColorMap`) — **sin vertex shader**.
  El primitivo `#Cylinder` NO sirve (cilindro completo, UV propias, no un arco).
- Curvar el contenido sobre una superficie **no desarrollable** (K>0) SÍ estira →
  exige shader/teselado → fuera de alcance.

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
  `/tmp/kube-effect-nested.addr`.
- El KCM del **host no afecta** al anidado: se configura dentro del anidado
  (System Settings) o editando `/tmp/kube-effect-test-config/kwinrc`
  (`[Effect-kube-effect]`).
- El efecto instalado se refresca con
  `kpackagetool6 --type KWin/Effect --upgrade package/` (el arnés ya lo hace).
- `--no-native` reproduce la experiencia **sin compilar** (nada de `make native`,
  `prefix.sh` ni `kcmshell6`): sirve para comprobar que el efecto QML está completo
  sin el lado nativo y para ver la diferencia con el anidado compilado.
- **El engranaje del efecto NO cambia al compilar**: el botón Configurar abre
  siempre `config.ui` (KCM genérico) porque la metadata del efecto sigue apuntando a
  `kcm_kwin4_genericscripted` (KF6 no hace fallback, ADR-011). El KCM nativo aparece
  como módulo aparte en Preferencias → Gestión de ventanas → «Kube Effect Plus».

## K. Ficha rápida de comandos

```bash
make check                      # qmllint (allowlist) + qmlformat + check-schema + check-ui + check-constants + json/yaml
make lint                       # make check + SonarQube en localhost:9000 (requiere .sonar-token y kkube-sonar)
kpackagetool6 --type KWin/Effect --upgrade package/   # instala/actualiza el efecto
./scripts/kwin-nested-test.sh   # arranca el KWin anidado
kill $(cat /tmp/kube-effect-nested.pid)               # para el anidado
DBUS_SESSION_BUS_ADDRESS=$(cat /tmp/kube-effect-nested.addr) \
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
