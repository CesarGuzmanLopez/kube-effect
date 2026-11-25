# Arquitectura — Kube Effect

Modelo técnico del efecto (QML puro, KWin `declarativescript`, QtQuick3D 6.12).
Cómo se compone la escena y cómo se construye cada forma.

## 1. Capas de la escena (de fuera a dentro)

1. **Cámara** (`PerspectiveCamera`): orbita el sólido; arrastre + rueda + teclado. igual como funciona actualmente la camara funciona como ya funciona en el cubo
2. **Casco (espacio alrededor)**: lo que se ve detrás/alrededor del sólido. Es el
   fondo (color, degradado, vídeo, imagen). Rodea la escena; el sólido deja verlo
   por los huecos entre caras.
3. **Caras**: N quads, uno por escritorio; cada uno lleva su **fondo de cara**
   (wallpaper escritorio real) + sus ventanas. la transparencia de estas caras es configurable
4. **Interior**: objetos decorativos en el centro (3D/2D, animados o estáticos,
   vídeos, imágenes).

No hay "piel": entre las caras no hay superficie que cierre la forma; se ve el
casco a través de los huecos (como el cubo de KDE).

## 2. Formas

### 2.1 Polígono (default)

- N caras planas en el perímetro de un N-gono regular. N = nº de escritorios.
- Cada cara es un quad rígido (sin curvatura). Se ven las aristas.
- Radio del polígono: `R = (0.5·anchoCara + 0.5·separación) / tan(π/N)`. La
  separación puede ser **negativa** (las caras se solapan, R encoge) hasta
  `-anchoCara` (R→0); positiva = huecos entre caras; 0 = pegadas.

### 2.2 Cilindro (isométrico, sin shader)

El cilindro es una superficie **desarrollable** (curvatura gaussiana K=0): un plano
se envuelve sobre él **sin distorsión**. Por eso el contenido del escritorio se
puede curvar sobre un cilindro sin estirarlo → **sin vertex shader**.

Geometría (arco de cilindro, eje Y, radio R, ancho de cara W, alto H):

```
φ(s) = φ0 + s / R          s ∈ [0, W]        (mapeo isométrico: arco = R·φ = W)
P(s,t) = ( R·sin(φ), t, R·cos(φ) )           t ∈ [0, H]
normal(s) = ( sin(φ), 0, cos(φ) )
UV:        u = s / W,   v = t / H
```

Relación clave: **θ = W / R** (si no se cumple, la textura se estira/comprime).
el radio dependera de la resolucion ratio de pantalla
Implementación en QML puro con **`ProceduralMesh`** (`import QtQuick3D.Helpers`,
Qt 6.6+):

- Segmentos: 32 (moderado) – 64 (arco grande/cerca). Crear la malla una vez; no
  regenerarla por frame si solo cambia la transformación.
- `ProceduralMesh` es sólo QML (suficiente aquí). Para máximo rendimiento/multi-
  pantalla, la alternativa sería `QQuick3DGeometry` en C++ (fuera del contrato
  QML-puro).
- `#Cylinder` primitivo NO sirve para un arco parcial con UV isométrica; es un
  cilindro completo con UV propias.

### 2.3 Hoja 2D (2 escritorios)

- Un quad plano doble cara: un escritorio por delante, otro por detrás.
- Sin interior.

## 2.4 Capas de ventana (z-index / separación) — cómo se aplicó

Cada ventana de una cara = un quad propio (con su `WindowThumbnail`) colocado en la
normal de la cara y **empujado hacia dentro** según su rango de apilado:

```
rank          = nº de ventanas de la cara con menor stackingOrder  (0 = la de arriba)
cap           = 150 px                                             (tope duro del stack)
maxLayerDepth = min(faceDistance * 0.5, cap)
fittedGap     = min(WindowLayerGap, maxLayerDepth / max(1, maxRank))
layerDepth    = (maxRank - rank) * fittedGap                       (la de arriba = 0)
position.z    = -(layerDepth + epsilon)                            (+z = normal hacia fuera)
```

El **velo (plate)** va detrás de la capa más profunda: `z = -(maxLayerDepth + 2)`.

### Cómo se aplicaria

- **Orden determinista**: un mapa `id → stackingOrder` + un contador `revision` que
  re-evalúa las posiciones. No depende del orden de creación de los delegates;
  además se conecta a `onStackingOrderChanged` para mantenerlo vivo.
