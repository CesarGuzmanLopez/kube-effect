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

### 2.2 Cilindro (isométrico, sin shader) — cómo ES (ADR-025)

El cilindro es una superficie **desarrollable** (curvatura gaussiana K=0): un plano
se envuelve sobre él **sin distorsión**. Por eso el contenido del escritorio se
curva sobre un cilindro sin estirarlo → **sin vertex shader**, QML puro.

Geometría real (arco de cilindro, radio R, ancho de cara W, alto H; desde
ADR-026 el arco vive **alrededor de su nodo** — punto medio en el origen del
Model, eje local en (0, 0, −R) — y la posición del nodo aporta el radio):

```
g      = max(0, CubeFaceDisplacement)   → hueco LINEAL entre arcos (negativos = 0)
R      = N·(W + g) / (2π)               → cylinderRadius(N, W, g)   (constants.js)
θ      = W / R                          → cylinderArcAngle(W, R)    (arco = R·θ = W)
φ(s)   = (s − W/2) / R                  → arco simétrico, medio en el nodo
P(s,t) = ( R·sin φ, t − H/2, R·cos φ − R ) → t ∈ [0, H]; eje en (0, 0, −R)
normal = ( sin φ, 0, cos φ )            → radial saliente
UV:    u = s / W,  v = t/H              → misma convención que #Rectangle (v=0 abajo)
```

Cómo está implementado:

- **Función pura** `cylinderArcGeometry(faceWidth, faceHeight, radius, segments)`
  en `constants.js`: devuelve `{positions, normals, uvs, indexes}` como listas de
  `Qt.vector3d/vector2d/uint` (130 vértices, 384 índices con 64 segmentos). Sin
  KWin ni escena: es lo que validan los checks (ADR: decisión testeable).
- **Componente con módulo aislado** (`CylinderArcMesh.qml`): es el
  **único** fichero del efecto que importa `QtQuick3D.Helpers` (el patrón de
  `HullVideo.qml`/`HullRadial.qml`, ADR-022). `Cube.qml` lo alcanza solo con
  `isCylinder` y a través del `source` de un `Loader` — la URL se resuelve en
  tiempo de ejecución, y un delegate inline habría convertido el import en
  dependencia de compilación de todo el efecto. Como un `Loader` solo carga
  raíces `Item`, el fichero es un holder `Item` de tamaño cero que expone el
  `ProceduralMesh` en su propiedad `mesh`. Si el módulo faltara, solo falla
  ese `Loader`: `cylinderMesh` queda nulo, `cylinderActive` pasa a false y el
  sólido degrada al polígono plano (caras rectangulares, fórmulas de cámara
  poligonales). Cuando el módulo está, el objeto es el `ProceduralMesh` y se
  construye **una vez por cambio de (W, H, R)** — los bindings no corren por
  frame; girar y hacer zoom son transformaciones.
- **Una sola malla para las N caras** (`ADR-025` decisión): el `ProceduralMesh`
  vive en `CylinderArcMesh.qml` (holder `Item` de tamaño cero; `Cube.qml` lo
  lee por `item.mesh`) y cada `CubeFace` (un `Model`) lo referencia con su
  propiedad `geometry` (con `source` vacío). En QML/QtQuick3D un `Geometry` puede
  referenciarlo más de un `Model` — es exactamente el patrón de los primitivos
  compartidos (`"#Rectangle"`); `scripts/check-cylinder-wiring.py` lo prueba con
  dos Models sobre la misma geometría. Si el anidado mostrara un problema de
  referenciación múltiple, el plan B es una instancia por cara (la fórmula no
  cambia; solo dónde vive el objeto).
