# ADR — decisiones de diseño (Kube Effect)

Registro de decisiones tomadas en el grill de alcance. Cada una con su porqué.
No reabrir sin motivo; si cambia, se añade un ADR nuevo que la sustituye.

## ADR-001 — Solo dos formas: polígono y cilindro.

**Decisión**: el efecto sólo ofrece **polígono** (N caras planas en N-gono) y
**cilindro** (las mismas caras curvadas). No hay una tercera forma.
**Porqué**: polígono y cilindro son topológicamente el mismo sólido (un prisma
N-gonal); el cilindro es una superficie **desarrollable** (K=0), así que curvar el
contenido es isométrico (sin distorsión). Una forma con curvatura positiva (K>0)
exige deformar el contenido (Theorema Egregium) → shader/teselado y texto
deformado → fuera del contrato "solo QML".

## ADR-002 — Cilindro isométrico con ProceduralMesh, sin shader.

**Decisión**: el cilindro se construye con `ProceduralMesh` (QML puro):
`P(s,t) = (R·sin φ, t, R·cos φ)`, `φ = s/R`, UV `u = s/W`, `v = t/H`, con
`θ = W/R`. Material estándar (`PrincipledMaterial.NoLighting` + `baseColorMap`).
**Porqué**: el mapeo plano→cilindro es isométrico (no estira); no hace falta
vertex shader. El primitivo `#Cylinder` no sirve (cilindro completo, UV propias,
no un arco). 32–64 segmentos bastan (66–130 vértices).

## ADR-003 — Sin piel: el sólido son sólo caras; el "casco" es el espacio tambien llamado skybox

**Decisión**: no hay superficie/piel entre caras. El sólido = caras (una por
escritorio). **Casco** = el **espacio alrededor** - sky - cielo (fondo/entorno), no la superficie
del sólido.
**Porqué**: separar conceptos evita la ambigüedad El cubo KDE es sólo caras; entre ellas se ve el fondo.

## ADR-004 — Fondo de cara = wallpaper REAL del escritorio

    esto debe deformar el escritorio y usarlo esto es importante para que se sigan usando el fondo real del usuario como pared del cubasi esta sea animada o video hay que verificar como hacer esto de forma optima sobre todo buscar como funciona wayland y wayfire como lo hace si es necesario

## ADR-005 — Reglas por número de escritorios.

**Decisión**: 1 y 2 → **hoja 2D doble cara** (un
escritorio por delante, otro por detrás), sin interior; 3+ → polígono (default) o
cilindro (elegible).
**Porqué**: polígono y cilindro necesitan 3+ caras. Con 2 sólo cabe una hoja; con
1 no hay sólido.

## ADR-006 — Casco configurable (todas las opciones).

**Decisión**: `CascoMode` = Color (default) / Gradient (lineal/radial/circular) /
Video (360) / Image (fija o girando con el centro) hay que mantener estatico el fondo o puede ser jirable , más `CascoDim`.
**Porqué**: el usuario quiere un casco rico, no limitado a dos fondos.

**Nota** (ADR-013): el tipo `Circular` queda fuera; `Radial` se implementa con `QtQuick.Shapes.RadialGradient`.

## ADR-007 — Interior = objetos decorativos 3D/2D.

**Decisión**: objetos dentro del sólido: 3D animado (planetas), 3D estático
(quieto al girar), vídeo, imagen 2D. Arranque: planetas + mini-cubo. Sólo con 3+
escritorios (con 2, hoja 2D, deshabilitado).
**Porqué**: "lo que puede ir dentro" del cubo es parte del ámbito; el sistema debe
cubrir los tipos, aunque se empiece con dos.

## ADR-008 — Capas de ventana (z-index) hacia dentro, tope 150 px.

**Decisión**: cada ventana = quad propio empujado hacia fuera del solido según su orden de
apilado; tope del stack 150 px con paso repartido (`fittedGap`);
esto es actibable y configurable el usuario puede decir cuanta separacion hay entre ventanas y si 2 ventanas estan abiertas pero no estan una sobre la otra entonces pertenecen al mismo z index pero si una esta sobre otra la que esta alado comparte z index con el que esta mas abajo asi da un efecto de apilado sincronizado

## ADR-009 — Recargar QML: reiniciar KWin o anidado.