- **LOD**: solo las caras cercanas al escritorio actual crean capas
  (`WindowLayerLodFaces`). Cada `WindowThumbnail` es una captura offscreen por
  frame, así que una capa que no se ve sigue costando GPU; las caras lejanas usan
  el compuesto plano.
- **Ventanas descartadas** (minimizadas, docks, ventana-wallpaper) → `nullWId`
  (desasocia el thumbnail y libera la captura; `visible: false` por sí solo NO lo
  hace). Cada capa descartada lleva `wId` nulo.
- **Dos lados** (`Material.NoCulling`): como las capas van metidas DENTRO, no
  sobresalen; las ventanas se ven a través. No hace falta un material de dos caras
  con culling.

### Consejos (trampas)

- **Empujar hacia el exterior del radio tangencialmente fuera- **Tope duro + paso repartido**: no hacer clamp por capa (aplana las profundas en
  un mismo plano y se pierde el orden). Repartir un paso menor conserva el orden y
  que el más profundo caiga justo en el tope.
- **Profundidad FIJA mientras gira**: animar el hueco producía un "pop" al parar.
  El stack se lee como un sólido rígido.
- **`plate` detrás de la más profunda**; si va delante, tapa las ventanas.
- **Crear capas solo en caras cercanas** (LOD): una capa oculta sigue costando una
  captura por frame.

## 3. Caras: fondo de cara (wallpaper real)

- El fondo de cada cara es el wallpaper REAL del escritorio (el mismo que el
  usuario tiene), capturado en QML: se captura la ventana de escritorio de Plasma
  (`WindowThumbnail` sobre la `desktopWindow` de esa pantalla) → textura.
- Sin shaders: es una textura estándar sobre el quad/cilindro.
- Encima van las ventanas de ese escritorio (composite o capas 3D).
- Multi-monitor: una captura por pantalla (`WindowFilterModel { screenName }`).

## 4. Casco: espacio alrededor

- Es el fondo de la escena (no la superficie del sólido). Modos:
    - **Color**: un `Rectangle` de color sólido DENTRO de la escena, detrás del
      `View3D` (nunca `window.color`, que pinta la superficie de la ventana; ver
      trucos).
    - **Degradado** lineal (arriba→abajo u horizontal): un `Rectangle` con
      `Gradient` DENTRO de la escena. `Radial` es **real** con
      `QtQuick.Shapes.RadialGradient` (expone `centerX/centerY/centerRadius/focal*`
      y `stops` en Qt 6.12); no cae a vertical. Sin shaders ni C++.
    - **Imagen / SkyBox**: si el mapeo es `Equirect` (panorámica 360) se usa
      `SceneEnvironment { backgroundMode: SkyBox; lightProbe: Texture { source } }`
      → **SkyBox**: entorno que envuelve la escena y gira con el centro. Si es
      `Flat`, se pinta como **quad plano** (fondo fijo), con `BackgroundImageFit`
      (`Cover`/`Contain`/`Stretch`, default `Cover`) para decidir cómo encaja
      la imagen plana. Ya no hay `Auto`: el usuario elige explícitamente
      (`BackgroundImageLayout`: `Equirect`/`Flat`).
    - **Vídeo** (`Background=Video`): el clip se pinta **igual que una imagen**,
      con dos caminos. `Equirect` + `BackgroundImageRotate` = 360: el
      `SceneEnvironment.SkyBox` usa `lightProbe: Texture { sourceItem }` sobre el
      `VideoOutput` (verificado en Qt 6.12: `Texture.sourceItem` es un
      `QQuickItem` y `VideoOutput` lo es; el `VideoOutput` vive oculto y
      QtQuick3D lo renderiza a una capa offscreen). Si no, capa plana
      fullscreen detrás del `View3D` con `BackgroundImageFit` en el
      `VideoOutput.fillMode` (`Cover`/`Contain`/`Stretch`).
      **El import de QtMultimedia está aislado** en `package/contents/ui/HullVideo.qml`,
      que `ScreenView.qml` carga con un `Loader`: si el módulo opcional no está,
      solo ese item queda en `Loader.Error` (aviso `qWarning` una vez) y el
      color de respaldo sigue pintando el casco. Un import de QtMultimedia en
      `ScreenView.qml` habría roto **todo** el efecto.
      El `MediaPlayer` (bucle infinito, `AudioOutput { muted: true }` —en Qt 6.12
      `MediaPlayer` no tiene `muted`) solo reproduce con `effect.visible`:
      `playing` está ligado a esa propiedad, y el item no se crea hasta la
      primera activación, así que no consume CPU en segundo plano.
      Atenuación al girar: capa plana → velo 2D `hullDim`; 360 →
      `probeExposure`, exactamente igual que la imagen (no hay lógica duplicada).