- **Colocación (ADR-026)**: la del polígono exacta —
  `position = rotar(azimut)·(0, 0, faceDistance=R)` más
  `eulerRotation.y = angleTick * index` (idéntico al polígono con 3+; el
  tambor de 1-2 usa la MISMA grid con tres slots — punto tambor abajo, la
  banda especial está retirada). El radio
  vive en la **posición del nodo**, no en los vértices de la malla: cada cara
  queda a distancia R del eje con centroide de sort dos a dos distinto, que
  es la clave con la que QtQuick3D ordena la pasada transparente (centro del
  bbox en mundo proyectado sobre el eje de visión; medido en
  qssglayerrenderdata.cpp) y la que el polígono siempre usó. La vieja malla
  centrada en +Z con todos los nodos en (0,0,0) empataba esa clave — causa
  del overlap que reportó el usuario (ADR-025 pt.12, resuelto en ADR-026).
  Winding **CCW hacia fuera**, verificado por `check-cylinder.py` (ahora
  alrededor del eje local (0, 0, −R)).
- **Material de cara (ADR-026)**: `PrincipledMaterial` con
  `lighting: NoLighting`, `baseColorMap: Texture { sourceItem: DesktopView }` y
  `alphaMode` por umbral de `faceOpacity`: `≥ 0.99 → Mask` (en reposo los
  fragmentes sobre el corte se pintan opacos y **escriben profundidad** —
  imposible que una cara lejana quede encima de una cercana—; los bajo el
  corte se descartan, así que el wallpaper sigue viéndose a través de los
  huecos de la textura; `Opaque` se descartó porque pintaba esos huecos de
  negro, medido), `< 0.99 → Blend` (giro: la semitransparencia de ADR-021,
  ordenada atrás-adelante por los centroides del punto anterior). Antes el
  `DefaultMaterial` con `diffuseMap ← Texture.sourceItem` entraba SIEMPRE en la
  pasada transparente (el grab del item tiene canal alfa: el motor marca
  transparencia por la textura, no por el `opacity` — por eso el overlap se veía
  con op=1.00). `NoCulling` se mantiene SIEMPRE — polígono, hoja y tambor (con
  1-2 escritorios, el tambor de 3 slots): por los huecos y cantos se ven los
  dorso de las caras lejanas
  (paridad con el cubo virgen, ADR-003/ADR-023). El helper `cylinderCullMode`
  sigue testeado como semilla de la alternativa descartada (tokens 1/0; los
  ints del enum NO se hardcodean: Qt 6.12.1 Back=1, Front=2, None=3). El
  overlay imprime `blend=0|1` (1 = op < 0.99, caras en pasada transparente
  ordenada por centroide; 0 = reposo, profundidad por píxel con Mask).
- **Cámara**: `viewRadius`/`faceDistance` valen `R` en cilindro; close/distant,
  min/maxRadius y `safeViewRadius` reutilizan la infraestructura de
  ADR-022/024 sin fórmula nueva.
- **Contenido**: el `DesktopView` compuesto (wallpaper + ventanas) se aplica como
  `baseColorMap` sobre la malla curva con el MISMO material que el plano —
  polígono, hoja y tambor (de 3 slots con 1-2) comparten `CubeFace.qml`
  (ADR-021 heredada; ADR-026 solo hizo explícita la pasada).
- Segmentos: **64 fijos** (`CYLINDER_SEGMENTS`) — ADR-002 admitía 32–64; 64 por
  arcos grandes/cerca (130 vértices por malla, no por cara).
- `#Cylinder` primitivo NO sirve para un arco parcial con UV isométrica; es un
  cilindro completo con UV propias.
