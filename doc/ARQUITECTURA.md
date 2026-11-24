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
    - **Color**: `window.color` (plano, ver trucos) / `SceneEnvironment`.
    - **Degradado** lineal/radial/circular: un `Rectangle` con `Gradient` (lineal) o
      un gradiente generado (radial/circular) capturado a textura.
    - **Imagen / SkyBox**: si la imagen es **360 equirectangular (2:1)** se usa
      `SceneEnvironment { backgroundMode: SkyBox; lightProbe: Texture { source } }`
      → **SkyBox**: entorno que envuelve la escena y gira con el centro. Si no es
      2:1, se pinta como **quad plano** (fondo fijo). `CascoImageMapping`
      (Auto/Equirect/Flat) lo decide.
    - **Vídeo 360**: entorno envolvente con el clip (skydome animado), equivalente en
      movimiento al SkyBox. Requiere QtMultimedia.
- **SkyBox no es un modo aparte**: es la variante 360 de "Imagen"
  (`SceneEnvironment.SkyBox`, no un quad). "Vídeo 360" es su versión animada.
- `CascoImageRotate`: si la imagen plana gira con el centro o queda fija.
- Por cómo se pinta el fondo en KWin (ver `doc/trucos-aprendidos.md`): el modo
  plano (Color) se pinta con `window.color`; los texturizados, dentro de la escena.

## 5. Interior: objetos decorativos

- Nodo en el centro del sólido. Objetos 3D (primitivas `#Cube`/`#Cylinder`, modelos `.mesh`/`.glb`),
  2D (quads con imagen/HUD) o vídeo (`Video` sobre un quad).
- Animados por defecto; un objeto **estático** no debe heredar el giro del sólido
  (anclar al mundo, no al nodo que gira).
- Deshabilitado con 2 escritorios (hoja 2D) y en el placeholder (1).

## 6. Configuración

Las claves viven en `package/contents/config/main.xml` (KCM genérico). Enums se
guardan como ENTERO en kwinrc. Grupo `[Effect-kube-effect]`.

## 7. Verificación

- `make lint` (estático).
- KWin anidado (`scripts/kwin-nested-test.sh`): el usuario prueba a mano. KWin
  cachea el QML; hay que usar un proceso nuevo (anidado) o reiniciar KWin.