- **Orientación del degradado** (`BackgroundGradientRotation`, ADR-017; solo el
  casco degradado). `ScreenView.qml` pasa el yaw de la cámara
  (`cameraController.rotation.toEulerAngles().y`) como propiedad `yaw` a
  `HullGradient.qml`, que deriva el ángulo con `constants.js`
  (`gradientRotationAngle`): `Fixed` (0) lo deja quieto, `FollowCube` copia el yaw y
  `FollowCubeInverse` lo invierte. **Lineal**: la capa es un `Rectangle` con
  `Gradient` y un `Rotation` (transform) con `origin` en su centro; el rectángulo se
  sobredimensiona al diagonal (`Math.hypot(w, h)`) y se centra en el casco para que
  al girar no queden esquinas sin pintar. Los tres stops se remapean a la franja
  visible (`stopMargin`), así `Fixed` conserva el aspecto anterior. **Radial**:
  girar un radial centrado no se ve (es radialmente simétrico), así que se desplazan
  `focalX`/`focalY` sobre una circunferencia de radio `0.25 · max(w, h)` con ese
  ángulo; con `Fixed` el foco queda en el centro. En ambos casos la rotación es una
  **transformación** sobre objetos que ya existen: no se crea ni se destruye nada por
  frame, y el único binding por frame es el yaw que ya se calculaba para el cubo.
- **Atenuar al girar** (`DimWhileRotating`/`DimWhileRotatingAmount`) alcanza
  los cuatro modos de casco, pero por dos vías distintas: color, degradado e imagen plana
  usan el velo 2D (`hullDim`, un `Rectangle` negro entre el casco y el `View3D`);
  el SkyBox 360 usa `SceneEnvironment.probeExposure` = `constants.js`
  `skyBoxExposure(...)`, porque el entorno 3D no lo pinta la capa 2D y un velo
  delante del `View3D` taparía las caras. Con el SkyBox ya pintado el velo 2D
  queda apagado (solo cubre el color de respaldo mientras la sonda decodifica),
  así que nunca se atenúa dos veces el mismo fondo; ambos usan la misma señal de
  giro y un `Behavior` de 120 ms.
- **SkyBox no es un modo aparte**: es la variante 360 de "Imagen"
  (`SceneEnvironment.SkyBox`, no un quad).
- **Vídeo 360 = cúpula, no SkyBox** (ADR-019): Qt Quick 3D rechaza un
  `Texture.sourceItem` como `lightProbe` («Cannot use QSGTexture from
  Texture.sourceItem as light probe.»), así que un clip no puede envolver la
  escena con el entorno. Se pinta en una esfera vista desde dentro, hija de la
  escena con `position: camera.position` (sin heredar su rotación): radio
  50 × escala 100 = 5000, muy por dentro de `clipFar` y muy por fuera del cubo.
  La atenuación va con una segunda esfera negra justo dentro (alpha = 1 − expos).
- `BackgroundImageRotate`: solo aplica al mapeo equirect — gira con el centro
  (SkyBox) o queda fija como imagen plana. El mapeo `Flat` nunca gira.
- El fondo (color, degradado o imagen plana) se pinta con `Rectangle`/`Image`
  DENTRO de la escena, detrás del `View3D`, y con `visible: effect.visible`.
  `window.color` no se toca: pinta la superficie de la ventana y deja el fondo
  pegado al desactivar (ver `doc/trucos-aprendidos.md`).

## 5. Interior: objetos decorativos

- Nodo en el centro del sólido. Objetos 3D (primitivas `#Cube`/`#Cylinder`, modelos `.mesh`/`.glb`),
  2D (quads con imagen/HUD) o vídeo (`Video` sobre un quad).
- Animados por defecto; un objeto **estático** no debe heredar el giro del sólido
  (anclar al mundo, no al nodo que gira).
- Deshabilitado con 2 escritorios (hoja 2D) y en el placeholder (1).

## 6. Configuración

Las claves viven en `package/contents/config/main.xml` (KCM genérico). Enums se
guardan como ENTERO en kwinrc. Grupo `[Effect-kube-effect]`.

## 7. Distribución (QML puro, sin C++)