- **Tambor de tres slots (1-2 escritorios, ADR-025 pt.11 re-rectificado +
  ADR-026)**: con `Shape = Cylinder` y 1-2 escritorios NO hay rama especial:
  `cylinderActive = isCylinder && mesh` a cualquier count y el tambor corre
  con su fórmula fijando el suelo de slots en 3 (`geometryCount =
  max(3, faces)`): `R = 3(W + g)/2π` — **el hueco g del usuario aplica**
  (el 3W/2π fijo del segmento murió con él) —, tick 120° por la grid
  estándar `angleTick·index`, caras en los slots 0..count-1 y slots vacíos
  **sin delegate** (se ve el casco: «como si hubiera 3 escritorios, con las
  que faltan vacías»). El rango de giro es **abierto** a todos los counts
  con malla (`azimuthRangeFor` → `[null, null]`): la banda con topes
  ([-60,60]/[-60,180], y antes ±80/±120) se retiró tras probarla en el
  anidado — «hacía saltos raros y se sentía poco fluida». Flechas/estados/
  `desktopAt`: la aritmética de grid del tambor verbatim; aparcar en slot
  vacío es válido y seleccionar ahí es el `null`-guard ya existente. Con 1
  escritorio el target del estado es azimut 0 verbatim → la cara queda
  **siempre de frente al activar** (guard del addendum, verificado por
  `check-cylinder-wiring.py` —`slotZeroAzimuth`/`slotOneAzimuth`— y por el
  escenario `single` de `check-cylinder-overlap.py`). Los helpers de la
  banda (`cylinderArcRadius`, `cylinderSegmentAzimuth`,
  `cylinderAzimuthRange`, `cylinderSegmentDesktopAt`,
  `CYLINDER_SEGMENT_DEG`) fueron RETIRADOS de `constants.js`. `faceDistance
  = viewRadius = R`; close llena la pantalla en vertical — en horizontal
  la cuerda del arco mide ≈ 0.826·W con g = 0 (los bordes curvos dejan
  ~8-9 % de casco a cada lado; es la proyección, no un bug). Con `Polygon`,
  1-2 sigue siendo §2.3 sin tocar.

### 2.3 Hoja 2D plana (1-2 escritorios, Shape = Polygon)

Implementada dentro de `Cube.qml` (ADR-024): `isSheet = count < 3 &&
!cylinderActive` — la hoja PLANA es la representación cuando `Shape` es
`Polygon` (o cuando `Cylinder` no pudo conseguir malla: la caída degrada
aquí, ADR-025), y el delegate coloca los quads en el centro en vez de sobre
el perímetro. Con `Shape = Cylinder` y 1-2 escritorios la representación
es el **tambor de tres slots** (§2.2) — la hoja queda solo para `Polygon`
y para el fallback sin `QtQuick3D.Helpers`.

- **2 escritorios**: un quad por escritorio (`CubeFace`, `#Rectangle` con
  `Material.NoCulling`) en `position.z = ±sheetGap` (**separación proporcional
  (≥2 unidades)**: `sheetGap = max(1, viewRadius · 0.005)`; 1 px fijo serían
  1-2 pasos del depth buffer a radios 4K) con `eulerRotation.y = 0° / 180°` —
  cada cara mira a un lado. `angleTick = 180`: las flechas y `desktopAt()`
  saltan de cara a cara y el giro es completo (ambos lados son reales).
- **1 escritorio**: solo el frente (z = +`sheetGap`, `eulerRotation.y = 0`,
  `angleTick = 360`). Como `NoCulling` muestra el dorso **espejado**, el azimut
  se clampa a ±80° (`SHEET_AZIMUTH_LIMIT_DEG` en `constants.js`, fijo, sin
  clave; expresado como rango `flatAzimuthRange` = [-80, 80]). El **arrastre**
  con rango real clampa la suma cruda
  (`euler.y + delta`, sin `%360` ni normalizar: un tirón que cruzara ±180 no
  debe teletransportar de +80 a −80); las **flechas y los estados** usan
  `clampAzimuthRange` (heredero del retirado `clampSheetAzimuth`), que
  normaliza a (-180,180] solo con rango real y devuelve el ángulo tal cual si
  no (paridad literal con el código pre-hoja).
- **Radios**: `viewRadius = 0.5·anchoCara` (en hoja; leer `faceDistance` sería
  ciclo: el gap deriva del radius), `faceDistance = sheetGap` (close llena la
  pantalla igual que el cubo: `sheetGap + 0.5·h/tan(fov/2)`), y distant/zoom se
  miden contra `safeViewRadius = max(1, viewRadius)` — con ≥3 escritorios
  `viewRadius === faceDistance`, pero el apotema del polígono puede ser
  **negativa** (displacement −500) y sin el pincho la rueda metía la cámara
  dentro del sólido.
- **Cambio de nº de escritorios con el efecto abierto**: los bindings de los
  estados mueren al primer arrastre/flecha/rueda, así que un `Connections`
  sobre `cube.faceCount` llama `cameraController.resyncToState()` (re-clampa el
  azimut a la forma nueva, re-alinea al escritorio actual y fuerza el radius
  del estado vigente). El mismo bloque escucha también `cube.cylinderActive`
  (antes, mientras vivió la banda, también `cube.cylinderSegments`; el tambor
  de tres slots unificó la rama, ADR-026).
