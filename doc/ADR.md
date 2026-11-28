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
`scripts/check-video-dome.py` (retirado por coste, ver doc/trucos-aprendidos.md sección P) exigía `fillMode == Stretch` en el caso 360.
**Verificación**: `scripts/check-video-dome.py` (retirado por coste; sección P de trucos) renderizaba el `ScreenView.qml` real
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
default, check-scene-environment, check-features) y
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
nuevos y los bordes de `clampSheetAzimuth`; el gate de vídeo (retirado, sección P de trucos) renderizaba
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
el gate de píxeles de cilindro, retirado: sección P de `doc/trucos-aprendidos.md`).

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
sigue siendo la hoja plana exacta de ADR-024. 12. **Culling dinámico RETIRADO del runtime (rectificación del usuario)**:
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
`Blend` al girar). 13. **Flechas: siguiente cara real, no múltiplo crudo de tick** (rectificado
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

### Enmienda (2026-11-27) — modularización: `cylinderArcGeometry()` vive en `arcGeometry.js`

El generador de malla salió de `constants.js` hacia
**`package/contents/ui/arcGeometry.js`**, el mismo reparto que la enmienda de
ADR-027 hizo con `capGeometry.js`: `constants.js` queda solo con resolvedores
de valor y fórmulas (`cylinderRadius`, `cylinderArcAngle`, la semilla
`cylinderCullMode`, `CYLINDER_SEGMENTS`), y cada generador de vértices es un
módulo autocontenido (lleva su propia copia del guard `isFiniteNumber`
porque los scripts QML no se importan entre sí; `check-constants.qml` fija
ambos lados). `CylinderArcMesh.qml` importa `arcGeometry.js` además de
`constants.js`. Sin cambio de comportamiento: la fórmula, el fallback de
segmentos (64, fijado por «segments fixed») y los contratos que validan
`check-cylinder.py`/`check-cylinder-wiring.py` quedan verbatim.

---

## ADR-026 — Overlap del cilindro: centroide por cara + alphaMode explícito.

**Decisión**: el solapamiento de la pared interior sobre las caras frontales
(problema abierto por ADR-025 pt.12, medido por el usuario en el anidado con
`op=1.00` en reposo y peor al girar) se cierra con dos mecanismos, y ambos
quedaron fijados por `scripts/check-cylinder-overlap.py` (retirado por coste; sección P de trucos), y la estructura sigue fijada por `check-cylinder-wiring.py`:

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

**Verificación**: `make check` — `check-cylinder-overlap.py` (píxeles + estructura; retirado por coste, sección P de trucos; la parte de estructura quedó en
estructura; necesita pantalla real, se salta sin ella), `check-cylinder.py`
recalibrado (cilindricidad, longitud de arco y winding alrededor del eje local
`(0,0,−R)`; su `--selftest` sigue rechazando las nueve rupturas),
`check-cylinder-wiring.py` (`hypot(x, z+R)` del primer vértice == R, más los
escenarios 1/2 como tambor de tres slots: `cylinderActive`, tick 120,
R = 3(W+g)/2π con el g del harness, rango abierto, slot 0 en azimut 0 —la
guarda «cara de frente»— y slot 1 vacío alcanzable) y
`check-constants` con `azimuthRangeFor` recalibrado (los helpers de la banda
retirada murieron con ella). El escenario `single` de
el gate de píxeles retirado cubría además la intersección de ambos fixes: el
tambor de un escritorio mantiene la cara de frente (slot 0, centro de
pantalla rojo) con la malla re-centrada (ADR-026 fix a no desplaza el azimut:
el arco envuelve el nodo y el nodo sigue la grid del tambor). La verificación visual del overlap
real queda para el usuario en el anidado (`Meta+Shift+K`, DebugOverlay con
`op=`/`blend=`): reposo sin pared sobre frontal, giro con la pared solo por
huecos y cantos, y el wallpaper siguiéndose ver a través de los huecos de las
caras.

### Dos regresiones del tambor de 3 slots medidas por el usuario (ADR-026b)

El usuario midió en el anidado (DebugOverlay) dos fallos del tambor con 1-2
escritorios que ningún check del gate detectó:

1. **`v=4` → la cámara dentro del tambor.** Línea medida exacta (2 escritorios):
   `d=776 v=4 sheet=0 R=776 ... r=786`, y con 1 escritorio `r=32`/`r=28`.
   `r=786 = 4·DistanceFactor(1.75) + faceFit` es el estado `distant` calculado
   con `viewRadius=4`, y `r=32 = 8·4` es el `maxRadius` de la rueda con ese
   `viewRadius`: la cámara queda atrapada DENTRO del tambor (solo casco, dorso
   espejado, «no se puede pasar» al zoom). Causa raíz: ciclo de dependencias en
   `Cube.qml` — `viewRadius` (línea 76, `isSheet ? 0.5·W : faceDistance`) →
   `faceDistance` (rama hoja: `sheetGap`) → `sheetGap` (`0.005·viewRadius`) →
   `viewRadius`. Con `count < 3` existe una fase de hoja (`isSheet` true)
   mientras la cadena del tambor no manda; el disparador medido es un flip
   de `Shape`/status a mitad de pase (el Loader de la malla es **síncrono
   por defecto** — no hizo falta ningún montaje diferido para activar el
   ciclo); cuando la malla entra en juego dentro de ese pase, Qt corta el
   ciclo y deja
   `viewRadius` **congelado en `sheetGap` ≈ max(1, 0.005·R) ≈ 4`** mientras
`faceDistance`se recupera solo a R (de ahí`d=776 v=4`simultáneos). El
log del motor lo confesaba:`QML Cube: Binding loop detected for property
   "viewRadius"`— reproducido fuera de KWin instanciando el`ScreenView.qml`real offscreen (polígono-hoja con 2 escritorios y switch a Cylinder:
mismo`d=776 v=4 r=786`). Con 3+ escritorios `isSheet`nunca es true, el
ciclo no se cierra, y por eso el tambor de 3 funcionaba. Fix: la rama de
cilindro sale ANTES de tocar la cadena de hoja —`viewRadius: cylinderActive ? cylinderRadius : isSheet ? 0.5 * faceSize.width : faceDistance`— así con`cylinderActive`el valor es`R` estructuralmente (`viewRadius ===
   faceDistance === cylinderRadius`para cualquier count) y el grafo queda
acíclico en las tres ramas (hoja:`viewRadius`no lee`faceDistance`;
polígono: `faceDistance`no lee`sheetGap`; cilindro: ninguna lee la cadena
de la otra). Consecuencia fijada por test: close/distant y los topes de
rueda miden contra R — con 1 escritorio `r=32`/`r=28` son imposibles
(`minRadius = 0.6·R`).
2. **Flechas que aparcan en el slot vacío.** Con 2 escritorios la grid de 3
   slots tiene un hueco (240°): la aritmética ±tick verbatim del rango abierto
   paseaba la cámara `0 → 120 → 240`, y en 240 no hay delegate — Enter/click
   son el no-op guardado y la siguiente flecha volvía a otro hueco o sumaba
   120 sobre el vacío: «no se puede pasar» entre los dos escritorios reales
   (medido: `yaw=-103.9 f0:-0.24 f1:-0.72` atascado). Fix en
   `Constants.arrowAzimuth`: con rango ABIERTO y la lista de caras reales
   (parámetro `faceAzimuths`, ya se pasaba) con **huecos** en la grid
   (`faces.length < 360/tick` — el tambor de 1-2), la flecha avanza a la
   siguiente CARA REAL en la dirección pedida con wrap completo y camino más
   corto (n=2: 0↔120 por ambos lados, nunca 240; n=1: no-op; desde un punto
   fuera de grid —drag— aterriza en la cara real más cercana en la dirección
   pedida). Con la grid LLENA (tambor 3+, polígono, hoja doble cara) corre la
   cuenta vieja verbatim — paridad ADR-022/024 intacta, ningún resultado
   cambia fuera del tambor con hueco. La rama LIMITADA (hoja-1) no se toca.
   El drag conserva el giro libre: puede dejar el casco en pantalla, y las
   flechas salen de ahí a una cara real.

**Verificación ADR-026b**: `check-constants.qml` fija las flechas del tambor
(n=1 no-op, n=2 0↔120 ambos lados, n=3 grid intacta, polígono 4 caras
verbatim); `check-cylinder-wiring.py` exige en los tres counts
`viewRadius === faceDistance === R` + assert estructural «`viewRadius` no es
`sheetGap`» (>100 px de diferencia con R=1270) + close/distant > R, y añade
el escenario **flip** — `ScreenView.qml` real offscreen, hoja de 2
escritorios y `Shape` a Cylinder en caliente, la secuencia que congelaba
`v=4` — parseando el DebugOverlay y exigiendo `v == d == R`, `r` == la
distancia `distant` del tambor nuevo (vive el binding de estado o
`resyncToState` por `onCylinderActiveChanged`) y `sheet=0`
(con el código viejo este escenario falla: `v=4`, medido; sin
`QtQuick3D.Helpers` el flip **se salta con aviso** — el fallback hoja es
configuración soportada y lo cubren los escenarios de `Cube`);
el gate de píxeles retirado tenía el escenario **two-slot** (2 escritorios,
yaw 0: la fila central es el rojo de la cara del slot 0 — la cara de frente
también con huecos).
---

## ADR-027 — Tapas: dos superficies de cierre inscritas en el sólido.

**Decisión**: el sólido gana dos superficies de cierre — la **tapa superior** y
la **inferior**, una en cada extremo del eje Y (`y = ± faceHeight/2`) —,
habilitables por separado (`CapTop` / `CapBottom`, Bool, default false). Cada
tapa pinta un contenido propio con su propia transparencia:

| Clave             | Tipo  | Rango                                            | Default   |
| ----------------- | ----- | ------------------------------------------------ | --------- |
| `CapContent`      | Enum  | Color 0 / Gradient 1 / Image 2                   | 0         |
| `CapColor`        | Color | —                                                | `#1b3fd8` |
| `CapColor2`       | Color | —                                                | `#0a1a5e` |
| `CapGradientType` | Enum  | LinearVertical 0 / LinearHorizontal 1 / Radial 2 | 0         |
| `CapGradientStop` | Int   | 0–100                                            | 50        |
| `CapImage`        | Url   | —                                                | vacío     |
| `CapImageFit`     | Enum  | Cover 0 / Contain 1 / Stretch 2                  | 0         |
| `CapOpacity`      | Int   | 0–100                                            | 80        |

La geometría es la del sólido que cierra, sin inventar otra fuente:

- **Polígono** (3+): **N-gono regular** con N = `geometryCount`, apotema =
  `faceDistance` (`W/2 / tan(π/N) + CubeFaceDisplacement`), de modo que cada
  lado cae sobre el plano de una cara — la tapa queda **inscrita** en el prisma
  y no sobresale. El radio circunscrito es `apotema / cos(π/N)`, derivado, no
  una clave.
- **Cilindro** (tambor, cualquier count incluido el tambor de 3 slots con 1-2):
  **disco** de radio `R = cylinderRadius` (`N·(W+g)/2π`), triangulado en abanico
  con `CYLINDER_SEGMENTS` (64); tapa también las cuñas vacías del tambor.
- **Hoja 2D** (`Polygon` 1-2): sin volumen → tapas **deshabilitadas por código**
  (no una opción), igual que el Interior: una hoja no encierra nada.

UNA sola `ProceduralMesh` por forma, compartida por las dos tapas (espejadas
por rotación), igual que las caras comparten `CylinderArcMesh` (ADR-025). Sin
shader. Culling `Material.NoCulling` (paridad con las caras, ADR-025 pt.12
revertido): la tapa se ve igual desde arriba y desde abajo. Las tapas aportan
centroides de ordenación propios en Y (±H/2), no tapan las caras frontales, y
extienden la regla de ADR-026 (centroides + `alphaMode` explícito):
`alphaMode: Blend` porque el contenido tiene alfa.

**Porqué**: el usuario pidió cerrar el sólido por arriba y por abajo con
superficies cuyo contenido y transparencia se puedan modificar e independientes
entre sí ("una tapa donde podremos poner una figura, un degradado, una imagen,
etc."). ADR-003 no se toca en lo que importa: la «piel» lateral sigue sin
existir; la tapa es una superficie de cierre transversal, no una pared entre
caras. Reusar `faceDistance` (polígono) y `cylinderRadius` (cilindro) mantiene
una sola fuente de geometría, y compartir una malla entre las dos tapas sigue el
patrón de ADR-025 (una malla para las N caras), sin duplicar el upload de
vértices.

**Descartado (y por qué)**:

- **Disco para el polígono** en vez de N-gono: un disco de radio igual al
  apotema sobresaldría de las paredes por los vértices; el N-gono inscrito (lado
  = plano de cara) es el que coincide con la forma.
- **Radio circunscrito como clave/configuración**: sería una segunda fuente de
  verdad; se deriva del apotema (`apotema / cos(π/N)`).
- **Tapa opaca por defecto**: taparía el casco y las caras a través de los
  huecos; `CapOpacity` default 80 deja ver a través.
- **`CapOpacity` como Double**: se eligió **Int 0–100** por paridad con
  `DimWhileRotatingAmount` y el resto de claves 0–100 del KCM; el helper
  `capOpacity()` traduce a 0..1.

**A medir en la implementación**: coste de las dos mallas por forma y el
comportamiento visual del disco sobre el tambor de 3 slots (cuñas vacías tapadas
por el disco); sin métricas previas — se fijan en el anidado.

### Enmienda (2026-11-27) — la tapa se acota a las ESQUINAS de cara, no a la intersección de planos

**Qué se rompió**: el N-gono inscrito de arriba usa `rc = apotema / cos(π/N)`,
que es la distancia a la **intersección de los planos** de dos caras consecutivas.
Eso coincide con la esquina de cara solo mientras las caras se tocan
(`CubeFaceDisplacement = 0`). Con separación positiva el ancho de cara W manda, y
la tapa sacaba puntas tangenciales fuera de la esquina (medido con W = 2560, la
protrusión `rc·sin(π/N) − W/2`):

| N   | d   | rc     | lateral del vértice | sobresale                   |
| --- | --- | ------ | ------------------- | --------------------------- |
| 3   | 0   | 1478.0 | 1280.0              | 0.0 px                      |
| 3   | 100 | 1678.0 | 1453.2              | **+173.2 px (6.8 % de W)**  |
| 3   | 300 | 2078.0 | 1799.6              | **+519.6 px (20.3 % de W)** |
| 4   | 100 | 1951.6 | 1380.0              | **+100.0 px**               |
| 5   | 100 | 2301.3 | 1352.7              | **+72.7 px**                |

El gate de la época (check-cap: punto medio del lado contra plano + rejilla de
azimut + rejilla de la hoja) no podía verlo: los vértices bugeados caen EXACTAMENTE
sobre dos planos de cara; lo que cruzan es la **esquina**. Captura real del usuario
en el anidado: overlay `shape=poly n=3 tick=120 d=395` con puntas visibles. La tapa
inferior es la misma malla rotada 180°, fallaba igual.

**Qué se decide**: el anillo va a las **esquinas reales de cada cara**. Los vértices
por cara k (azimut `step·k`, `step = 2π/N`) son el punto local `(apotema, ±W/2)`
→ radio `rho = hypot(apotema, W/2)`, azimuts `step·k ± betaCara` con
`betaCara = atan((W/2)/apotema)`, y el hueco entre caras se cierra con una
**cuerda recta** (esquina derecha de k → izquierda de k+1). Dos **ramas
explícitas**, no un clamp único:

- `betaCara ≥ halfStep − 1e-9` ⟺ d ≤ 0 → **N-gono inscrito** (N vértices a
  `apotema/cos(π/N)`), el de siempre.
- `betaCara < halfStep − 1e-9` ⟺ d > 0 → **2N vértices** a `hypot`.

La banda de 1e-9 rad colapsa el caso d = 0 (y su jitter de un ulp, medido a N = 4:
`atan(1280/1280.0000000000002)` cae por debajo de π/4) sobre el N-gono: un solo
vértice donde las dos esquinas coinciden, sin triángulos astilla. Las ramas
coinciden exactamente en d = 0 (`hypot(a₀, W/2) = a₀/cos(π/N)`; diferencia medida
≤ 2.3e-13 px), así que cruzar el cero del slider no produce salto, y con d < 0 la
tapa es el N-gono virgen: **cero regresión** en el rango ADR-022.

**Por qué no basta `beta = min(betaCara, halfStep)`**: con d < 0 esa regla deja el
vértice en el azimut de la intersección de planos pero con el radio de esquina — y
sale **fuera del plano de cara** (medido n=3 d=-200, W=2560: proyección 694.4 vs
apotema 539.0; la tapa asomaría por las paredes, el fallo opuesto al que se
arregla). La ramificación explícita elige también el **radio** (rc vs rho), no solo
el azimut; el clamp puro solo puede elegir una de las dos cosas y se queda sin
contrato con caras solapadas.

**Invariante dura (nuevo contrato del gate)**: ningún vértice del anillo puede quedar
fuera del plano de ninguna cara — `max over (v,k) de dot(v, n_k) ≤ apotema + eps` —
y ningún vértice sobre un plano de cara puede cruzar la esquina de esa cara —
`|dot(v, t_k)| ≤ W/2 + eps`. Ambas, **por cara y en el marco local de la cara**
(`n_k = (sin step·k, cos step·k)`, `t_k = (cos step·k, −sin step·k)`), nunca contra
un máximo global de coordenadas: el anillo correcto con n=3 d=300 tiene
`max |x| = 1539.8 > W/2 = 1280) porque las esquinas de las caras laterales caen
fuera del eje X del mundo (una aserción global daría falso rojo sobre la malla
buena). Los lados de hueco cumplen además `dot(mid, n_k) < apotema` por identidad
(`= apotema − d·sin²(π/N)`, medido −150 px a n=4 d=300): la tapa sella las caras,
**no** los huecos — el casco sigue viéndose a través de ellos.

**Consecuencias de código**: `capPolygonGeometry` pasa a firma
`(apotem, faceWidth, sides, halfHeight)` — `faceWidth` era la entrada que faltaba
(sin ella la tapa solo podía guiarse por los planos). El generador se traslada de
`constants.js` a un módulo propio, `package/contents/ui/capGeometry.js`
(`capPolygonGeometry` + `capDiscGeometry`; constants.js venía ya pasado de presupuesto
de líneas y el anillo es una responsabilidad única). `CapMesh.qml` expone
`property real faceWidth` y `Cube.qml` lo enlaza con
`item.faceWidth = Qt.binding(() => cube.faceSize.width)` — el grafo de bindings de la
tapa sigue leyendo solo geometría existente (nunca `viewRadius`), ACíclico como exige
ADR-026b. `capDiscGeometry` NO cambia (el disco no tiene esquinas de cara que cruzar:
R ya es la fuente única). No hay claves nuevas: `faceDistance`, `geometryCount` y
`faceSize` ya existían; sin bump de versión (0.0.0.5 no publicado).

**Gate (scripts/check-cap.py/.qml, extendido)**: contrato bidireccional por régimen
(N-gono con d ≤ 0 colapsado y verificado; 2N esquinas exactas ±W/2 con d > 0 más
cuerdas de hueco dentro del plano), la aserción anti-punta `|tangencial| ≤ W/2` y la
invariante de prisma, sobre las dos mallas REALES (esquinas a n=4 d=100 e inscrita a
n=5 con el mismo apotema) más la degenerate `faceWidth = 0`. `--selftest`: 17
detecciones (las 8 mutaciones clásicas + 3 regresiones del bug del usuario: anillo
pre-fix bajo d > 0, esquina deslizada más allá de W/2 manteniendo plano/normales/UVs
coherentes, y vértice fuera del plano) + 4 sondas de aislamiento que mantienen cada
rama de `_edge_problems` y ambas aserciones nuevas independientemente matables.

### Enmienda 2 (2026-11-27) — el eje de giro de la tapa inferior era WRONG; el material sigue la regla ADR-026; Arrow (3) es el contenido por defecto

**Qué reportó el usuario** (anidado 1600×900, overlay
`shape=poly n=3 tick=120.0 d=472 v=472 pitch=30.0 yaw=154.3`, ambas tapas,
contenido Color azul, opacidad 80): la tapa «se dibuja por encima de las caras y
ventanas, cruzando el sólido», «no tapa el hueco», y la pista decisiva: _«el
error pareciera que está 180° volteado»_.

**La premisa del descarte inicial era falsa (refutada con píxeles).** Se había
argumentado que `eulerRotation.x: 180` «manda α → −α» y que el conjunto de
azimuts del anillo es invariante bajo ese mapa, concluyendo que la tapa
inferior no podía estar girada. Las dos mitades eran ciertas; la unión, no:
**la rotación 180° sobre X manda (x,z) → (x,−z), es decir azimut α → 180°−α,
que NO es simetría del anillo de esquinas** `{59.47°, 60.53°, 179.47°, 180.53°,
299.47°, 300.53°}` (las aristas largas abrazan las NORMALES de cara
{0°,120°,240°}, las cuerdas cortas los HUECOS {60°,180°,300°}). Aplicar
α→180°−α equivale a **girar el anillo 60° = medio tick**, y el gate
el gate de píxeles de tapas (retirado por coste; sección P de trucos), renderizando el `Cube.qml` REAL con la
geometría exacta de la captura, lo midió:

- la tapa inferior rotada con X (v3) y la MISMA malla sin rotar (v4) daban
  siluetas DISTINTAS: mirror-symdiff de 78 a 220 celdas por escena (p. ej.
  [−30/0]: v3 `cross=64 caplost=112 gapopen=2 outside=106` frente a v4 todo
  ceros). El dump ASCII mostraba el anillo espejado clavado en la cara roja
  frontal — literalmente «cruzando el sólido»;
- geométricamente: los vértices del anillo espejado alcanzan
  ρ·cos(0.53°) = 928.4 sobre la normal de cara cuyo plano está a 471.9 → la
  tapa asomaba por las paredes (queja 1); y en el azimut del hueco (60°) la
  frontera espejada caía a 472 en vez de 928 → la esquina quedaba abierta
  (queja 2). Ninguna de las dos era un problema de orden de pintado;
- el mapa que vuelca la normal +Y → −Y **y** preserva el anillo es la
  rotación 180° sobre **Z**: (x,z) → (−x,z), α → −α (la simetría real). Con
  `eulerRotation.z: 180` el mirror-symdiff v3-vs-v4 pasó a **0 celdas en las
  14 filas** del barrido ±30 × 7 yaws y todos los contadores a cero.
  La intuición del usuario («180° volteado») era exacta: el anillo estaba
  girado medio tick.

**Segundo hallazgo (régimen de material).** `Cap.qml` fijaba
`alphaMode: Blend` siempre; el snapshot del motor midió `mask=False` también a
`CapOpacity` 100 (evidencia estructural). Se extiende a las tapas la regla de
ADR-026: **`Mask` con `alphaCutoff: 0.5` explícito desde ≥ 0.99** (los
fragmentos conservados escriben profundidad: un empate de sort ya no puede
pintar una tapa lejana sobre una cara cercana) y **`Blend` por debajo** (el
default 80 sigue siendo translúcido real). NO `Opaque`/`SetToOpaque`:
pintarían de negro los agujeros de alfa (medido en ADR-026). Nota honesta:
el barrido por software NO reprodujo ningún cruce causado por el orden de
pintado — todos los cruces venían del anillo mal girado; el cambio de régimen
se aplica por contrato (en GPU real el pase transparente solo tiene el sort
de centroides como guardaraíles) y el gate lo fija estructuralmente.

**Tercera decisión: `CapContent.Arrow` (índice 3) como DEFAULT definitivo.**
Petición del usuario: «pon por default una imagen con una flecha que apunte
arriba para que puedas identificar la rotación que tiene». Un color uniforme
no permite leer rotación ni espejo —no se distingue «la tapa está girada» de
«la tapa se pinta encima», la confusión que retrasó este diagnóstico—, y un
marcador asimétrico lo hace visible a simple vista Y medible con píxeles.
Design (sin asset binario, regla de AGENTS.md): `CapArrow.qml` (el único
fichero de tapas que importa `QtQuick.Shapes`, cargado tras `Loader` — patrón
HullRadial ADR-022) pinta fondo `CapColor`, **flecha cian** (#00ffff) hacia el
borde superior del ítem y **cuadrante magenta** (#ff00ff) en la esquina
superior-izquierda. El cuadrante existe porque la flecha sola es simétrica
izquierda-derecha: un espejo podría leerse como giro; el cuadrante rompe esa
ambigüedad (el espejo lo mueve de lado x, un giro lo llevaría a otra esquina).
Sin Shapes: la tapa degrada a `CapColor` plano y avisa UNA vez
(`surfaceDegraded`). `Arrow` se AÑADE AL FINAL del enum (los índices
guardados no se mueven); kwinrc existentes conservan su entero; valores
desconocidos siguen cayendo a Color. Con `DebugOverlay` activo el contenido
se fuerza a Arrow cualquiera que sea el valor guardado.

**Convención de «arriba» (MEDIDA contra el mesh real, no asumida).** La UV
de la malla es `u = 0.5 + x/(2ρ)`, `v = 0.5 + z/(2ρ)` sobre el cuadrado del
ítem grabado. El PNG asimétrico y la tabla `arrow-*` del gate fijaron el
mapeo: **borde superior del ítem ↔ v → 1 ↔ +z local**, es decir el azimut de
la cara 0 (el escritorio 1): la flecha de ambas tapas apunta SIEMPRE hacia la
cara del escritorio 1, y al girar el sólido se ve girar con él; en reposo con
la vista lejana (cámara ligeramente por encima) se lee «hacia el frente».
El flip Z de la tapa inferior conserva v (la flecha sigue apuntando al mismo
azimut) y espeja u: números medidos en [−30/0], cuadrante bottom=(534.2,
272.5) vs loose=(265.8, 272.5) — misma fila (Δy = 0.0), x espejada alrededor
del eje de la flecha (|Σx − 2·400| = 0.6 px) — y el par entre cámaras
top@+30=(266.5, 175.6) vs bottom@−30=(534.2, 272.5): Σx = 800.7 y Σy = 448.1
(los dos espejos de pantalla, Δ ≤ 1.7 px). El contenido (Image) de la tapa
inferior sale, por tanto, **espejado horizontalmente** — consecuencia
direc­ta del flip de anillo correcto, visible por diseño gracias al cuadrante.

**Puertas.** Gate de píxeles `scripts/check-cap-overlap.py/.qml` (retirado por coste el 2026-11-27; recuperable según doc/trucos-aprendidos.md sección P) estuvo enganchado a
`make check` (arranque compartido vía `qml_check_harness.view_boot`), partido en
dos ficheros por el tope de 1000 líneas: el **driver** (grabs reales y comparación
de píxeles) y su **oráculo geométrico** `scripts/cap_overlap_oracle.py` (ambos retirados: sección P de
`doc/trucos-aprendidos.md`), que solo
usa `math` + `cap_contract` (sin PySide6). Por eso el `--selftest` del oráculo
corre **sin pantalla ni GPU** y exige rechazar las escenas sintéticas trucadas
(cap bleed, paint outside, hole open, face wins, la identidad de espejo del propio
oráculo y la fila de control `expect=0`, que prueba que el detector no es trivial),
quedando mudo en la limpia; los píxeles del driver sí necesitan pantalla real y se
salta con exit 0 sin ella. Contrato de material
(Mask/Blend por umbral con cutoff clavado) y de wiring (nodos ±H/2, rz=180)
leídos en vivo del motor. `check-cap.qml` pasa sus Modelos de muestra a Z.
Tapas apagadas (default del usuario) → render idéntico a 0.0.0.4 (contrato
intacto); sin claves nuevas; sin bump de versión (0.0.0.5 no publicado).

## ADR-028 — Capas de ventana: modelo H (huecos en la cara intacta).

**Decisión**: `WindowLayering` (Bool, default **false** — paridad píxel con el
cubo virgen, patrón opt-in de las tapas, ADR-027) convierte cada ventana de una
cara en un quad propio empujado hacia dentro según su rango de apilado. La cara
**no se mueve**: sigue siendo la superficie del shell, y su grab suelta
(`wId = ""`) exactamente las ventanas que ganan quad, dejando huecos transparentes
detrás de los cuales flota cada capa. Fórmula y presupuesto por representación en
ARQUITECTURA §2.4; reglas completas en requerimientos §2.1. Puntos:

1. **Huecos (H), no pared retraída (P) ni quads exteriores (F).** La cara de
   kube-effect es el grab del escritorio completo (wallpaper incluido): P
   arrastraría el wallpaper al fondo del cubo y abriría la silueta al girar (se
   miraría dentro del sólido por cada cara, rompiendo el cilindro cerrado de
   ADR-025/026); F cruzaría paredes y caras vecinas al orbitar («ventanas
   hundiéndose a través del escritorio»); y una cara que conserve sus ventanas
   opacas frente a la pila (C) es muerta: el `Mask` en reposo escribe profundidad
   y la ventana plana ocluye a su propia capa.
2. **El hueco es el recorte.** Cada quad queda recortado por el hueco de su cara en
   cualquier vista, así que la **hoja 2D** (1-2 escritorios, sin interior) puede
   llevar capas con presupuesto = cap directo (150 px) — detrás solo hay vacío y no
   hay paredes que cruzar. En sólidos (polígono ≥3, tambor) sigue
   `min(faceDistance · 0.5, cap)`; medido: con `faceDistance = sheetGap` de la hoja
   la fórmula del sólido aplastaría el stack a ~1 px.
3. **LOD = presupuesto de coste, no de orden.** El culling de `Model` no se
   propaga al `Texture.sourceItem`: capa instanciada = captura por frame aunque no
   se vea. `WindowLayerLodFaces` (0–8, default 1, 0 = todas) limita la instanciación
   por distancia de índice al escritorio actual. El pintado no depende del LOD
   (centroides + umbral Mask/Blend, ADR-026). Se retira de los docs la frase
   «obligatorio»: es obligatorio *para el coste* en sesiones con muchas ventanas;
   puede ponerse a 0 y medir. No reduce el grab de la cara (ADR-023 sigue intacto).
4. **Descartes**: solo las ventanas con capa se sueltan del grab. Docks y
   ventana-wallpaper quedan **planos** (hueco sin quad detrás = shell abierto);
   minimizadas no existen. Soltar = `wId = ""` (QUuid nulo — un `0` entero no
   libera la captura, trucos-aprendidos §N).
5. **Picking**: quads `pickable` → clic = `switchTo(desktop)` (lo de la cara).
   Activar la ventana clickeada queda **documentada como feature futura del módulo
   nativo**: `Workspace::activateWindow` no es QML-expuesto para efectos (medido en
   `/usr/include/kwin`: `Window` expone solo `setMaximize`). Esta feature no toca
   `native/` y el efecto debe seguir funcionando sin compilar.
6. **Claves y UI**: cuatro claves sin enums nuevos (KConfigXT: Int/Double puros).
   `WindowLayering` en la pestaña Ventanas del KCM (placeholder existente);
   `WindowLayerGap`, `WindowLayerLodFaces` y `WindowLayerPlateOpacity` en Avanzado
   (ADR-014). La pila completa (quads + plate) multiplica la opacidad de la cara
   (ADR-021): al girar funda la pila entera, no solo la base.
7. **Alcance 0.0.0.6, por pasos**: polígono (sólido ≥3 + hoja 1-2, funciona desde 1
   escritorio), luego tambor (cilindro 1-2). Si la verificación en el anidado no
   cierra en el tambor (coste o visual), las capas del tambor se apagan por código y
   esa fase se pospone — misma versión. Curvar/deformar capas con el cilindro y las
   colisiones con otros efectos quedan como features futuras con clave propia
   (esta feature: quads planos sobre la normal de la cara).
8. **Código**: helpers puros en módulo nuevo `layerGeometry.js` (rank, fittedGap,
   layerDepth, plateDepth — patrón arcGeometry.js/capGeometry.js de la enmienda de
   ADR-027: constants.js guarda solo resolvedores de valor). `constants.js` (882
   líneas) NO se splitea aquí: queda anotado como refactor posterior independiente,
   sin mezcla con la feature.

**Porqué**: es el estrato hacia adentro del sólido ya cerrado
geométricamente (cilindro 0.0.0.4, tapas 0.0.0.5); cada capa es un quad con su
`WindowThumbnail` (`Texture.sourceItem`) y hereda directamente la regla de
sort-centroides y el umbral alphaMode Mask/Blend de ADR-026; DesktopView ya tiene
el `WindowFilterModel { screenName }` — es extender la maquinaria existente, no
inventar. Y es la deuda que ADR-023 dejó escrita: el ahorro real por distancia llega
con `WindowLayerLodFaces`, ahora con presupuesto de coste documentado.

**Puertas**: gate offscreen en el harness extendido (stub de WindowFilterModel con
N ventanas por cara y `stackingOrder` distintos) y 5 asserts: monotonía estricta de
profundidad por rank (dos capas nunca coplanares); todo ≤ cap con fittedGap
repartido; caras fuera de LOD no instancian quads; cada ventana con capa tiene
`wId = ""` en el grab de su cara; gap = 0 → todas a −ε (paridad con el plano). Lo
visual se verifica en el anidado (usuario): blend al girar (pilas ajenas visibles
por transparencia), ángulo de dos caras simultáneas, vista superior/inferior con
muchas ventanas, borde del hueco (el cutoff 0.5 corta en seco las sombras AA en
reposo — riesgo conocido), rejilla del wallpaper para confirmar que nada asoma del
hueco, gap 0 vs 120. `features.json`: window-layering planned→stable con
`since 0.0.0.6` y metadata 0.0.0.5→0.0.0.6 en el mismo commit final.

### Enmienda (medida en el anidado 2026-11-27) — la pila va hacia FUERA (+z); el plate vela los huecos

**Qué midió el usuario** (anidado, polígono 3 escritorios, pitch=30, yaw=71,
opacidad 1.00, gap=120): con la pila empujada hacia DENTRO los huecos de la cara
dejaban ver el **interior del sólido** — cuña blanca de los quads/caras lejanas y
la etiqueta del wallpaper «ABA» espejada a través de los huecos — y las ventanas
se leían **hundidas dentro del cubo**. Además las capas interiores competían con
la propia cara en el sort por centroides de la pasada transparente (ADR-026): al
girar **parpadeaba el quad entero** (quad y cara quedaban casi coplanares por
delante y por detrás según el ángulo).

**Se adopta la dirección hacia FUERA**: +z sobre la normal de la cara, la ventana
de mayor `stackingOrder` es la **más cercana al observador** (la más exterior).

- Fórmula: `layerDepthOut(rank) = rank · fittedGap + ε` con
  `fittedGap = min(WindowLayerGap, cap / max(1, maxRank))` — rank 0 (la de abajo)
  queda casi pegada a la cara (+ε) y la más exterior cae EXACTO en el cap cuando
  el stack no cabe (paso repartido, sin clamp por capa). El hueco en el grab **se
  queda**: sin él la ventana plana y su quad se dibujarían doble.
- El **plate pasa a z = −2**: justo detrás del plano de la cara, delante del
  interior. Su papel nuevo es **velar los huecos** para que no asome el interior
  del cubo por ellos; queda estrictamente detrás de TODOS los quads (−2 < +ε),
  así que nunca tapa una ventana.
- Sort: el quad queda **estricto delante del plano de su cara** en cualquier
  pose, el problema del parpadeo desaparece con la regla de signo (la cara sigue
  ordenada por su centroide ADR-026; el quad de su ventana está siempre entre la
  cara y el observador).
- Presupuesto: el `min(faceDistance · 0.5, cap)` por forma **queda sin efecto** —
  cap directo (150 px) en TODAS las formas. Hacia fuera no hay paredes interiores
  que proteger; `maxLayerDepth()` desaparece del módulo.
- **Por qué el descarte original del modelo F (quads exteriores) NO aplica aquí**:
  el fallo medido en la exploración vieja era cruzar paredes y doblar la
  superficie **sin huecos** (la opaca tapaba a la capa y se veía el doble). Aquí
  la cara tiene el hueco exacto de cada ventana y el plate vela el interior: no
  hay doble dibujo y no se mira dentro del sólido.

**Trade-off aceptado**: al orbitar, los quads pueden **salir de la silueta de su
cara** — ventanas flotando sobre el escritorio. Es el look pedido (metáfora del
escritorio), no un defecto; la rejilla del wallpaper direccional del arnés
permite medir que el quad no deforma la cara.

**Gates actualizados**: `layers_contract.py` exige z estrictamente CRECIENTE con
el rank y POSITIVA; la más exterior EXACTA en cap + ε con overflow (todas las
formas, hoja incluida); gap 0 → todas a +ε; plate SIEMPRE en −2 y detrás de
todos los quads. El selftest añade los rechazos «plate delante de la capa de
abajo» y «plate fuera del plano de velo» (y la fórmula heredada −(maxDepth+2) ya
no pasa).

**UI del KCM (mismo 2026-11-27, sustituye el punto 6)**: `WindowLayerGap` y
`WindowLayerPlateOpacity` **no** van en Avanzado — son configuración normal de la
feature y viven en la pestaña **Ventanas** junto al toggle (deshabilitados hasta
que `WindowLayering` está activo, patrón dim-amount). **Avanzado** conserva SOLO
`WindowLayerLodFaces`, que sí es ajuste fino: presupuesto de coste GPU por frame,
no de aspecto. Las claves de main.xml y sus rangos/default no cambian; solo se
reubica la UI (gate: check-ui/check-schema validan widget, tipo, rango y
conexión por nombre, sin depender del tab).

**Tercera corrección (medida 2026-11-27) — el stack flota ENTERO**: con la fórmula
de arriba rank 0 quedaba en el +ε puro y la ventana de abajo (la maximizada del
arnés) se leía «pegada al escritorio todo el tiempo». Nuevo ladder:
`layerDepthOut = (rank + 1) · fittedGap + ε` con
`fittedGap = min(WindowLayerGap, cap / (maxRank + 1))` — la de abajo arranca a
+paso, la de arriba cae EXACTA en cap + ε cuando no cabe (una sola ventana con
gap grande: exactamente a +cap), la monotonía por rank y el gap 0 → todas a +ε
se conservan intactos. Gate: cláusula (b) espejada + rechazo sintético nuevo
«bottom quad anchored on the plane with gap > 0» (el bug visto) y unidad
single-window a +cap.

**Orden por profundidad en reposo (medido 2026-11-27, segunda corrección del
flip)**: con los quads en `Blend` fijo QtQuick3D ordena la pasada transparente
por **centroide**, y el centroide de un quad = centro de cara + offset lateral
de la ventana + profundidad exterior — no respeta el rank. Medido en el anidado
con capas hacia fuera: en ángulos oblicuos EN REPOSOS había cambio de orden
entre quads (la ventana de menor rank dibujada encima de la de mayor) y quads de
caras vecinas intercalándose. Los quads adoptan el umbral ADR-026 de la cara
sobre su opacidad efectiva: `≥ 0.99 → Mask` (con `alphaCutoff` clavado a 0.5,
mismo argumento: no depender del default de Qt) y `< 0.99 → Blend`. En reposo el
quad entra al pase opaco con **escritura de profundidad**: el orden se resuelve
por geometría real (la capa más exterior gana el píxel); el grab de la cara
(Blend en las formas planas, alfa 1 en los píxeles del wallpaper) tapa por
depth-test los quads lejanos y los huecos siguen dejando ver el plate/interior
como hasta ahora. A diferencia de la cara —cuyo Mask quedó acotado al cilindro
porque la pila plana nunca se solapaba—, los quads se solapan entre sí a
cualquier forma, así que el umbral corre en polígono, hoja y tambor por igual.
Trade-off medido y aceptado: en reposo el borde AA/sombra de la ventana se corta
duro en el cutoff (la misma clase de efecto ya documentada del hueco en
cilindro). El plate conserva `Blend` siempre: color uniforme, sin contenido que
ordenar.

**Opacidad propia de las capas al girar (WindowLayerRotationOpacity, mismo
2026-11-27)**: la clave nueva (Double 0–1, default **0.7**) fija la opacidad
**absoluta** del quad durante el giro; **en reposo las capas valen SIEMPRE 1**
(ventanas sólidas, umbral Mask incluido, sea cual sea el rest de las caras). El
valor viaja por el mecanismo ya existente, cero machinery nueva:
`ScreenView.layerOpacity = Constants.faceOpacity(1, LayerGeometry.rotationOpacity(raw),
cubeMoving)` con el mismo `Behavior`/`FaceFadeMs` de las caras; el umbral de
`alphaMode` de los quads mira ESTA opacidad efectiva — con la clave a 1.0 las
ventanas quedan sólidas y ordenadas por profundidad **también al girar** (efecto
buscado). **Paridad por default**: 0.7 es también el default de
`FaceRotationOpacity` y `Constants.faceOpacity(1, v, true) == v` para todo v
alcanzable (aserción numérica en check-constants), así que out-of-the-box la
pila funda exactamente como el escritorio (comportamiento de ADR-021 conservado
como default; el fundido residual por centroide solo dura mientras gira).
**Paridad con el flag apagado (confirmación del usuario)**: sin capas las
ventanas son píxeles del grab y comparten su transparencia — la clave es
completamente inerte a cualquier valor (0.2/0.7/1.0 probados en el gate): cero
quads, cero layeredIds, grab íntegro y los materiales VIVOS de la cara siguen
dependiendo solo de faceOpacity (ningún binding de layerOpacity los toca). El
plate funda con la pila: `plateOpacity × layerOpacity`. Gate: cláusula (g)
del oráculo con los materiales leídos en vivo del motor (patrón
check-cap/check-cylinder) + rechazos sintéticos nuevos (quad Blend en reposo,
opacity ≠ 1 en reposo, cutoff movido, plate sin Blend, Mask al girar con 0.7,
plate ignorando el fundido, cara tocada con flag off); en la UI la clave vive
en Ventanas junto a gap y plate (4ª conexión `toggled→setEnabled`).


## ADR-029 — El modelo interior lo trae el usuario: glTF local, cargado en runtime.

**Decisión**: el interior (ADR-007, §4) arranca con **una sola feature de
configuración**: el usuario elige un fichero de su disco (`ModelFile`, Url) y el efecto
lo carga **sin compilar nada y sin conversión previa**, con `RuntimeLoader`
(`QtQuick3D.AssetUtils`). El modelo es responsabilidad del usuario: él lo busca, él lo
exporta, él ve cómo queda (`ModelScale`, Double, es un multiplicador del auto-ajuste).

**Porqué**: era la única vía que cumple las reglas del proyecto a la vez — «solo QML»,
«sin root», «el menú QML funciona sin compilar» (README/ADR-016). Pedir `.mesh` horneado
hubiera obligado al usuario a correr `balsam`; y `balsam` ata el asset a la versión de Qt
(la cabecera del `.mesh` lleva `fileVersion`, medido: 7 con Qt 6.12), así que un mesh
empaquetado rompería en un KWin con Qt previo. Cargar el `.glb` tal cual no acopla a nada.

**Formato aceptado y por qué exactamente ese** (medido en esta máquina, Qt 6.12.1,
`QT_QPA_PLATFORM=minimal`, ficheros de Khronos glTF-Sample-Assets procesados con
`gltf-transform` 4.5.1):

| fichero | resultado RuntimeLoader | ms |
| --- | --- | --- |
| `Duck.glb` (120 KB, glTF 2.0 puro) | Ready, 1 model | 14 |
| `DamagedHelmet.glb` (3.77 MB, puro) | Ready, 1 model | ~158 |
| + `KHR_materials_unlit` | Ready | 162 |
| + `KHR_draco_mesh_compression` | **Error**: «Draco mesh compression not supported» | 9 |
| + `EXT_meshopt_compression` | **Error**: buffer sin atributo «uri» | 9 |
| + `KHR_mesh_quantization` | **Error**: «No meshes remaining» | 15 |

Es decir: las compresiones que hacen «más pequeño» el glTF para la web son justo las que
Qt no lee — y `balsam` tampoco saca ninguna malla de ahí (0 `.mesh` generados, medido). De
ahí que el spec (§4.1) acepte glTF **sin comprimir** y `.obj`, y descarte FBX/DAE/STL:
el cargador de runtime solo conoce `.obj`/`.gltf`/`.glb` (doc de Qt).

**Consecuencias aceptadas**:

1. `RuntimeLoader` es menos eficiente que el formato interno (doc de Qt lo dice). A cambio,
   cero pasos para el usuario. El coste medido (158 ms el casco de 3.7 MB) es carga, no
   por-frame; el draw de una malla dentro del sólido es el de cualquier `Model`.
2. El cargador de runtime **no valida ni aísla** el contenido (advertencia explícita en la
   doc de Qt): se alimenta del disco del usuario, no de la red, y quien escribe
   `[Effect-kube-effect]` ya controla su sesión (mismo argumento de `localSource`, §2.2).
3. Sin `bounds` válidos el nodo no se pinta: el auto-ajuste necesita la caja del modelo y
   Qt avisa de que puede no estar disponible hasta el primer render.

**Degradación** (patrón ADR-022, el mismo de `CapMesh.qml`/`CylinderArcMesh.qml`): el
import de `QtQuick3D.AssetUtils` queda **aislado** en `InteriorModel.qml`, cargado con
`Loader`. Si el módulo falta, solo ese Loader falla y el cubo se pinta intacto. Si el
fichero es ilegible, se avisa **una vez** con el `errorString` de Qt — el usuario ve
escrito «Draco … not supported» en el log y entiende qué exportar distinto.

**Vida útil de la escena**: el `Loader` solo está activo con fuente válida y volumen
(3+ escritorios, regla de las tapas ADR-027: la hoja 2D no encierra nada). Cambiar de
fichero reasigna `source` (RuntimeLoader descarga el anterior y carga el nuevo); al
vaciar `ModelFile` el Loader se desactiva y libera el modelo.

**No se hace**: catálogo de modelos, descarga desde el efecto, caché `.mesh`, miniatura 3D
en `config.ui` (`QUiLoader` no pinta estado, ADR-016), posición/rotación por eje (un
modelo, en el centro), «objeto estático que no gira». Salen en cuanto haya demanda;
auto-ajuste + `ModelScale` cubren el 90 % del uso.