- `kpackagetool6 --type KWin/Effect` solo instala efectos **scripted/QML**
  (`~/.local/share/kwin/effects/<id>/contents/ui/main.qml`). Un `.so` dentro del
  paquete **no se carga**: `PluginEffectLoader` busca plugins binarios en
  `kwin/effects/plugins`, y los **KCM propios** en `kwin/effects/configs` (ambos
  en `${KDE_INSTALL_PLUGINDIR}`, p. ej. `/usr/lib/qt6/plugins/...`), **fuera del
  KPackage**.
- **No hay ABI estable** entre versiones de Plasma: KWin compara el IID y descarta
  los binarios de otra versión ("… was built for a different version of KWin and
  needs to be rebuilt"). Casos reales: **Better Blur** (taj-ny) soporta una sola
  versión de Plasma y avisa de recompilar tras actualizar KWin; **KDE Rounded
  Corners** se rompe tras cada update de KWin. Ambos distribuyen AUR/COPR/PPA/Nix
  con binarios por distro.
- **Flatpak no sirve** (el efecto se carga dentro del `kwin_wayland` del host) y
  **KDE Store solo entrega datos/QML**. Un efecto C++ "sin que el usuario
  compile" = paquete por distro y por versión de KWin + CI.
- Por eso este efecto es **QML puro** y se distribuye por KDE Store. Si alguna
  feature exige C++, iría a un repo nativo aparte con paquetes por distro
  (AUR `-bin`, COPR, PPA, OBS, Nix) y CI por versión de KWin; nunca un `.so`
  genérico ni dentro del KPackage.
- **Qué NO exige C++** (se queda en QML): degradado radial (`QtQuick.Shapes`),
  skybox, vídeo de fondo (`QtMultimedia`, módulo opcional aislado en
  `HullVideo.qml`), cilindro (`ProceduralMesh`), capas visuales. **C++ solo** para framebuffer real por escritorio, `EffectWindow`
  avanzado o `QQuick3DGeometry` de alto rendimiento. Decisión: seguir en QML y
  decidir C++ al llegar a la feature que lo exija.

## 7.1 Distribución nativa (opcional)

Además del QML puro, el paquete puede llevar **Kube Effect Plus**, un módulo
nativo opcional compilado bajo demanda desde `native/` (fuentes CMake). No es
necesario para que el efecto funcione: el menú QML (`config.ui` vía
`kcm_kwin4_genericscripted`) siempre está.

El paquete distribuible incluye una copia de esas fuentes en
`package/contents/native/` (sin `build*`, `*.o`, `CMakeFiles` ni `.cache`).
`native/` es la fuente de verdad: `make sync-package-native` la copia (lo hace
`make install` antes de `kpackagetool6`) y `make check` falla si divergen.
KWin no carga nada de ahí; existe para que quien instala desde KDE Store compile
Plus desde la copia instalada con `./build.sh` / `./build.sh --system`
(`build.sh` calcula todas las rutas desde su propia ubicación y no necesita el
`Makefile` del repo).

Estructura real:

```
native/
  CMakeLists.txt           # proyecto kube_effect_native: versiones + stamp
  kube-native-info.json.in  # versiones compiladas -> kube-native-info.json
  build.sh                 # configure + build + install + stamp + prefix.sh
  src/kcm/
    CMakeLists.txt         # kcoreaddons_add_plugin -> plasma/kcms/systemsettings
    kube_effect_kcm.h      # KubeEffectKcm : KCModule
    kube_effect_kcm.cpp    # diagnóstico, reconfigure y «Recargar compositor»
    kube_effect_reload.h   # helpers puros del reinicio (guarda anidado, comando)
    kube_effect_reload.cpp
    kube_effect_kcm.json   # metadatos del plugin (Id kcm_kube_effect_plus)
    tests/                 # unit test de kube_effect_reload (Qt Test, sin proceso)
```

- Módulo: `kcm_kube_effect_plus`, «Kube Effect Plus»,
  `X-KDE-System-Settings-Parent-Category: windowmanagement`, instalado con
  `kcoreaddons_add_plugin(... INSTALL_NAMESPACE "plasma/kcms/systemsettings")`.
  El `.so` lleva los metadatos embebidos: `KPluginMetaData::findPlugins`
  sobre los Qt plugin paths es todo el registro.
- Contenido (solo lo que QML no puede hacer):
  a. Versiones compiladas (`KUBE_PLASMA_VERSION`, `KUBE_QT_VERSION`,
     `KUBE_PKG_VERSION`), inyectadas con `add_compile_definitions`.
     Plasma se detecta con `find_package(KWin)` (`KWin_VERSION`, autoritativo);
     si no hay paquete CMake de KWin se ejecuta `kwin_wayland --version` en
     configure time. `KWindowSystem` no sirve: da la versión del framework KF6.
  b. Estado del stamp `~/.local/share/kube-effect/native-stamp.json`: si la
     versión de Plasma/Qt no coincide con la compilada, aviso destacado con
     «compilado para X, tienes Y → recompila» (etiqueta resaltada, sin diálogos).
  c. Dependencias de `features.json`: lee
     `kwin/effects/kube-effect/contents/config/features.json` con
     `QStandardPaths::locate(GenericDataLocation, …)` y pinta palomita/cruz por
     `requires` (mismos sondeos que `scripts/check-features.py`) + `notes` de las
     features que no cumplen.
  d. Aviso en negrita si `Background` (modo) no concuerda con los medios de
     kwinrc: modo Color con `SkyBox`/`BackgroundVideo` puesto (imagen que no se
     pinta, típico de kwinrc previo al rename del enum) o modo Imagen/Vídeo sin
     medio. Es el único diagnóstico que lee kwinrc directamente.
  e. Dos botones, con una línea que explica cuándo usar cada uno
     («Reconfigurar efecto: cambios de ajustes. Recargar compositor: cambios de
     código (KWin guarda el QML en caché).»):
     - **«Reconfigurar efecto»** → D-Bus
       `org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect("kube-effect")`,
       con el fallo visible en una etiqueta. Solo re-lee la config: **no**
       recompila QML.
     - **«Aplicar cambios de código»** → cierra la sesión, no reinicia KWin
       (2026-11-25, medido: el restart mata la sesión Wayland y el escritorio
       queda muerto). `KMessageDialog` de aviso con tres salidas: «Cerrar
       sesión» → `org.kde.Shutdown /Shutdown org.kde.Shutdown.logout` (la misma
       llamada del menú de Plasma: las apps reciben su cierre normal y SDDM
       autologin devuelve la sesión); «Copiar comando» → deja `systemctl --user
       restart plasma-kwin_wayland.service` en el portapapeles para un TTY;
       Cancelar no hace nada. No se usa `reconfigureEffect` (solo re-lee la
       config) ni `kwin_wayland --replace` (X11; en Wayland empeora). **Una
       guarda**: si `WAYLAND_DISPLAY` contiene `kube-effect-nested` o
       `KUBE_NESTED=1` (el arnés exporta ese flag y usa ese socket; KCM abierto
       dentro de `scripts/kwin-nested-test.sh`) se niega y responde «No
       disponible en el compositor de pruebas: reinícialo cerrando y volviendo
       a lanzar el script.».
  f. El comando `bash native/build.sh` solo se muestra con
     `-DKUBE_SHOW_BUILD_COMMAND=ON` (default OFF, ver ADR-015).
- **Dos instalaciones del mismo KCM**, con comportamientos distintos:
  1. **De sistema** (`make native-install`, prefijo `/usr`): el `.so` queda
     en `/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so`,
     dentro de los Qt plugin paths por defecto. `KPluginMetaData::findPlugins`
     lo ve y System Settings lo lista en **Preferencias → Gestión de ventanas →
     «Kube Effect Plus»** sin ninguna variable de entorno.
  2. **De usuario** (`make native`, prefijo `~/.local`, sin root): el `.so` va a
     `~/.local/lib/plugins/...` + `prefix.sh` (lo genera ECM en el build y
     `build.sh` lo copia a `~/.local/share/kube-effect/prefix.sh`), que exporta
     `QT_PLUGIN_PATH`/`XDG_DATA_DIRS` limitados al proceso. Sin ese
     `prefix.sh` **no se descubre**: `~/.local/lib/plugins` no está en los Qt
     plugin paths de la sesión, así que Preferencias no lo enseña y hay que
     abrirlo con `prefix.sh` + `kcmshell6`/`systemsettings`.
  `KDE_INSTALL_USE_QT_SYS_PATHS` solo se fuerza cuando el prefijo es `/usr`; los
  QTPLUGINDIR absolutos de Qt exigen root y ADR-012 lo prohíbe para la
  instalación por defecto.
- El KCM dice en qué caso está: la sección «Instalación nativa» muestra siempre
  la línea de instalación de sistema y, solo si `metaData().fileName()` **no**
  empieza por `/usr` (`KubeInstall::isSystemInstall`, /usr cubre /usr/local),
  un aviso destacado de que el módulo es solo del usuario y no sale en
  Preferencias. Debajo, la sección **«Comandos»** ofrece un bloque
  `QPlainTextEdit` read-only (fuente fija, sin `wordWrap`) con dos variantes
  según el campo `source` del stamp: desde el repo, `cd <repo>` + `make native`
  + `make native-install` + `make native-status`; desde la copia del paquete,
  `cd ~/.local/share/kwin/effects/kube-effect/contents/native` + `./build.sh` +
  `./build.sh --system` + `./build.sh --clean`. El botón **«Copiar comandos»**
  (`QApplication::clipboard()`) pega la secuencia sin escribir rutas. Si el
  stamp es antiguo y no tiene `source`, se imprime la ruta de la copia instalada
  con un aviso de que hay que ajustarla.
- `native-stamp.json` (`plasma`, `qt`, `pkg`, `built`, `prefix`, `source`) lo
  escribe `build.sh` con las versiones que CMake registró en
  `kube-native-info.json`, no con una consulta posterior: el stamp no puede
  mentir sobre el `.so`. `source` es la ruta absoluta desde la que se ejecutó
  `build.sh`: la raíz del repo cuando hay `Makefile` + `package/metadata.json`
  al lado, o la propia carpeta `contents/native` cuando corre desde la copia
  instalada. Alimenta el bloque de comandos del KCM; los stamps viejos sin ese
  campo siguen siendo válidos (el KCM cae al placeholder).
  `make native-status` compara ese stamp con el sistema y devuelve 1 si falta o
  no coincide.
- Comandos: `make native` (privado, sin root; se prueba con `prefix.sh`),
  `make native-install` (sistema; es el único que aparece en Preferencias →
  Gestión de ventanas → «Kube Effect Plus»), `make native-clean`,
  `make native-status`. El target `native-install` compila como el usuario que
  lo lanza y solo invoca `sudo` en `cmake --install` (la contraseña se pide una
  vez, al final): no hay que anteponer `sudo` y el árbol de build no queda con
  artefactos de root.
- Arnés (`scripts/kwin-nested-test.sh`): compila `make native` antes de arrancar
  y aborta si falla; si el KCM está en el prefijo privado, lo abre con
  `kcmshell6 kcm_kube_effect_plus` en el bus y el `XDG_CONFIG_HOME` del anidado, así
  que escribe en el kwinrc del test, nunca en el del host.
- Qué NO rompe si falta el `.so`: nada del efecto QML. Kube Effect Plus es
  independiente (ver ADR-011/012).

## 7.2 features.json

`package/contents/config/features.json` — catálogo de features y dependencias.

- Campos: `id`, `label`, `requires[]`, `native` (bool), `notes`,
  `status` (stable/planned/needs-native), `since`.
- Consumidores: `scripts/check-features.py` (validación del JSON, también en
  `make check`) y `scripts/check-deps.sh` / `make deps` (sondeo del sistema,
  informativo) y el KCM nativo (palomitas de dependencias). **El QML no lo lee**
  (sin validación en runtime ni avisos en pantalla).

## 8. Verificación

- `make lint` (estático).
- Nativo en prefijo privado: la página avisa de que es una instalación de
  usuario; `DESTDIR=<stage> cmake --install native/build-system` (prefijo
  `/usr`) deja el `.so` en `<stage>/usr/lib/qt6/plugins/plasma/kcms/systemsettings/`,
  la ruta que System Settings escanea sin `prefix.sh`.
- Nativo: `ctest --test-dir native/build` (smoke test del KCM + unit test de
  `kube_effect_reload`, incluida la detección del anidado y del árbol de
  procesos). Lo ejecutan `build.sh` / `make native` antes de instalar
  (`KUBE_SKIP_TESTS=1` lo salta). Además
  `kcmshell6 --smoke-test kcm_kube_effect_plus` con `WAYLAND_DISPLAY=kube-effect-nested-0`
  para comprobar que el módulo carga y que la guarda no lanza nada.
- KWin anidado (`scripts/kwin-nested-test.sh`): el usuario prueba a mano. KWin
  cachea el QML; hay que usar un proceso nuevo (anidado) o reiniciar el
  compositor con el botón del KCM.