- `CubeFaceDisplacement` **no aplica a la hoja** (su `faceDistance` es el gap);
  en Cylinder aplica a TODOS los counts (tambor y tambor de tres slots,
  ADR-026).
- Con `Polygon` y <3 escritorios la forma es la hoja plana (esta sección,
  ADR-024 intacto); con `Cylinder` existe el tambor de tres slots (§2.2) y
  la hoja solo vuelve si falta `QtQuick3D.Helpers`. `PlaceholderView.qml`
  quedó retirado.
- El re-sincronizado del punto anterior escucha también `cube.cylinderActive`
  y — con tambor activo — `cube.cylinderRadius`/`cube.faceSize`: cambiar
  `Shape` o la separación con el efecto abierto re-clampa (±80 ↔ sin límite),
  re-alinea (slot 0) y fuerza el radius nuevo (R del tambor), mismo
  mecanismo ADR-024.

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

## 2.5 Tapas (superior e inferior) — cómo se aplicó (ADR-027)

- **Dónde vive la malla**: `CapMesh.qml` (holder `Item` de tamaño cero con un
  `ProceduralMesh`), en la misma rama del árbol que `CylinderArcMesh.qml`.
  `Cube.qml` la alcanza SOLO con `Loader` por URL de source
  (`capMeshLoader`, activo únicamente con alguna tapa encendida y sólido con
  volumen): así el `import QtQuick3D.Helpers` queda aislado en ese fichero y
  se compila en runtime (patrón ADR-022/HullRadial/HullVideo). Si el módulo
  falta, solo ese Loader queda en `Error`: `capMesh` es nulo, las dos tapas
  no se pintan y el cubo queda intacto, con un único log del motor.
- **UNA sola malla para las dos tapas**: la geometría es un plano en y = 0
  generado por los helpers puros de `capGeometry.js`
  (`capPolygonGeometry`/`capDiscGeometry` — módulo propio desde la enmienda de
  ADR-027; `constants.js` guarda solo los resolvedores de valor). El desplazamiento ±alto/2 lo
  lleva el NODO del Model (`Cap` superior en `y = +faceSize.height/2`,
  inferior en `y = -faceSize.height/2` con `eulerRotation.x: 180` — la
  rotación invierte la normal +Y a -Y y el winding queda consistente visto
  desde fuera; no existe segunda malla ni copia espejada). **El eje del flip
  es Z** (ADR-027 enmienda 2, medido con píxeles por
  `scripts/check-cap-overlap.py`): solo la rotación 180° sobre Z vuelca la
  normal (+Y → −Y) MANTIENIENDO el anillo (manda azimut α → −α, la simetría
  real del anillo de esquinas); sobre X mandaría α → 180°−α y giraría el
  anillo medio tick — los vértices asomaban 928 sobre planos de cara a 472
  (la tapa "cruzaba el sólido") y la frontera del hueco caía de 928 a 472
  (no cerraba). Consecuencia visible: el grab de la tapa inferior queda
  espejado en u (el cuadrante del marcador cambia de lado x; la flecha,
  simétrica, no). Los centroides de ordenación son distintos en Y por tapa →
  la regla ADR-026 se extiende a ellas, con el `alphaMode` por umbral de
  opacidad que se describe justo abajo.
- **Sin fuente paralela de geometría** (enmienda ADR-027): el polígono se
  genera con apotema = `cube.faceDistance` y ancho = `cube.faceSize.width`
  (enlazado por el Loader como `item.faceWidth`, sin leer `viewRadius`): con
  separación nula o negativa la tapa es el N-gono INSCRITO de siempre (N
  vértices, circunradio derivado `apotema/cos(π/N)`); con separación positiva
  el anillo va a las ESQUINAS de cara (2N vértices a `hypot(apotema, W/2)`) y
  los huecos se cierran con cuerdas rectas por dentro de los planos — ningún
  vértice asoma fuera del prisma ni cruza la esquina de su cara. El disco
  sigue con radio = `cube.cylinderRadius` (tapa también las cuñas vacías del
  tambor de 3 slots; allí R ya es la fuente única y no hay esquinas). Con la hoja 2D (`isSheet`) las tapas se desactivan POR CÓDIGO:
  el Loader ni se monta. Ninguna propiedad nueva lee `viewRadius` ni la
  cadena de la hoja, así que no reabre el ciclo ADR-026b.