**Decisión**: los cambios de QML se prueban en un KWin anidado (proceso nuevo) o
reiniciando KWin; nunca con `unloadEffect`+`loadEffect` sobre la sesión real.
**Porqué**: KWin cachea el QML compilado en memoria (bug #514131); recargar no
recompila.

## ADR-010 — Animar escalares, derivar vectores.

**Decisión**: nunca animar `scale`/`position`/`eulerRotation` directamente; animar
un `real` (pulso/órbita) y derivar el `vector3d`.
**Porqué**: animar un vector3d escribe un solo double y llena el journal de
`QVariant(double, nan/0)`, corrompiendo la escena.

## ADR-011 — Distribución híbrida: QML baseline + Kube Effect Plus independiente.

**Decisión**: el efecto SIEMPRE declara `X-KDE-ConfigModule: kcm_kwin4_genericscripted`
(menú QML = `config.ui`, funciona sin compilar). Verificado en
`plasma/kwin/src/kcms/common/effectsmodel.cpp`: KF6 **no hace fallback** al
genérico si el módulo declarado no existe, así que apuntar la metadata a un
`.so` opcional rompería el botón Configurar. El nativo es **Kube Effect Plus**,
un módulo **independiente** (`kcm_kube_effect_plus`, título «Kube Effect Plus»,
`X-KDE-System-Settings-Parent-Category: windowmanagement`), no un gemelo de
todas las pestañas: solo features nativas, diagnóstico, comprobación de
dependencias y `reconfigureEffect`.
**Porqué**: cero duplicación de UI (dos UIs que sincronizar con `main.xml`), y si el
`.so` falta o es incompatible el cubo QML sigue intacto. Precedente upstream:
`kdeplasma-addons/kwin/effects/cube` (efecto QML `declarativescript` + KCM C++
`kwin_cube_config`).

## ADR-012 — El código nativo se compila bajo demanda; nunca automático.

**Decisión**: el paquete que se distribuye (KDE Store) viaja con `native/` (fuentes
CMake). El usuario compila cuando quiere (referente real: `kde-shader-wallpaper`,
que incluye `contents/source/` y ofrece «Build and Install» con `build.sh`).
Instalación por defecto en `~/.local` con prefijo privado + `prefix.sh` (sin root);
integración permanente requiere `sudo` una vez o el paquete de distro. Verificado:
`systemsettings` KF6 descubre KCMs vía `KPluginMetaData::findPlugins` sobre los Qt
plugin paths; `~/.local/share/kservices6` NO basta y `~/.local/lib/qt6/plugins` no se
escanea sin `prefix.sh`/`QT_PLUGIN_PATH`. Sin ABI estable en KWin: el `.so` se
estampa con `KUBE_PLASMA_VERSION`, `KUBE_QT_VERSION`, `KUBE_PKG_VERSION` y escribe
`~/.local/share/kube-effect/native-stamp.json` (`plasma`, `qt`, `pkg`, `built`,
`prefix`) en `build.sh`. Tras actualizar Plasma: **nunca** se recompila solo; el KCM
detecta la discrepancia y muestra «compilado para X, tienes Y → recompila». El estado
(«no compilado», «desactualizado», «faltan dependencias») se muestra SOLO en el KCM
nativo: `config.ui` es estático (QUiLoader) y no puede leer ficheros ni pintar estado.
Paquetes por distro (AUR `-bin`, COPR, PPA, OBS) quedan como canal futuro; no ahora.
**Porqué**: compilar es un acto voluntario y explícito, nunca un efecto secundario de
instalar el paquete. Así el KDE Store sigue entregando solo QML y el usuario decide si
quiere el menú avanzado.

## ADR-013 — Degradado: radial real sin cónico; el usuario define la proporción de la imagen.

**Decisión**: `Radial` real con `QtQuick.Shapes.RadialGradient` (verificado: expone
`centerX/centerY/centerRadius/focal*` y `stops` en Qt 6.12). Deja de caer a vertical.
**No** hay tipo cónico/circular. Se elimina `BackgroundImageMapping.Auto` (adivinaba
mal): quedan `Equirect` y `Flat` explícitos, más `BackgroundImageFit`
(`Cover`/`Contain`/`Stretch`, default `Cover`) para la imagen plana.
**Nota (rename)**: la clave pasa de `BackgroundImageMapping` a
`BackgroundImageLayout` (`Equirect`=0 / `Flat`=1, misma semántica). El cambio de
**clave** es deliberado: kwinrc guarda el índice, así que un
`BackgroundImageMapping=1` viejo (que entonces era Equirect) queda huérfano y se
ignora, en vez de convertirse en `Flat`.
**Porqué**: el usuario decide qué es panorama y cómo encaja; el efecto deja de adivinar
la proporción de una imagen que no puede medir sin decodificarla.

## ADR-014 — Pestaña Advanced: solo tres claves avanzadas.

**Decisión**: `DimWhileRotating` (Bool, default false) + `DimWhileRotatingAmount` (Int
0–100, default 40): oscurece el fondo SOLO mientras el cubo gira y vuelve al soltar.
`CursorScreenOnly` (Bool, default **false** = todas las pantallas): el cubo se dibuja
solo en el monitor donde está el cursor al lanzarse; el resto de pantallas quedan
normales. Advanced es el único sitio donde viven las opciones avanzadas (no repartirlas
por otras pestañas).
**Nota (ADR-018)**: la pestaña se organiza en tres bloques con separadores
(`QFrame::HLine`): «Atenuar mientras gira», «Pantalla» y una sección plegable
«Funciones extra (Kube Effect Plus)». La intensidad de atenuación empieza
deshabilitada y se habilita con `toggled(bool)` de su casilla.
**Porqué**: las opciones avanzadas se agrupan en una sola pestaña para que las básicas
queden limpias y no se dispersen por la UI.

## ADR-015 — Arnés anidado: compila siempre antes, aborta si falla.

**Decisión**: `scripts/kwin-nested-test.sh` ejecuta `make native` antes de arrancar; si
falla, **aborta** (no se prueba con binario viejo). Tras arrancar, lanza
`kcmshell6 kcm_kube_effect_plus` con `prefix.sh` y el `XDG_CONFIG_HOME` del anidado (el
KCM escribe en el kwinrc del anidado, no en el del host). El comando de compilación que
muestra el menú QML se **oculta en pruebas** (se compila a mano al lanzar el arnés);
documentarlo como paso obligatorio cada vez que se cree un menú nuevo.
**Porqué**: nunca se prueba contra un binario desactualizado; el arnés garantiza que lo
que se ve es lo recién compilado.
**Ampliación (2026-11-25)**: el arnés arranca como una **instalación limpia**:
kwinrc de fábrica (`KUBE_NESTED_CONFIG=clean`, solo se hereda
`[Effect-kube-effect]`), `XDG_DATA_HOME` temporal y plasmashell con el panel y
el wallpaper **del sistema** — así no se carga ningún plasmoid descargado ni sus
errores (verificado: con la data aislada `Plasma.Flex.Hub`/`Plasma.Control.Hub`
no se enumeran; sin aislar sí). 3 escritorios y una ventana por cara repartida
por DBus (`--no-plasma` quita el shell, `--no-apps` deja las caras vacías,
`KUBE_NESTED_APPS` cambia la lista). No fuerza `Background` (usa la configuración
del efecto; forzarlo a Image con un `.mp4` en `SkyBox` dejaba el casco vacío y
parecía un bug del efecto), sigue los logs en vivo y `Ctrl+C` para el anidado
entero. El `pidfile` guarda el pid de `kwin_wayland` (el de `dbus-run-session`
deja el compositor huérfano al matarlo). Y ojo: `Meta+K` dentro del anidado se
lo queda el KWin del host, así que la activación fiable es el borde superior
(`BorderActivate=1`).

## ADR-016 — `features.json`: catálogo de features y dependencias.

**Decisión**: `package/contents/config/features.json` con `id`, `label`,
`requires[]`, `native` (bool), `notes`, `status` (stable/planned/needs-native),
`since`. Consumidores: `scripts/check-deps.sh` / `make deps` (Python) y el KCM
nativo (pinta palomitas de dependencias). **El QML no lo lee** (sin validación en runtime
ni avisos en pantalla).
**Porqué**: una sola fuente para «qué feature necesita qué» y para saber qué puede correr.

## ADR-017 — Degradado giratorio: tres orientaciones y el radial mueve el foco.

**Decisión**: nueva clave `BackgroundGradientRotation` (Enum → entero en kwinrc):
`Fixed` (0, default: el degradado no gira), `FollowCube` (1: gira con el yaw de la
cámara/cubo) y `FollowCubeInverse` (2: gira al revés). Solo afecta al **casco
degradado** (`Background=Gradient`); el color, la imagen y el SkyBox no cambian.
La rotación lineal es un `Rotation` (transform) sobre un `Rectangle`
sobredimensionado al diagonal de la pantalla, así que **no se crea ningún objeto por
frame**; los stops del `Gradient` se remapean a la franja visible para que `Fixed`
se vea exactamente igual que antes. Un `RadialGradient` centrado es simétrico, así
que girarlo no se notaría: en `FollowCube`/`FollowCubeInverse` se desplaza el
**foco** (`focalX`/`focalY`) sobre una circunferencia de radio `0.25 · max(w, h)`
con ese mismo ángulo; con `Fixed` el foco queda en el centro del item.
**Porqué**: el usuario quiere que el fondo pueda «seguir» al cubo mientras gira, sin
shaders ni C++ y sin coste por frame; el radial necesitaba una solución distinta de
la rotación porque no se puede percibir girando.
**Nota**: el menú QML (`config.ui`, página Degradado) gana el combo; el KCM nativo
(`kcm_kube_effect_plus`, «Kube Effect Plus») **sigue siendo solo diagnóstico** hasta
que exista una feature que QML no pueda hacer (ADR-011).

## ADR-018 — «Kube Effect Plus»: nombre, fuentes en el paquete y Advanced en lenguaje llano.

**Decisión**:
1. El módulo nativo pasa a llamarse **Kube Effect Plus**: id de plugin
   `kcm_kube_effect_plus`, nombre visible «Kube Effect Plus». El directorio
   sigue siendo `native/` y los targets `make native*` no cambian.
2. El paquete distribuible incluye las **fuentes** para compilar bajo demanda en
   `package/contents/native/` (copia de `native/`, sin árboles de build,
   `*.o`, `CMakeFiles` ni `.cache`). `native/` sigue siendo la fuente de verdad:
   `make sync-package-native` copia (y `make install` lo invoca antes de
   `kpackagetool6`); `make check` falla si `package/contents/native/` no
   coincide. KWin no carga nada de esa carpeta.
3. `native/build.sh` funciona también desde la copia instalada
   (`.../contents/native/build.sh`): calcula todas sus rutas desde su propia
   ubicación y, si no encuentra el `Makefile` + `package/metadata.json` del
   repo al lado, guarda esa carpeta como `source` en el stamp.
4. La pestaña **Advanced** del menú QML se rehace en tres bloques con separadores
   y lenguaje llano, sin nombres de API: «Atenuar mientras gira» (casilla,
   ayuda y una intensidad que empieza **gris/deshabilitada** hasta marcar la
   casilla), «Pantalla» (solo en la pantalla del puntero, con su explicación) y
   una sección **desplegable** «Funciones extra (Kube Effect Plus)» que hoy dice
   la verdad: Plus aún no añade funciones; aquí aparecerán cuando exista alguna
   que el efecto no pueda hacer por sí solo. La sección incluye los comandos
   válidos desde el paquete instalado (`cd .../contents/native`, `./build.sh`,
   `./build.sh --system`).

**Porqué**: el nombre «(avanzado)» sonaba a opciones ocultas cuando el módulo
solo añade diagnóstico y herramientas nativas; «Plus» describe lo que es. Llevar
las fuentes dentro del paquete permite compilar sin el repositorio sin duplicar
la fuente de verdad (`native/`), y el rediseño de Advanced deja claro qué hace
cada opción sin exponer la API interna de KWin.
**Verificación**: `scripts/check-ui.py` carga el `.ui` con QUiLoader y
comprueba que la intensidad empieza deshabilitada, que sigue a su casilla, que
`plusSection` empieza oculto y que sus dos separadores son `QFrame::HLine`.

## ADR-019 — El vídeo es una imagen con otra fuente; dependencia opcional declarada.

**Decisión**:
1. `Background` gana `Video` como **cuarto** valor (índice 3, al final): los
   valores guardados 0/1/2 siguen significando Color/Image/Gradient. La clave nueva
   `BackgroundVideo` (Url) guarda el clip; se aceptan solo ficheros locales
   (`file:`), nunca red.
2. El vídeo **reutiliza** `BackgroundImageLayout`, `BackgroundImageFit` y
   `BackgroundImageRotate`: es una imagen con otra fuente, así que equirect +
   girar = panorama 360 y Flat o sin girar = capa plana con el ajuste. No hay
   claves nuevas para «cómo se muestra». **Corregido (ADR-020)**: el 360 de vídeo
   no usa `SceneEnvironment.SkyBox` (Qt rechaza ahí un `Texture.sourceItem`),
   sino una esfera vista desde dentro.
3. `QtMultimedia` es una **dependencia opcional** declarada en `features.json`
   (`requires: ["QtMultimedia"]`, `status: stable`, `since: 0.0.0.3`). Su import
   está aislado en `package/contents/ui/HullVideo.qml`, cargado con un `Loader`
   desde `ScreenView.qml`: si falta el módulo, solo ese item queda en
   `Loader.Error`, se avisa una vez y se pinta `BackgroundColor`. Un import
   directo en `ScreenView.qml` habría roto todo el efecto.
4. El vídeo solo reproduce con `effect.visible` (pausa al ocultar, reanuda al
   mostrar; el item no se crea hasta la primera activación), en bucle y sin sonido
   (`AudioOutput { muted: true }`, porque `MediaPlayer` no tiene `muted` en Qt
   6.12). La atenuación al girar reutiliza el velo 2D o `probeExposure` según el
   camino, sin lógica nueva.
5. La pestaña **Advanced** explica la dependencia en lenguaje llano, sin comandos
   más allá del nombre del paquete (`qt6-multimedia`), y el KCM agrupa las tres
   claves compartidas fuera del stack («Imagen o vídeo: cómo se muestra») porque un
   `kcfg_` = un widget.
**Porqué**: el usuario quiere el vídeo con la misma libertad que la imagen (360 o
fijo, girable o no) sin duplicar opciones ni convertir una dependencia opcional en
obligatoria. Declararla en el catálogo deja que `make deps` y el KCM de Plus
digan si falta, y el fallback a color mantiene el cubo usable en cualquier sistema.
**Verificación**: `scripts/check-video.py` instancia `HullVideo.qml` en un motor
QML real (item y `VideoOutput` creados; módulo ausente y fuente rota → `Loader.Error`
sin llevarse la escena).

## ADR-020 — El vídeo 360 se pinta en una cúpula, no en el SkyBox.

**Decisión**: cuando `BackgroundVideo` es equirect y «girar con el centro» está
activo, el clip se pinta en un `Model { source: "#Sphere" }` visto desde dentro,
con `position: camera.position` (sin heredar su rotación), radio 50 × escala 100 =
5000, `cullMode: FrontFaceCulling` y `PrincipledMaterial { lighting: NoLighting;
baseColorMap: Texture { sourceItem: videoOutput } }`. La atenuación al girar usa
una segunda esfera negra justo dentro (radio 5000 × 0.99) con
alpha = 1 − `skyBoxExposure`, así las dos rutas (imagen con `probeExposure`, vídeo
con velo) oscurecen exactamente `dimOpacity(...)` y comparten el `Behavior` de
120 ms. El `VideoOutput` de `HullVideo.qml` debe seguir **renderizándose** (capa
2D visible detrás del `View3D`): su textura no existe si el item no entra en la
escena; la cúpula, opaca, tapa esa capa y no se ve duplicada.
**Porqué**: Qt Quick 3D imprime «Cannot use QSGTexture from Texture.sourceItem as
light probe.» y no dibuja nada; medido 2026-11-25 con `Background=Video`, el fondo
quedaba vacío (y el aviso se repetía cada frame, llenando el journal). El mismo
`sourceItem` sí funciona en el `baseColorMap` de un material (rectángulo/esfera
con vídeo verificado: cientos de colores distintos y velo al 40 % exacto), y el
resultado visual es el mismo panorama envolvente.
**Nota**: el escenario previo (SkyBox + `sourceItem`) se elimina, con su `Loader`
y su ruta de `probeExposure`, en vez de dejarlo como código muerto.
**Corregido (2026-11-25)**: el `VideoOutput` de la cúpula ignora
`BackgroundImageFit` mientras envuelve (`HullVideo.dome = true` →
`fillMode: Stretch`). Con el default Cover el equirect se recortaba arriba y
abajo (faltaba cielo y suelo y el horizonte saltaba al girar) y con Contain
entraban barras negras a los polos. El ajuste del usuario solo manda en la
capa plana; la esfera hace el envoltorio. Medido con un clip 608×304.
`scripts/check-video-dome.py` ahora exige `fillMode == Stretch` en el caso 360.
**Verificación**: `scripts/check-video-dome.py` renderiza el `ScreenView.qml` real
(con un módulo `org.kde.kwin` simulado y un `effect` falso: `Background=Video`,
Equirect, girar) y exige un frame con muchos colores distintos; cargar sin error
no basta, porque el fallo anterior cargaba bien y pintaba negro. Necesita
pantalla real, así que en CI se salta.



## ADR-021 — Transparencia de caras antes del cilindro.

**Decisión**: nuevas claves `FaceOpacity` (Double 0.1–1, default 1, reposo),
`FaceRotationOpacity` (Double 0.1–1, default 0.7, solo al girar) y `FaceFadeMs`
(Int 0–1000, default 120). La opacidad se aplica al `DefaultMaterial.opacity` de
`CubeFace.qml`, con la misma señal de giro que la atenuación del casco
(`cameraController.busy || rotationAnimation.running`); un `Behavior` de
`FaceFadeMs` funde ambos valores. Con `opacity < 1` el material pasa al pase
transparente de QtQuick3D, que ya ordena los objetos mezclados de atrás hacia
delante por distancia (el equivalente del render en dos pasadas de Wayfire);
no hace falta ordenar el `Repeater3D` a mano. Mínimo 0.1: una cara invisible
no se puede clicar ni elegir.

**Porqué**: el cilindro (ADR-002) y el interior necesitan que se vea a través
del sólido; la transparencia es prerrequisito de la forma, no un adorno. Se
implementa sobre el material, no sobre la geometría, así que la malla curva del
cilindro la hereda sin tocar esta lógica. Es el rasgo «cube transparency» de
Compiz, adaptado a QML puro (sin shader): `DefaultMaterial.opacity` + orden
explícito bastan. Independiente de `DimWhileRotating`: eso oscurece el casco,
esto las caras; pueden combinarse.

**Verificación**: `scripts/check-constants.py` prueba `faceOpacity(...)`
(reposo/giro/clamp/NaN) y `make check` valida el esquema (widget
QDoubleSpinBox por clave). Prueba visual solo en el anidado
(`scripts/kwin-nested-test.sh`), nunca en el host.

---

## ADR-022 — Lote de estabilidad pre-cilindro.

**Decisión**: correcciones puntuales de estabilidad y rendimiento encontradas en
auditoría, sin cambiar claves de configuración ni el contrato QML-puro:

1. **Delegate reactivo** (`main.qml`): el `delegate` de un SceneEffect se evalúa
   una vez, así que un `Qt.createComponent(...)` en un binding dejaba el
   PlaceholderView clavado al crecer a 3+ escritorios (y el cubo vivo al bajar de
   2). Se pasa a dos `Component` inline y un binding sobre `desktopCount`
   (`Workspace.desktops.length`); KWin recrea los SceneViews cuando cambia el
   delegate.
2. **Geometría con `geometryCount >= 3`** (`Cube.qml`): `angleTick = 360/count`
   sin guarda producía Infinity (count 0 → flood de NaN documentado en
   trucos-aprendidos §C), −4e18 (count 1) o ~0 (count 2) en `faceDistance`.
   `angleTick` y `faceDistance` usan `Math.max(3, faceRepeater.count)`;
   `desktopAt()` tolera delegates nulos.
3. **LOD de caras opacas**: cada cara mantiene un `Texture.sourceItem` = capa
   offscreen a resolución completa por frame. Con `faceOpacity >= 0.99` las
   caras que dan la espalda a la cámara están totalmente ocluidas y se marcan
   `visible: false` (cero captura); con caras semitransparentes se mantienen
   todas, porque hay que ver las lejanas a través. El criterio es
   `cos(faceAzimuth - cameraYaw) >= 0` — umbral 0, no un margen positivo: una cara
   a 89° sigue siendo frontal (un `> 0.15` la ocultaba y dejaba un hueco con el
   casco asomando por el canto), y solo cruza `cos < 0` la que de verdad da la
   espalda; `cameraYaw` llega a Cube desde el binding de `cameraController` en
   ScreenView.
4. **SceneEnvironment único** (`ScreenView.qml`): los dos Loaders
   transparent/skybox se recreaban en cada cambio de modo (vaivén de objetos del
   entorno en plena animación de cierre). Un solo `SceneEnvironment` inline
   alterna `backgroundMode` y su `lightProbe` se gatea por `skyBoxImageReady` y
   `drawOnThisScreen` (multi-monitor). Nota honesta (segunda revisión): **no**
   hay latch `skyBoxEverShown` — KWin destruye el SceneView en cada desactivación
   (`QuickSceneEffect::stopInternal`; el view caching está apagado y no es
   `Q_PROPERTY`), así que el re-decode del panorama por activación es inevitable
   desde QML: conservarlo exigiría activar el caching en C++, fuera del contrato
   QML-puro. El fix real era eliminar el vaivén de los dos Loaders, no retener la
   textura.
5. **Clamp de zoom relativo a `faceDistance`** (`CubeCameraController.qml`): la
   rueda sin límites dejaba `radius` bajo `clipNear` (caras desaparecidas).
   `minRadius`/`maxRadius` enlazados a `faceDistance * 0.6` / `faceDistance * 8`.
6. **`screenName`/`screenGeometry` explícitos** (`DesktopView.qml`): el
   `targetScreen` resuelto por scope dinámico es frágil (qmllint no lo ve y
   depende del encadenado de objetos). El ScreenView los pasa como propiedades
   requeridas, y `wId` tolera modelos nulos (0 = nullWId, libera captura).
7. **Shapes opcional con fallback lineal** (`HullRadial.qml`): el import de
   `QtQuick.Shapes` era dependencia dura de TODO el efecto (sin Shapes no había
   ni placeholder). El radial se carga con `Loader` desde `HullGradient.qml`;
   en `Loader.Error` cae al degradado lineal y avisa una vez. La nota de las
   features `background-*` en `features.json` documenta el fallback.
8. **Plus: D-Bus asíncrono + quoting** (`native/src/kcm`): `reconfigureEffect`
   y `logout` usaban `QDBusInterface::call` síncrono en el hilo GUI (hasta 25 s
   congelado si KWin no responde); pasan a `QDBusConnection::asyncCall()` +
   `QDBusPendingCallWatcher` con el resultado en la etiqueta existente. El
   bloque de comandos copiaba la ruta del stamp sin comillas (`cd %1`): se
   añade `shellQuote()` (comillas simples; una comilla literal se cierra y se
   escapa como `'\''`), la ruta se valida absoluta y la lógica pasa a
   `kube_effect_install.*`, testeable con ctest.
9. **Menus y detalles**: activar durante el cierre reaprovecha el timer en vez
   de dejar el efecto muerto; `switchTo()` ignora clics con el efecto cerrado;
   `constants.js` trata `null` y `""` como «sin valor» (usa el default, no el
   suelo, porque `Number(null) === 0`); el vídeo resetea
   `videoEverShown`/`videoWarningShown` al cambiar fuente o modo (con rearma
   del diagnóstico si el Loader ya estaba listo); el probe del skybox y el
   Loader del vídeo se gatean por `drawOnThisScreen` (multi-monitor);
   el `yaw` del degradado solo se descompone en modo Gradient; imports y
   tamaños implícitos muertos fuera.

**Porqué**: son fallos de orden de magnitud (cubo que no aparece, congelación
de 25 s, reconstrucción de texturas por ciclo) que hay que cerrar antes de la
forma cilíndrica (ADR-002), que multiplica delegates, caras y cargas.

**Verificación**: `make check` (qmllint, check-constants con los tests null →
default, check-scene-environment, check-video-dome, check-features) y
`make native` (ctest: quoting del bloque de comandos). Prueba visual solo en
el anidado (`scripts/kwin-nested-test.sh`).

## ADR-023 — Sin LOD de caras; modo DebugOverlay permanente.

**Decisión**:

1. **Se retira el LOD de caras de ADR-022 punto 3**: todas las caras se
   renderizan siempre (el delegate pierde el `visible:` y `isFacingCamera`
   desaparece). Medido en el anidado (2026-11-25): en reposo (`op=1.00`,
   yaw=0.2) el criterio de orientación ocultaba caras con `f1:-0.50` y
   `f2:-0.50` y esas caras abrían un agujero por el que asomaba el casco; al
   girar (`op=0.70`) el LOD ya no actuaba y todo se veía bien. Es un bug de
   diseño, no de umbral: con `Material.NoCulling` (las caras se ven por las
   dos partes, necesario para la hoja 2D y el sliver frontal) y
   `CubeFaceDisplacement > 0`, los **interiores** de las caras traseras se ven
   a través de los huecos entre caras — eso ES el aspecto del cubo virgen de
   KDE, y ocultar las traseras lo cambia. El ahorro de capturas no vale ese
   cambio de apariencia. El coste se atacará con LOD real **por distancia**
   cuando exista WindowLayering (fase posterior, `WindowLayerLodFaces`), no
   por orientación.
2. **El debug temporal pasa a ser `DebugOverlay`** (Bool, default false,
   pestaña Advanced): un texto rojo monoespaciado en pantalla con el estado
   vivo del efecto (modo de fondo, equirect/skybox, vídeo con `mediaStatus`,
   dim/exposición, pantalla y dibujado, yaw/pitch/radio, opacidad/tick/cos por
   cara, geometría). El yaw y el pitch solo se descomponen del cuaternión
   mientras el overlay está activo — el mismo gateo del yaw del degradado
   (ADR-022 punto 9).

**Porqué**: el diagnóstico necesita un canal **visible**, y ninguno de los
dos estándar lo es en este KWin: `console.log`/`console.warn` no llega al
journal (trucos §D) y `org.kde.kwin.Effects.supportInformation` devuelve
cadena vacía en KWin 6.8.3 (medido 2026-11-25; invalida el patrón que esta
doc daba por bueno — corregido en trucos §D). Pintar en pantalla es lo único
comprobado que funciona: así se diagnosticó el propio bug del LOD. Con la
clave apagada (default) el overlay no se pinta ni paga descomposiciones.

**Verificación**: `make check` (check-schema: entry `DebugOverlay` ↔ widget
`kcfg_DebugOverlay`; check-ui: la checkbox se crea con QUiLoader; qmllint) y
prueba visual en el anidado (`scripts/kwin-nested-test.sh`) con el overlay
encendido y apagado.

---

## ADR-024 — Hoja 2D: la forma vive en Cube, no en otra vista.

**Contexto**: el spec viejo (§1) exigía 3+ escritorios y debajo de ese mínimo
`main.qml` montaba un `PlaceholderView` que pedía añadir escritorios. Con 1-2
el efecto era inútil, y con 1 escritorio el placeholder además chocaba contra
la realidad: KWin siempre tiene al menos un escritorio virtual.

**Decisión**:

1. **Hoja dentro de `Cube`, no una vista nueva.** Con `faceRepeater.count < 3`
   la forma es hoja: los quads se colocan en el centro del espacio con
   `eulerRotation.y = index * 180` y `position.z = ±sheetGap`, **separación
   proporcional** (`sheetGap = max(1, viewRadius · 0.005)`, ≥2 unidades entre
   caras): un hueco fijo de 1 px es 1-2 pasos del depth buffer (24-bit,
   `clipNear` 10) a radios de 4K y puede Z-fightear. Con 1 escritorio solo
   existe el frente (z = +`sheetGap`), el lado que mira la cámara en reposo.
   `ScreenView`, el casco, las capturas de `DesktopView`, la dim, el debug y la
   cámara **no se duplican**: el bug del placeholder se cierra retirando la
   rama, no añadiendo una tercera vista.
2. **Giro limitado con 1 escritorio.** `Material.NoCulling` muestra el dorso
   espejado (ya documentado en §2.0: las caras se ven por las dos partes). Con
   un solo quad no hay «otro lado» que sea un escritorio real, así que el
   azimut se clampa a **±80°** (`SHEET_AZIMUTH_LIMIT_DEG` en `constants.js`).
   Límite fijo, sin clave de configuración: si el usuario la pide, se expone
   entonces. Con 2 escritorios el giro es completo (cada lado es un escritorio).
3. **Regla permanente pre-cilindro**: con 1-2 escritorios la forma es hoja
   siempre, ignore la futura clave `Shape`. Los caminos que producen azimut
   clampean distinto, cada uno a propósito:
   - **Arrastre** (`CubeCameraController.processInput`): con límite real
     (<360) clampa la suma cruda `euler.y + delta` a ±límite, **sin `%360` ni
     normalizar** — un tirón fuerte que cruzara ±180 se teletransportaría de
     +80 a −80 al envolver. Sin límite (hoja-2, polígono) se conserva el
     `% 360` histórico.
   - **Flechas y estados close/distant**: `Constants.clampSheetAzimuth
     (azimuth, limit)` normaliza a (-180,180] solo cuando el límite es real;
     con limit ≥ 360 (o basura) devuelve el ángulo **tal cual**, paridad
     exacta con el código pre-hoja (cuaterniones de signo opuesto harían
     slerpear el Behavior por el lado largo).
4. **Radios de cámara**: `viewRadius` en hoja es `0.5·anchoCara` (no puede leer
   `faceDistance`: el gap deriva del radius, ciclo), `faceDistance` en hoja es
   `sheetGap` y el estado close sigue llenando la pantalla
   (`faceDistance + 0.5·h/tan(fov/2)`); distant y los límites de zoom usan
   `safeViewRadius = max(1, viewRadius)`: `CubeFaceDisplacement` negativo puede
   volver **negativo** el apotema del polígono (pre-existente ADR-022), y con
   él minRadius/maxRadius y el distant metían la cámara dentro del sólido.
5. **Re-sincronización con el efecto abierto** (`ScreenView`): los
   `PropertyChanges` de los estados son bindings vivos solo hasta la primera
   interacción (arrastre/flechas/rueda escriben `rotation`/`radius` y los
   matan). Si cambia el nº de escritorios sin cerrar (2→1 con yaw 170) no se
   re-clampa y se ve el dorso espejado; 2→3 deja yaw 180 → Enter/click elige el
   escritorio equivocado; y el `radius` queda el de la forma vieja. Un
   `Connections` sobre `cube.faceCount` llama `resyncToState()`: reescribe
   `rotation` (elevation actual + target de la forma nueva) y `radius` con las
   fórmulas del estado vigente. Es idempotente con los bindings vivos, y los
   bindings se reinstalan solos en cada deactivate/activate (el estado vuelve
   a entrar).
6. **Retirada de `PlaceholderView.qml`** (git rm). `main.qml` deja el gate por
   `desktopCount` y deja un único `Component` inline con `ScreenView` (el
   delegate del SceneEffect se evalúa una vez, ADR-022 punto 1, pero ya no hay
   dos componentes entre los que cambiar).
7. **Helpers puros en `constants.js`**, testeables sin KWin
   (`scripts/check-constants.qml`): `sheetAzimuthLimit(count)` (1 → 80,
   2/3+/basura → 360 = sin límite), `sheetDesktopAt(azimuth, count)` (qué
   escritorio mira la cámara; −1 = no aplica o azimut no numérico) y
   `clampSheetAzimuth(azimuth, limit)` (verbatim con limit ≥ 360; si no,
   normaliza a (-180,180] y clampa). `CubeFaceDisplacement` no toca la hoja.

**Porqué**: reutilizar el camino existente mantiene una sola fuente de
geometría/estados/cámara — otra vista nueva duplicaría el casco, el vídeo 360,
la dim y el overlay de debug (todo lo caro de ADR-022/023) y volvería a quedar
fuera de los checks del anidado. El límite ±80° es más estrecho que ±90° para
que en el recorrido extremo el quad nunca se vea de canto con el dorso asomando
por perspectiva.

**Verificación**: `make check` (check-constants con los helpers
nuevos y los bordes de `clampSheetAzimuth`; check-video-dome renderiza
`ScreenView` con el stub de 3 escritorios → camino poligonal intacto, más una
segunda pasada con el stub de 2 → `debugInfo` dice `sheet=1 tick=180.0`; el
stub ya no devuelve `currentDesktop` nulo — el camino poligonal la necesitaba
— y el harness falla ante TypeError/ReferenceError/«is not defined»). Prueba
visual en el anidado con 1 escritorio (no pasar de ±80° arrastrando ni con
flechas; crear/eliminar el 2º escritorio con el cubo abierto y ver la
re-sincronización) y con 2 (vuelta completa, cada cara con su escritorio).

---

## ADR-025 — Cilindro segmentado con hueco lineal.

**Decisión**: la segunda forma del contrato (ADR-001) llega como **cilindro de
N arcos**, con estas reglas:

1. **Enum `Shape`** en `config/main.xml`: `Polygon` (0, default) / `Cylinder`
   (1). Con **3+ escritorios** elige tambor (cilindro cerrado de N arcos) o
   polígono. Con **1-2** `Shape` elige la REPRESENTACIÓN (punto 11, versión
   final): `Polygon` deja la hoja plana (ADR-024, comportamiento intacto) y
   `Cylinder` muestra el **tambor de tres slots** con las caras vacías
   enseñando el casco — la versión intermedia de este punto («segmento
   curvo» con topes) fue retirada por el usuario (ver pt.11 re-rectificado
   y ADR-026). `constants.js` espeja la tabla y la resuelve con
   `shape(value)` (desconocido → Polygon, el patrón de `backgroundMode`).
2. **Radio por hueco LINEAL sobre la superficie**: `g = max(0,
   CubeFaceDisplacement)` y

   ```
   R = N·(W + g) / (2π)          θ_arco = W / R          hueco angular = 2π/N − θ
   ```

   El desplazamiento entre caras consecutivas medida **sobre el cilindro** es
   exactamente `g` (px), como en el polígono: los arcos miden W (isometría) y
   cada hueco angular mide g/R radianes → g px. Con `g = 0` los arcos se tocan:
   cilindro cerrado **sin piel** (ADR-003 intacto — entre arcos se ve el casco
   SOLO si g > 0).
3. **Negativo clampeado a 0**. En el polígono un displacement negativo encoje
   el radio (caras solapadas); en el cilindro es geométricamente imposible: el
   arco tiene que medir W o la textura se comprime (la isometría K=0 es el
   contrato de ADR-002). `cylinderRadius()` clampa y el KCM lo dice en el
   tooltip y en el hint de la pestaña Shape.
4. **Malla**: `ProceduralMesh` (`import QtQuick3D.Helpers`) con **64 segmentos
   fijos** (`CYLINDER_SEGMENTS`), generado por la función pura
   `cylinderArcGeometry(faceWidth, faceHeight, radius, segments)` en
   `constants.js` — posiciones `P(s,t) = (R·sin φ, t − H/2, R·cos φ)` con
   `φ = (s − W/2)/R` (arco centrado en +Z; **rectificado en ADR-026**:
   `R·cos φ − R`, el arco pasa a envolver el propio nodo), normales `x = sin φ, y = 0,
   z = cos φ` (radiales salientes), UVs `u = s/W`, `v = t/H` con la misma
   convención del `#Rectangle` nativo — medida sobre `Rectangle.mesh` de Qt
   6.12: la fila inferior lleva `v = 0` y la superior `v = 1`, lo que hace
   la dirección del eje Y — y triángulos con winding **CCW visto desde fuera**
   (igual que los índices `0,1,2…` del rectángulo). Así `Texture` hace con
   la malla curva exactamente lo que ya hace con el quad plano (la cara del
   cubo se ve derecha arriba en el anidado): el compuesto sale derecho y sin
   giro de 180°. La malla se reconstruye **solo cuando cambia (W, H, R)** —
   bindings QML sobre la función pura, nunca por frame.
5. **Colocación = la del polígono** (tambor): la malla se genera centrada en
   +Z y cada cara se gira con `eulerRotation.y = angleTick · index` en
   posición (0,0,0) — el radio vive en los vértices, no en la traslación.
   (**ADR-026 revierte esta parte**: el radio vuelve a la `position` del
   nodo —`rotar(azimut)·(0,0,R)`— y la malla se genera alrededor del nodo;
   así el centroide de sort es distinto por cara, como siempre en el
   polígono.) Así
   `angleTick`, `desktopAt()` y `desktopAzimuth()` son idénticos en las dos
   formas con 3+ y el hueco entre arcos queda exactamente en el bisector de
   dos azimuts consecutivos. (Con 1-2 cilindros rige el suelo de 3 slots del
   punto 11; la malla se genera alrededor del nodo desde ADR-026, no centrada
   en +Z.)
6. **Una sola malla compartida**: las N caras son N `Model` que referencian el
   MISMO `ProceduralMesh` (property `geometry` de Model; `source` queda vacío
   en cilindro) — es lo que ya hacen los primitivos nativos (un `#Rectangle`
   para todos los Models) y ahorra N-1 uploads de vértices. Cada Model aporta
   su transformación y su material propios. (Si el anidado mostrara un problema
   con la geometría compartida, el plan B es una instancia por cara: el cambio
   es local a Cube/CubeFace y no toca la fórmula.)
7. **Cámara**: con tambor `faceDistance = viewRadius = R`; los estados
   close/distant, los límites de zoom y `safeViewRadius` usan la
   infraestructura existente (ADR-022/024) sin fórmula nueva: R sustituye al
   apotema del polígono. Con Shape=Cylinder y g=0 close llena la pantalla
   igual que el polígono con el mismo W, H **en vertical** (la generatriz
   del cilindro no se deforma: la altura llena siempre). En horizontal
   ninguna cara curva llena como el quad plano: los bordes del arco se van
   hacia dentro por curvatura — con el segmento de 120° la cuerda visible
   mide 2·R·sin(60°) ≈ 0.826·W, así que close deja ~8-9 % de casco a cada
   lado (no es bug: bordes curvos proyectados). Con 1-2 cilindros el tambor
   de tres slots mide sobre `R = 3(W+g)/2π` (pt.11 re-rectificado: el radio
   fijo 3W/2π de la versión «segmento» murió con la banda), misma
   sustitución.
8. **Contenido**: la cara cilíndrica recibe el compuesto completo
   (`DesktopView` = wallpaper + ventanas) como `diffuseMap` sobre la malla
   curva, con el mismo `DefaultMaterial` NoLighting + NoCulling +
   opacity=`faceOpacity` (ADR-021 se hereda sin cambios). El texto NO se
   deforma (isometría), solo se curva.
9. **Módulo aislado en tiempo de ejecución**: el import de `QtQuick3D.Helpers`
   vive SOLO en `CylinderArcMesh.qml`, y `Cube.qml` lo alcanza únicamente con
   `isCylinder` y a través del `source` de un `Loader` (la URL se resuelve en
   tiempo de ejecución; un delegate inline convertiría el import en
   dependencia de compilación de todo el efecto). El `Loader` exige raíz
   `Item`, así que el fichero es un holder `Item` de tamaño cero que expone el
   `ProceduralMesh` en su propiedad `mesh`. Si el módulo faltara en un sistema,
   solo falla ese `Loader`: `cylinderMesh` queda nulo, `cylinderActive` pasa a
   false y el sólido **degrada al polígono** (o a la hoja plana con 1-2,
   ADR-024; en ambos casos con las fórmulas planas que ya existían — nunca se
   lee una clave que no pudo cumplirse) — el QML engine deja la línea del
   import ausente en el log.
   Con `Shape=Polygon` el `Loader` ni se crea: coste cero.
10. **Hoja plana y polígono intactos**: ni la rama poligonal de `Cube`, ni
   la hoja (ADR-024, que sigue siendo la representación con
   `Shape = Polygon`), ni `CubeCameraController` cambian de comportamiento;
   el cilindro es una rama nueva en la geometría de `Cube` y una geometría
   opcional en `CubeFace`.
11. **Tambor de tres slots con 1-2 escritorios** (rectificación FINAL del
   usuario tras probar las dos intentonas de banda; sustituye por completo al
   «segmento curvo» que este punto describía): 1 o 2 arcos no cierran un
   cilindro, pero la forma curva NO cae a la hoja plana ni se encierra en una
   banda con topes: el sólido es un **tambor de 3 slots** — la fórmula del
   tambor corriendo con N = 3, con las caras en los slots que existen y los
   slots sin escritorio **vacíos** (no se crea delegate: por ahí se ve el
   casco, «cara vacía» sin panel, ADR-003):

   ```
   slots  = 3 (geometría fija, el count solo pone caras en 0..count-1)
   R      = 3·(W + g) / (2π)   (cylinderRadius(3, W, g) — el hueco LINEAL g
                               del usuario SÍ aplica, ya no hay radio fijo)
   tick   = 360/3 = 120°       (slot 0 en 0°, slot 1 en 120°, slot 2 en 240°)
   rango  = ABIERTO a todos los counts (giro libre, sin topes)
   ```

   **Por qué se retiró la banda**: las dos versiones de topes que se probaron
   en el anidado — la primera simétrica (±80 con uno, ±120 con dos) y la
   rectificada asimétrica ([-60, 60] con uno, [-60, 180] con dos) — eran lo
   que «hacía saltos raros y se sentía poco fluido»: el clamp mordía el
   arrastre en los bordes de banda y las flechas/normalizaciones producían
   giros en espejo. Con giro libre el tambor de 3 slots es exactamente la
   experiencia del tambor real: la cara de frente es la que hay, aparcar
   frente a un slot vacío enseña el casco (vista válida), y el dorso espejado
   se tolera por los huecos y cantos igual que en el tambor de 3+ (ADR-023;
   el culling sigue retirado, pt.12). Con 1 escritorio el slot 0 está en
   azimut 0 y el target de los estados es verbatim sobre rango abierto →
   **la cara queda SIEMPRE de frente al activar** (guard verificado por
   `check-cylinder-wiring.py` y por el escenario `single` de
   `check-cylinder-overlap.py`).

   Consecuencia en helpers: `cylinderArcRadius`, `cylinderSegmentAzimuth`,
   `cylinderAzimuthRange` y `cylinderSegmentDesktopAt` **mueren** — el azimut
   es la grid `angleTick·index` con `angleTick = 360/max(3, count)`, la
   selección es el `desktopAt` estándar del tambor (slot vacío → delegate
   ausente → `null` → `switchTo` no-op, guarda ya existente) y el rango lo da
   `azimuthRangeFor` (ADR-026): Cylinder con malla → `[null, null]`. La
   **hoja plana no cambia** (ADR-024 intacto: ±80 con uno, libre con dos,
   `flatAzimuthRange` + `clampAzimuthRange` + arrastre crudo sin normalizar);
   Cylinder **sin** malla (QtQuick3D.Helpers ausente) degrada a la hoja con
   sus topes, como antes. El DebugOverlay marca el caso con `shape=cyl R=…
   g_eff=… slots=1/3` (o `2/3`) y `lim=none`. Con `Shape = Polygon` 1-2
   sigue siendo la hoja plana exacta de ADR-024.
12. **Culling dinámico RETIRADO del runtime (rectificación del usuario)**:
   la primera lectura del problema medido en el anidado (caras traseras con
   `f1:-0.99/f2:-0.99` cuya **pared interior espejada** aparecía por encima
   y entre los arcos, tapando las frontales) llevó a `BackFaceCulling` con
   cámara fuera de 1.05·R. El usuario aclaró el requisito real: **ver la
   pared interior por los huecos y cantos es paridad con el polígono y se
   conserva (ADR-023)**; lo que no debe pasar es que esa pared se **dibuje
   encima** de las frontales (overlap), sobre todo al girar. Culling ≠ fix:
   suprimía las dos cosas. El runtime vuelve a `Material.NoCulling`
   siempre — tambor (a todos los counts), polígono y hoja, idéntico entre sí (en
   `Cube.faceCullMode` queda la property fija en NoCulling con un TODO que
   apunta al fix real). `cylinderCullMode` (tokens 1/0, nunca ints del enum
   — medido en Qt 6.12.1: Back=1, Front=2, None=3, un hardcode de 2 habría
   dado FrontFaceCulling, el efecto opuesto) **NO se borra** de
   `constants.js`: queda documentado como sin-uso en runtime y testeado,
   como semilla del fix real. El fix real es de **orden de pintado**, no de
   geometría: con `faceOpacity < 0.99` las caras entran en la pasada
   transparente de QtQuick3D, que ordena por **centroide** del objeto — en
   el tambor los centroides de los arcos se apilan distinto que en el
   polígono (la malla curva separa el centro del quad del volumen que
   ocupa), y ahí es donde una trasera puede pintarse encima de una frontal
   viva. Con `op = 1.00` en cambio el overlap sería un bug de **profundidad**
   (dos Models sobre la misma geometría compartida / winding), caso
   distinto. Para separar los dos diagnósticos el overlay añade
   `blend=0|1` (1 = las caras están en pasada transparente): la captura del
   momento "encima" con `op` y `blend` juntos dice cual de los dos es. El
   campo `cull=` desaparece (siempre sería none); `shape=cyl(fallback)` se
   mantiene.
   **Resuelto en ADR-026**: el fix no fue culling ni profundidad de malla,
   sino orden de pintado — centroide de sort por cara (colocación tipo
   polígono) más `alphaMode` explícito en el material (`Mask` en reposo /
   `Blend` al girar).
13. **Flechas: siguiente cara real, no múltiplo crudo de tick** (rectificado
   tras el re-review; traza medida en el segmento de 2 caras, banda
   [-60, 180], tick 120: LEFT desde 0 → -120 → clamp -60 — el borde de
   banda donde solo se ve casco; LEFT otra vez → delta 0, NO-op permanente:
   el escritorio 2 (120°) era inalcanzable a la izquierda; RIGHT desde 120 →
   240 → normalizado -120 → clamp -60 — un giro de -180° hacia atrás. Con
   los topes simétricos viejos (±80/±120) el caso no aparecía porque los
   múltiplos de tick caían dentro del rango por simetría; la banda
   asimétrica separa "múltiplo de tick" de "cara existente").

   Helper puro `arrowAzimuth(current, direction, tick, min, max,
   faceAzimuths)` en `constants.js`:
   - rango abierto → la cuenta actual idéntica (floor/ceil + umbral
     0.05·tick + avanzar, verbatim: paridad polígono, tambor y hoja-2, con
     359→450 y -1→-90 incluidos);
   - rango con lista de caras → la SIGUIENTE CARA real en la dirección
     pedida (azimut normalizado a (-180,180]; si el current pisa una cara
     dentro del umbral se salta esa cara; sin cara en la dirección,
     envolver dentro de la banda: la más alta para LEFT, la más baja para
     RIGHT). Traza: RIGHT 0→120, LEFT 0→120 (envuelve), RIGHT 120→0 (sin
     -180 hacia atrás), LEFT 120→0;
   - una sola cara (hoja-1 [-80,80] y segmento-1 [-60,60]) → envolver
     devuelve la misma cara → delta 0, sin salto: la hoja-1 queda quieta
     en flechas (hoy el clamp ya normaliza ±360→0 y termina igual; paridad
     exacta, fijada en el test);
   - basura: current NaN → 0; tick inválido con rango abierto → current;
     lista vacía/no-array → la cuenta abierta; lista vacía con rango real
     → current (no-op seguro).

   **Nota ADR-026 (tambor de 3 slots)**: la banda asimétrica [-60, 180] que
   motivó este punto se retiró (giro libre en cilindro); la rama limitada del
   helper sigue viva para la hoja-1 ([-80, 80], una sola cara → la flecha no
   mueve nada) y la rama abierta es ahora también el camino del tambor de
   1-2 slots (tick 120 verbatim, aparcar en slot vacío es válido).

      `Cube.faceAzimuth(index)` es la ÚNICA fuente de los azimuts de cara (el
   propio delegate la usa para colocarse: tambor —a cualquier count, con el
   suelo de 3 slots— y polígono → tick·index; hoja plana → index·180; el
   helper `cylinderSegmentAzimuth` del segmento murió con la banda). En el
   tambor una flecha SÍ puede apuntar a un azimut sin cara — el slot vacío
   del tambor de 1-2, decisión del addendum: aparcar ahí enseña el casco y
   seleccionar es no-op; en los rangos limitados (hoja) sigue imposible.
   `targetAzimuth()` (estados close/distant) consume `desktopAzimuth`
   (cara real) + `clampAzimuthRange` — revisado, no tick crudo. El
   arrastre no cambia: su clamp raw entre [min,max] define bordes de
   banda, no caras, y sigue siendo correcto.

**Porqué**: ADR-001/002/003 ya fijaron el contrato (dos formas, cilindro
desarrollable sin shader, sin piel); esta ADR aterriza las decisiones que
el spec abierto no cerraba: qué significa el desplazamiento en cilindro
(hueco lineal g con negativo → 0, no encogimiento como en el polígono), dónde
vive R respecto a los vértices (primero en la malla centrada en +Z; desde
ADR-026 en la position del nodo con el arco envolviendo la cara, para que el
azimut y el centroide de sort sean la rotación del polígono), cuántas mallas
(una compartida, no N) y qué pasa con 1-2 escritorios y Shape=Cylinder (la
respuesta tuvo tres versiones: topes simétricos ±80/±120, banda asimétrica
[-60,60]/[-60,180, pt.11 original, y la FINAL del usuario: tambor de tres
slots con huecos vacíos y giro libre, pt.11 re-rectificado + ADR-026 — las
bandas con tope «hacían saltos raros y se sentían poco fluidos»). El culling
dinámico (pt.12) se probó para el overlap de la pared interior y se retiró
del runtime: el requisito real es paridad de visión con el polígono
(ADR-023) y el overlap es un problema de orden de pintado, no de
culling — la semilla queda testeada para el fix.

**Alternativas descartadas**:

- `g` como hueco angular (θ_arco = tick − g): el hueco en px dependería de R
  y rompería la paridad con el polígono (mismo valor, mismo aspecto).
- Negativos con R encogido (como en polígono): exige arcos < W → comprime la
  textura → viola ADR-002 (isometría).
- `#Cylinder` nativo recortado o `CylinderGeometry`: UVs y arco propios que
  no dan θ = W/R; ADR-002 ya los descartó.
- Malla nueva por frame o por cara: la primera es innecesaria (solo cambian
  W/H/R en resize), la segunda multiplica los uploads sin beneficio (misma
  geometría para todas las caras).

**Verificación**: `make check` (qmllint de `CylinderArcMesh.qml`;
check-constants: `shape()`, `cylinderRadius()` con clamp y bordes NaN,
`cylinderArcAngle()`, el routing `azimuthRangeFor` (ADR-026; los helpers del
segmento retirado `cylinderArcRadius` / `cylinderSegmentAzimuth` /
`cylinderAzimuthRange` / `cylinderSegmentDesktopAt` salieron con la banda),
`flatAzimuthRange`,
`clampAzimuthRange` (que hereda la cobertura de los retirados
`clampSheetAzimuth` y `cylinderAzimuthLimit`: verbatim, normalización,
límites simétricos, basura), `cylinderCullMode` (fuera→1, dentro→0,
límite 1.05 exacto→0, NaN/radio≤0→0) y `arrowAzimuth` (la traza completa
del re-review (aritmética genérica de rango limitado/asimétrica, hoy solo
cubre la hoja-1 simétrica; la banda [-60,180] se retiró con pt.11), no-op
con una sola cara —hoja-1—, flechas del cilindro 1-2 por la grid abierta
(RIGHT 0→120→240 verbatim), paridad verbatim current±tick con rango abierto
incl. 359→450 y -1→-90,
basura NaN), y `Cube.faceAzimuth` cubierta por la paridad de las listas de
caras de `arrowAzimuth`; check-schema/check-ui: entry
`Shape` ↔ combo `kcfg_Shape` en orden Polygon/Cylinder y clase QComboBox).
Y los checks nuevos: `scripts/check-cylinder.py` instancia la malla REAL
(`CylinderArcMesh.qml` con `ProceduralMesh`, motor QML offscreen sin
pantalla) — tambor cerrado (g=0), tambor abierto (g=100), negativo clampeado
y **tambor de tres slots con g=0 (R = 3W/2π, θ = 120° — el count 1-2 ya no
tiene rama propia: es la fórmula del tambor con N=3)** — y exige vértices
finitos sobre el
radio (cilindricidad), UVs en [0,1] con u lineal en s (isometría) y v por
fila según la convención medida, longitud de arco total = W (integral de
θ·R, también en el segmento), normales radiales, índices en rango y winding
CCW consistente; su `--selftest` comprueba que el validador rechaza **nueve
rupturas** (winding invertido, vértice fuera del radio, u invertida,
arco≠W con θ mal mantenida, v espejada, UV fuera, índice fuera, NaN y
triángulo de menos). `scripts/check-cylinder-wiring.py` ejercita el
**cableado real**: instancia `Cube.qml` completo contra el stub
`org.kde.kwin` con `Shape=Cylinder` — 3 escritorios (tambor:
`cylinderActive` true, `cylinderSegments` false, Loader→Ready con
`cylinderMesh` Geometry no nulo o, sin `QtQuick3D.Helpers`, fallback
`cylinderActive` false sin crash — imprime qué camino se ejercitó), 2
escritorios (segmento: `cylinderSegments` true, `angleTick` 120) y 1
escritorio (segmento de una cara: `cylinderSegments` true, `faceDistance`
3W/2π) — con assert de que el holder recibió el radio correcto
(`hypot(x, z)` de un vértice de la malla ≈ R esperada en tambor y
segmento: cierra el cableado de bindings del Loader) — más la
paridad de culling: con la cámara dentro, en el margen 1.05·R y fuera del
tambor, `faceCullMode` sigue siendo `Material.NoCulling` (el assert
documenta la retirada del punto 12: en runtime la pared interior se ve SIEMPRE,
como en el polígono). Prueba visual en el anidado (actualizada por el
addendum): Shape Polygon vs Cylinder con g=0 y g=100, zoom, la hoja con 1-2
sin cambios **con Polygon** y el **tambor de tres slots con Cylinder** (1
escritorio: cara de frente en reposo + dos huecos al casco; 2: caras en 0° y
120° + un hueco; giro libre sin topes; el DebugOverlay muestra `shape=cyl
R=… g_eff=… blend=…`, con `slots=1/3`/`slots=2/3` y `lim=none` bajo 3, y
`shape=cyl(fallback)` sin Helpers), el overlap de pared interior sobre
frontal **resuelto** (ADR-026 — `op` + `blend` siguen diciendo desde qué
pasada pinta cada frame; si volviera, blend=1 con una trasera encima = orden,
blend=0 = profundidad), los huecos del tambor de 1-2 dejando ver el casco y
las flechas/estados girando fluidos por la grid (el aparcado en slot vacío es
el comportamiento pedido, no un salto).

---

## ADR-026 — Overlap del cilindro: centroide por cara + alphaMode explícito.

**Decisión**: el solapamiento de la pared interior sobre las caras frontales
(problema abierto por ADR-025 pt.12, medido por el usuario en el anidado con
`op=1.00` en reposo y peor al girar) se cierra con dos mecanismos, y ambos
quedan fijados por `scripts/check-cylinder-overlap.py`:

1. **Malla centrada en el nodo, colocación como el polígono** (fix a).
   `cylinderArcGeometry()` genera ahora el arco **alrededor de su propio
   Model**: punto medio en el origen del nodo y eje del tambor en
   `(0, 0, -R)` local — `P(s,t) = (R·sin φ, t − H/2, R·cos φ − R)`. La cara se
   coloca con la regla del polígono: `position = rotar(azimut)·(0,0,faceDistance=R)`
   más `eulerRotation.y = azimut` (la rama `cylinderFaces → position (0,0,0)`
   desaparece de `Cube.qml`). El tambor mundial es idéntico vértice a vértice
   (reparametrización: las capturas del harness antes y después son
   píxel a píxel iguales); lo que cambia es la **clave de orden**: QtQuick3D
   ordena la pasada transparente por el **centro del bbox del objeto en
   mundo proyectado sobre el eje de visión** (`getCameraDistanceSq` usa
   `worldCenterPoint = globalTransform(bounds.center())`, medido en
   qssglayerrenderdata.cpp de Qt 6.12.1). Con los N nodos clavados en el eje,
   esa clave dependía solo del bbox de la malla compartida; con cada arco
   llevando su radio en la `position`, la clave es la del polígono — N
   centroides a distancia R, dos a dos distintos, que es lo que el usuario
   nunca ha visto fallar.
2. **Material de cara: `PrincipledMaterial` con `alphaMode` por umbral**
   (fix b): `faceOpacity ≥ 0.99 → Mask`, `< 0.99 → Blend`;
   `lighting: NoLighting`, `cullMode: NoCulling` intactos (ADR-025 pt.12).
   La causa de que "op=1.00" se comportara como transparente era estructural:
   un `DefaultMaterial` cuyo `diffuseMap` es un `Texture.sourceItem` entra SIEMPRE
   en la pasada transparente — el motor marca transparencia cuando la textura
   del item capturado tiene canal alfa (`prepareImage`, caso `Type::Diffuse`; el
   grab de un `DesktopView` lo tiene siempre) — aunque el `opacity` enlazado valga
   1. Con `PrincipledMaterial` la pasada deja de ser un efecto colateral del
   contenido y pasa a ser lo que el umbral dice:
   - **reposo (Mask)**: los fragmentos con alpha ≥ `alphaCutoff` (0.5) se pintan
     opacos y **escriben profundidad** → una arco lejano no puede quedar
     encima del cuerpo de uno cercano ni aunque el orden falle; los fragmentos
     bajo el corte se descartan → el fondo (wallpaper) sigue viéndose a través
     de los huecos de la textura de cara, igual que hoy;
   - **giro (Blend)**: la semitransparencia clásica de ADR-021, ordenada
     back-to-front por los centroides del punto 1.

   **Acotación del Mask (re-review)**: el modo `Mask` queda **solo en las
   caras cilíndricas en reposo** — la condición del material es
   `faceOpacity < 0.99 || cylinderMesh === null → Blend`: el polígono y la
   hoja nunca tuvieron solape (sus `position` ya son centroides de sort
   distintos, ADR-022) y su look virgen manda (ADR-023) — un `Mask` allí
   recortaría sombras y AA de las ventanas y endurecería las semitransparentes
   (alfa < 0.5, paneles con blur) sin beneficio demostrado. `alphaCutoff:
   0.5` queda **explícito** (no depende del default de Qt: un cambio de
   motor no puede mover el borde duro/suave de los huecos). El check nuevo
   lo fija: el escenario `poly` afirma `Blend` en reposo con malla nula, y
   el assert de `alphaMode` del tambor se condiciona a la malla.

**Medido, no teorizado** (motor real de esta máquina, Qt 6.12.1):

- El overlap **no se reproduce en el harness con colores planos**: allí el
  orden por bbox del código viejo ya daba la cara frontal ganando. El fallo
  del anidado depende pues de contenido real (texturas compuestas del
  escritorio) o de la variante de render de KWin; los dos mecanismos cubren
  ambos causales sin alterar el resultado observable aquí.
- Regresión medida y por eso **descartada**: la rama de reposo `Opaque` (el
  `SetToOpaque` histórico — en Qt 6.12.1 el enum es
  `AlphaMode { Default, Mask, Blend, Opaque }`, el nombre viejo no existe)
  **pinta de negro los huecos de la textura**: ignora el alpha del mapa y
  borra el escritorio que se ve a través de la cara (banda magenta → negra en
  las capturas). De ahí que el reposo sea `Mask`, no `Opaque`.
- Reparto honesto de lo que prueba cada assert del check nuevo: los píxeles
  fijan el **resultado** (la cara cercana manda en su huella en reposo —yaw 0,
  op 1— y a medio giro —yaw 60, op 0.7—; la pared lejana solo aparece por el
  hueco; los huecos de textura siguen translúcidos) — con colores planos
  pasan también con el código viejo, así que son guardia de regresión de
  orden. Los **structurales** fijan el **fix**: posiciones de cara
  pairwise-distintas con `hypot(x, z) = R` y `alphaMode` saliendo del umbral
  (`Mask` con op 1, `Blend` con op 0.7). Con el runtime revertido el check
  falla todos los escenarios (RC=1, verificado fuera del gate; re-verificado
  tras el tambor de tres slots del addendum, que añade el escenario
  `single`).

**Extra del lote — routing de `azimuthRange` testeado**: `ScreenView` elegía
la range por un ternario inline sin ninguna cobertura (intercambiar las ramas
dejaba `make check` verde). Vive `azimuthRangeFor(shape, count, hasArcMesh)`
en `constants.js`, recalibrado con el tambor de tres slots (ADR-025 pt.11,
rectificación final del usuario: la banda [-60,60]/[-60,180] con topes hacía
saltos y se sentía poco fluida — Cylinder con malla gira LIBRE a cualquier
count): tests en `check-constants.qml` — poly1→[-80,80], poly2/3→abierto,
cyl1→abierto, cyl2→abierto, cyl3→abierto, Cylinder **sin malla** (fallback
sin `QtQuick3D.Helpers`) → rango poligonal (la hoja-1 conserva ±80: el dorso
espejado de un quad plano no tiene banda que lo proteja). El routing abierto
es lo que hace trivial el guard «cara de frente»: con 1 escritorio
`desktopAzimuth` = 120·0 = 0 verbatim (ADR-026 fix a puso cada slot a
distancia R en su `position`, así que el tambor de 1-2 comparte también el
orden de pintado del de 3+).

**Porqué**: el usuario definió el contrato en ADR-025 pt.12 — la pared interior
se ve (paridad con el cubo virgen, ADR-023) pero nunca se pinta encima; eso es
propiedad del **orden de pintado**, y la única palanca robusta del orden en
QtQuick3D es el centroide de sort (pasada transparente) más la decisión de
pasada (opaca = profundidad por píxel). El polígono lleva años demostrando esa
combinación; el cilindro ahora usa exactamente la misma.

**Alternativas descartadas**:

- `BackFaceCulling` dinámico fuera de 1.05·R (`cylinderCullMode`): retirado en
  pt.12 — suprimía también la visión por huecos que el usuario defiende; la
  semilla sigue en `constants.js` documentada y testeada.
- `Opaque`/`SetToOpaque` en reposo: negros en los huecos de la cara (medido
  arriba); perdería el escritorio a través de la textura.
- Mantener `DefaultMaterial`: la pasada quedaba decidida por un efecto colateral
  del contenido de la textura (una futura fuente sin alfa cambiaría el orden
  sin tocar nada).
- Dejar la malla en el eje y confiar en el bbox: es justo lo que falló en el
  anidado; la `position` por cara es la única clave que el efecto controla.

**Verificación**: `make check` — `check-cylinder-overlap.py` (nuevo; píxeles +
estructura; necesita pantalla real, se salta sin ella), `check-cylinder.py`
recalibrado (cilindricidad, longitud de arco y winding alrededor del eje local
`(0,0,−R)`; su `--selftest` sigue rechazando las nueve rupturas),
`check-cylinder-wiring.py` (`hypot(x, z+R)` del primer vértice == R, más los
escenarios 1/2 como tambor de tres slots: `cylinderActive`, tick 120,
R = 3(W+g)/2π con el g del harness, rango abierto, slot 0 en azimut 0 —la
guarda «cara de frente»— y slot 1 vacío alcanzable) y
`check-constants` con `azimuthRangeFor` recalibrado (los helpers de la banda
retirada murieron con ella). El escenario `single` de
`check-cylinder-overlap.py` cubre además la intersección de ambos fixes: el
tambor de un escritorio mantiene la cara de frente (slot 0, centro de
pantalla rojo) con la malla re-centrada (ADR-026 fix a no desplaza el azimut:
el arco envuelve el nodo y el nodo sigue la grid del tambor). La verificación visual del overlap
real queda para el usuario en el anidado (`Meta+Shift+K`, DebugOverlay con
`op=`/`blend=`): reposo sin pared sobre frontal, giro con la pared solo por
huecos y cantos, y el wallpaper siguiéndose ver a través de los huecos de las
caras.
