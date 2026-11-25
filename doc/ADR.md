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