- **Contenido sin shaders**: `Cap.qml` es un `Model` con
  `PrincipledMaterial` (`NoLighting`, `NoCulling` y —desde ADR-027
  enmienda 2— `alphaMode` por umbral como `CubeFace.qml`: **Mask con
  `alphaCutoff: 0.5` explícito cuando `opacityValue ≥ 0.99`** —los
  fragmentos conservados escriben profundidad y un empate de centroides ya
  no puede pintar una tapa lejana sobre una cara cercana— y **Blend por
  debajo** —el default `CapOpacity` 80 sigue siendo translúcido de verdad—;
  nunca Opaque: pintaría de negro los agujeros de alfa, medido en ADR-026) y
  `baseColorMap: Texture { sourceItem }` sobre un `Item` de 512×512 que pinta
  Color (`Rectangle`), Degradado —reutilizando `HullGradient.qml`, cuyo
  radial mantiene su propio Loader opcional de `QtQuick.Shapes`—, Imagen
  local con `CapImageFit`, o **Arrow (el default nuevo)**:
  `CapArrow.qml` —fondo `CapColor`, flecha cian hacia el borde superior del
  ítem y cuadrante magenta en la esquina superior-izquierda— cargado tras su
  propio `Loader`: sin `QtQuick.Shapes` la tapa degrada a `CapColor` plano
  y avisa UNA vez (señal `surfaceDegraded`, patrón HullRadial ADR-022). El
  marcador existe porque un color uniforme no distingue "tapa girada" de
  "tapa pintada encima" (la confusión del reporte del usuario) y porque hace
  MEDIBLE el espejo de la tapa inferior con píxeles. Con `DebugOverlay` las
  tapas se fuerzan a Arrow cualquiera que sea el valor guardado (ADR-023: el
  overlay es el botón de diagnóstico). Imagen rota o ausente → `CapColor` y
  `console.warn` UNA vez (señal `imageUnavailable` filtrada en `Cube` con
  `capImageWarned`; el aviso de "fuente vacía" va diferido con
  `Qt.callLater` porque content e imageSource se re-enlazan en el mismo
  pase).
- **Config**: claves `CapTop/CapBottom/CapContent/CapColor/CapColor2/
  CapGradientType/CapGradientStop/CapImage/CapImageFit/CapOpacity` en
  `main.xml` (Enums como entero, KConfigXT; `CapContent` = Color 0 /
  Gradient 1 / Image 2 / **Arrow 3 — el default**, añadido al final para no
  mover los índices guardados; los valores desconocidos siguen cayendo a
  Color en `constants.js`); `config.ui` las agrupa en
  «Tapas (Caps)» (Appearance) con el patrón de páginas apiladas del fondo
  (`kcfg_CapContent` → `capContentStack` por `<connections>`); el grupo no se
  puede encender por "OR" de dos checkboxes en Qt Designer (la última señal
  gana), así que la ayuda escrita sustituye al gating y el efecto oculta las
  tapas si ninguna está activa.
- **Gate**: `scripts/check-cap.py` (+ `--selftest`) instancia el
  `CapMesh.qml` real offscreen y mide, por cara y en su marco local: invariante
  de prisma (ningún vértice del anillo proyecta más allá de `faceDistance`
  sobre la normal de NINGUNA cara), cota de esquina (`|tangencial| ≤ W/2`),
  régimen d ≤ 0 colapsado a N-gono (N vértices, apotema por punto medio de
  lado == `faceDistance`, azimut en rejilla) y régimen d > 0 con lados de cara
  exactos ±W/2 y cuerdas de hueco por dentro del plano; anillo del disco ==
  `R`, plano y = 0, normales +Y unitarias, UVs centradas en [0,1], fan CCW
  uniforme, índices en rango, mallas vacías con entradas degeneradas
  (`faceWidth = 0` incluida) y los dos `Cap` compartiendo la MISMA
  geometría. El `--selftest` (17 detecciones, 4 sondas de aislamiento) incluye
  la regresión del bug: esquina deslizada más allá de W/2 y vértice fuera del
  plano, con plano/normales/UVs coherentes.

## 3. Caras: fondo de cara (wallpaper real)

- El fondo de cada cara es el wallpaper REAL del escritorio (el mismo que el
  usuario tiene), capturado en QML: se captura la ventana de escritorio de Plasma
  (`WindowThumbnail` sobre la `desktopWindow` de esa pantalla) → textura.
- Sin shaders: es una textura estándar sobre el quad/cilindro.
- Encima van las ventanas de ese escritorio (composite o capas 3D).
- Multi-monitor: una captura por pantalla (`WindowFilterModel { screenName }`).
- **Todas las caras se pintan siempre** (ADR-023): el LOD de orientación de
  ADR-022 quedó retirado — con `Material.NoCulling` y caras separadas los
  interiores de las traseras se ven por los huecos (look del cubo virgen), y
  ocultarlas abría agujeros al casco en reposo. El `Texture.sourceItem` de
  cada cara captura por frame sin excepciones; el ahorro llegará con el LOD
  **por distancia** de WindowLayering (fase posterior).
- **Sin scope dinámico** (ADR-022): `DesktopView` no resuelve `targetScreen`
  subiendo el grafo de objetos; `ScreenView` → `Cube` → `CubeFace` →
  `DesktopView` pasan `screenName` y `screenGeometry` explícitos, y un modelo
  nulo deja `wId = 0` (nullWId) para liberar la captura.

### Modo debug (`DebugOverlay`)

- Clave Bool de Advanced, default `false` (ADR-023). Con `true`, un `Text`
  rojo monoespaciado anclado arriba-izquierda en cada `ScreenView` (z: 100)
  muestra dos líneas con el estado vivo: fondo (modo, equirect, skybox),
  vídeo (wanted/ready/painted + `mediaStatus`), atenuación (`cubeMoving`,
  exposición), pantalla (`sceneScreenName`, `cursorScreenName`,
  `drawOnThisScreen`), cámara (yaw, pitch, radio), opacidad de caras, tick
  angular, geometría (`faceRepeater.count` vs `geometryCount`,
  `faceDistance`) y el `cos` por cara (informativo: sin LOD ninguna cara se
  oculta).
- Por qué en pantalla y no por consola/D-Bus: `console.log/warn` no llega al
  journal de este KWin y `org.kde.kwin.Effects.supportInformation` devuelve
  cadena vacía en KWin 6.8.3 (medido 2026-11-25; trucos §D). Pintar es el
  único canal que se comprobó visible — así se diagnosticó el bug del LOD.
- Coste controlado: el ensamblado del string y la descomposición
  `toEulerAngles()` del yaw/pitch solo corren con el overlay activo (mismo
  gateo que el yaw del degradado, ADR-022).

## 4. Casco: espacio alrededor

- Es el fondo de la escena (no la superficie del sólido). Modos:
    - **Color**: un `Rectangle` de color sólido DENTRO de la escena, detrás del
      `View3D` (nunca `window.color`, que pinta la superficie de la ventana; ver
      trucos).
    - **Degradado** lineal (arriba→abajo u horizontal): un `Rectangle` con
      `Gradient` DENTRO de la escena. `Radial` es **real** con
      `QtQuick.Shapes.RadialGradient` (expone `centerX/centerY/centerRadius/focal*`
      y `stops` en Qt 6.12); no cae a vertical. Sin shaders ni C++. **Opcional**
      (ADR-022): vive en `HullRadial.qml` cargado con `Loader`; si falta el
      módulo, cae al lineal y avisa una vez (antes el import hacía de
      `QtQuick.Shapes` dependencia dura de todo el efecto).
    - **Imagen / SkyBox**: si el mapeo es `Equirect` (panorámica 360) se usa
      `SceneEnvironment { backgroundMode: SkyBox; lightProbe: Texture { source } }`
      → **SkyBox**: entorno que envuelve la escena y gira con el centro. Un solo
      `SceneEnvironment` inline del `View3D` (sin `Loaders`, ADR-022): alterna
      `SkyBox`/`Transparent` con `backgroundMode` sin recrear el entorno en cada
      cambio de modo. El `source` del `lightProbe` se gatea por `skyBoxImageReady`
      (la sonda solo decodifica con el efecto visible). Limite honesto: KWin
      destruye el SceneView en cada desactivación (`QuickSceneEffect::stopInternal`,
      view caching off y no expuesto a QML), así que el panorama **re-decodifica
      por activación** desde QML; evitarlo exige caching de views en C++, fuera
      del contrato. En multi-monitor el `source` del probe solo se crea en la pantalla donde
      se pinta (`drawOnThisScreen`). Si es
      `Flat`, se pinta como **quad plano** (fondo fijo), con `BackgroundImageFit`
      (`Cover`/`Contain`/`Stretch`, default `Cover`) para decidir cómo encaja
      la imagen plana. Ya no hay `Auto`: el usuario elige explícitamente
      (`BackgroundImageLayout`: `Equirect`/`Flat`).
    - **Vídeo** (`Background=Video`): el clip se pinta **igual que una imagen**,
      con dos caminos. `Equirect` + `BackgroundImageRotate` = 360: una esfera
      vista desde dentro con `baseColorMap: Texture { sourceItem: videoOutput }`
      (ADR-020; Qt rechaza el `sourceItem` como `lightProbe`). Ahí el
      `VideoOutput` fuerza `fillMode: Stretch` (`HullVideo.dome`): la esfera
      envuelve el fotograma completo; el fit del usuario recortaba cielo y
      suelo (Cover) o metía barras negras en los polos (Contain). Si no, capa
      plana fullscreen detrás del `View3D` con `BackgroundImageFit` en el
      `VideoOutput.fillMode` (`Cover`/`Contain`/`Stretch`).
      **El import de QtMultimedia está aislado** en `package/contents/ui/HullVideo.qml`,
      que `ScreenView.qml` carga con un `Loader`: si el módulo opcional no está,
      solo ese item queda en `Loader.Error` (aviso `qWarning` una vez) y el
      color de respaldo sigue pintando el casco. Un import de QtMultimedia en
      `ScreenView.qml` habría roto **todo** el efecto.
      El `MediaPlayer` (bucle infinito, `AudioOutput { muted: true }` —en Qt 6.12
      `MediaPlayer` no tiene `muted`) solo reproduce con `effect.visible`:
      `playing` está ligado a esa propiedad, y el item no se crea hasta la
      primera activación, así que no consume CPU en segundo plano. En
      multi-monitor el `Loader` del vídeo se crea solo en la pantalla que pinta
      (`active: videoActive && drawOnThisScreen`, ADR-022 segunda revisión):
      KWin genera un SceneView por salida y un Loader activo decodificaría en
      cada una. Cambiar de clip o de modo con el `Loader` ya montado rearma el
      temporizador de diagnóstico (si no, un clip nuevo roto quedaría mudo).
      Atenuación al girar: capa plana → velo 2D `hullDim`; 360 → esfera-velo
      negra dentro de la cúpula (ADR-020; `probeExposure` es solo para la imagen).
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
- Deshabilitado con 1-2 escritorios (no hay volumen: en la hoja de 1 y de 2,
  ADR-024).

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
       recompila QML. **Asíncrono** (ADR-022): `QDBusConnection::asyncCall()` +
       `QDBusPendingCallWatcher`; antes el `call` síncrono congelaba el hilo GUI
       hasta 25 s si KWin no respondía (el aviso «en curso…» se muestra antes de
       lanzar la llamada y la etiqueta recoge el resultado al terminar).
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
  con un aviso de que hay que ajustarla. La ruta del stamp se **entrecomilla**
  para la shell (`shellQuote()` en `kube_effect_install.*`, ADR-022: `cd %1` a
  pelo permitía inyectar comandos con una ruta con `'` del stamp) y solo se
  acepta si es absoluta; el `commandsBlock()` es función pura testeada con
  ctest.
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
