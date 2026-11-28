# Requerimientos — Kube Effect

Qué debe hacer el efecto y cómo se configura. Empieza por el vocabulario exacto;
luego cada requerimiento con su clave de configuración, tipo y rango. **No se
limita a un mínimo**: se define el alcance completo (la implementación puede ir
por fases, pero el spec es entero).

## 0. Vocabulario (definiciones exactas)

- **Escritorio virtual**: uno de los N espacios de trabajo de KDE. El sólido
  coloca uno por **cara**.
- **Cara (face)**: un lado del sólido; muestra UN escritorio: su **fondo de cara**
  - sus ventanas.
- **Sólido / forma**: el cuerpo que sostiene las caras. Dos formas:
  **polígono** (N caras planas en un N-gono) y **cilindro** (las mismas caras
  curvadas sobre un cilindro). Sin una tercera forma.
- **Fondo de cara**: el wallpaper REAL del escritorio de esa cara (el mismo que
  el usuario tiene puesto),**sin shaders**. Va detrás de las
  ventanas de la cara.
- **Superficie / piel**: NO existe. El sólido es solo caras; entre ellas se ve el
  casco. No hay paredes que "cierren" la forma. en el futuro las paredes tendran colisiones para poder poner efectos dentro pero por lo mientras esto estara asi
- **Tapa (cap)**: superficie de cierre **superior o inferior** del sólido — un
  plano (polígono o disco) que tapa un extremo del eje Y, una arriba y otra
  abajo, habilitables por separado. **Sí** es superficie de cierre (matiza
  ADR-003: la tapa cierra, la «piel» lateral sigue sin existir); es una pared
  transversal del sólido, no una cara lateral.
- **Casco**: el **espacio que rodea al sólido** cuando está activo (fondo /
  entorno). Se ve alrededor y a través de los huecos entre caras. Es configurable
  (color, degradado, vídeo, imagen…). NO es la superficie del sólido.
- **SkyBox**: una **forma concreta** de casco: una imagen **360 equirectangular
  (2:1)** que envuelve la escena y gira con el centro. Es un caso de "casco =
  imagen 360", **no un sinónimo** de casco. Un vídeo 360 es su equivalente en
  vídeo (skydome animado).
- **Interior**: el volumen dentro del sólido, donde viven los objetos decorativos.
- **Objeto interior**: elemento animado o estático dentro del sólido (3D, 2D,
  vídeo). El "centerpiece".
- **Opacidad** aquí se refiere al fondo de cara y a las ventanas; el casco es
  espacio (no se "opaca", se ve detrás del sólido).

## 1. Formas y reglas por número de escritorios

| Escritorios | Forma                                                                                                                                                                                                                                                                                                                                                                  | Interior                                              |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 1           | Con `Polygon` (default): **hoja simple**, un solo quad; giro limitado a ±80° (el dorso se vería espejado, no debe verse). Con `Cylinder`: **tambor de 3 slots con 2 vacíos** — un arco de W en el slot 0 (azimut 0), los slots 1/2 sin cara: por ahí se ve el casco; giro **libre**, sin topes (§1.2)                                                                  | **No permitido** (no hay volumen)                     |
| 2           | Con `Polygon`: **hoja 2D doble cara**, un quad por escritorio, separación proporcional en z (`sheetGap`, ≥2 unidades); giro completo (cada lado es un escritorio real). Con `Cylinder`: **tambor de 3 slots con 1 vacío** — arcos en los slots 0 y 1 (azimuts 0° y 120°), el slot 2 sin cara (se ve el casco), giro **libre** sin topes, tick de selección 120° (§1.2) | **No permitido** (no hay volumen donde poner objetos) |
| 3+          | **Polígono** (default) o **Cilindro** — tambor cerrado de N arcos (elegible)                                                                                                                                                                                                                                                                                           | Sí                                                    |

**Regla permanente** (re-rectificada, ADR-026): con `Polygon` y 1-2
escritorios la forma es la hoja plana de siempre (ADR-024 intacto; allí
`CubeFaceDisplacement` solo fija el `sheetGap` proporcional). Con
`Cylinder` y 1-2 escritorios la forma curva **sí existe**: tambor de TRES
slots con las caras vacías enseñando el casco — R = 3(W+g)/2π con el hueco
g del usuario, giro libre sin topes (la banda [-60,60]/[-60,180] que se
probó primero hizo saltos y se retiró, ADR-025 pt.11). El polígono plano
empieza en 3. No hay placeholder: KWin siempre tiene al menos 1 escritorio
y la hoja simple ya es útil (ADR-024).

### 1.1 Polígono (default)

- N caras planas (una por escritorio) en el perímetro de un N-gono regular.
- No deforma nada: las caras son planas; se ven las aristas entre caras.
- N = número de escritorios (3 = triángulo, 4 = cubo, 5 = pentágono…).

### 1.2 Cilindro (implementado, ADR-025)

- Las MISMAS caras, pero curvadas sobre un cilindro. Mapeo **isométrico**: el
  cilindro es una superficie **desarrollable** (curvatura gaussiana K=0), así que
  un plano se envuelve sobre él **sin distorsión** (una recta se vuelve arco de
  igual longitud; el contenido no se estira).
- Con 3+ es el tambor cerrado de N arcos. Con 1-2 y esta opción el sólido es
  un **tambor de tres slots** (abajo), no la hoja; con `Shape = Polygon`
  1-2 es la hoja plana (ADR-024 intacto).
- Fórmulas reales (todas en `constants.js`, con `W` = ancho de cara, `H` = alto,
  `N` = nº de escritorios):
  - `g = max(0, CubeFaceDisplacement)` — en cilindro la separación es **hueco
    lineal entre arcos** y los valores negativos se tratan como 0 (la isometría
    no permite solapar: el arco tiene que medir W).
  - `R = N·(W + g) / (2π)` (`cylinderRadius()`) — el radio crece con el hueco.
  - `θ = W / R` por cara (`cylinderArcAngle()`); el arco mide `R·θ = W`
    **siempre** (isometría: la textura ni se estira ni se comprime). El hueco
    angular entre arcos es `2π/N − θ`, que sobre la superficie mide exactamente
    `g` px.
  - Malla del arco (ADR-026): `P(s,t) = (R·sin φ, t − H/2, R·cos φ − R)` con
    `φ = (s − W/2)/R`, `s ∈ [0,W]`, `t ∈ [0,H]` — generada **alrededor del
    nodo** (punto medio en el origen del Model, eje local en (0,0,−R)); la
    colocación por cara es la regla del polígono exacta:
    `position = rotar(azimut)·(0,0,R)` + `eulerRotation.y = azimut`, así cada
    cara lleva su centroide de sort a distancia R (la clave con la que
    QtQuick3D ordena la pasada transparente; antes el radio vivía en los
    vértices y todos los nodos compartían (0,0,0) → empates → el overlap que
    reportó el usuario). Los azimuts y `desktopAt()` no cambian de forma en
    ningún count (slot i en `120·i` por la grid `angleTick·index`).
  - UVs: `u = s/W`, `v = t/H` (convención medida del `#Rectangle` nativo: la
    base de la cara lleva `v = 0`), con lo que el compuesto de la cara se ve
    igual de derecho que en el polígono.
  - `ProceduralMesh` (`QtQuick3D.Helpers`) con **64 segmentos fijos**, una sola
    malla compartida por las N caras, reconstruida SOLO al cambiar (W, H, R).
    **Sin vertex shader.**
- Con `g = 0` los arcos se tocan: cilindro cerrado pero **sin piel** (ADR-003:
  la superficie entre caras no existe). Con `g > 0` entre arcos se ve el casco,
  igual que por los huecos del polígono. Nota: el texto anterior de esta
  sección usaba la notación `arco = R·θ`; se conserva la relación, pero `θ`
  ahora es consecuencia de R (arriba), no un ajuste libre.
- Cámara: `R` sustituye al apotema del polígono — `faceDistance = viewRadius =
R`, y close/distant/límites de zoom usan la infraestructura existente
  (ADR-022/024) sin fórmulas nuevas.
- **Tambor de tres slots (1-2 escritorios, ADR-025 pt.11 re-rectificado por
  el usuario, ADR-026)**: la banda con topes (primero ±80/±120, después
  [-60,60]/[-60,180]) se probó en el anidado y **se retiró**: los clamps
  "hacían saltos raros y se sentían poco fluidos". Con `Shape = Cylinder` y
  1-2 escritorios el sólido es el propio tambor corriendo con **N = 3**:
  - Geometría fija de 3 slots: `R = 3·(W + g) / (2π)` — `cylinderRadius(3, W,
g)`, **el hueco lineal g del usuario aplica** (antes, con el segmento,
    R era el fijo 3W/2π y g no pintaba). Con g = 0 el arco del slot mide
    exactamente un tercio de círculo (θ = 120°).
  - Las caras ocupan los slots 0..count-1 (azimuts 0° y 120° por la grid
    `angleTick·index`, `angleTick = 360/max(3, count)`); los slots sin
    escritorio **no se crean**: no hay panel, por ahí se ve el casco — se
    ve "como si hubiera 3 escritorios" con huecos, la petición literal del
    usuario.
  - Giro **sin topes** (rango abierto igual que el tambor,
    `azimuthRangeFor` → `[null, null]`): rotación completa, sin clamps ni
    wraps asimétricos; el dorso espejado de los arcos lejanos se tolera por
    los huecos y cantos igual que en el tambor de 3+ (ADR-023). Estados:
    la aritmética estándar verbatim (con 1 cara en reposo el target es
    azimut 0 → **la cara queda siempre de frente al activar**). **Las
    flechas solo visitan caras reales** (ADR-026b): si la grid tiene huecos
    (el tambor de 1-2: slot 2 vacío), cada flecha avanza a la siguiente
    CARA real en la dirección pedida con wrap completo — con 2 escritorios
    0↔120 por ambos lados y **nunca 240**; con 1 no-op; con la grid llena
    (tambor 3+, polígono, hoja doble) la cuenta ±tick verbatim de siempre
    (paridad ADR-022/024). El drag sí puede dejar la cámara frente a un
    slot vacío (el casco es vista válida); desde ahí las flechas salen al
    parar en la cara real más cercana en la dirección pedida.
  - Selección: `desktopAt` estándar sobre la grid — slot vacío → delegate
    ausente → `null` → Enter/click no-op (guardas ya existentes, sin helper
    dedicado; `cylinderSegmentDesktopAt`, `cylinderSegmentAzimuth`,
    `cylinderArcRadius` y `cylinderAzimuthRange` murieron con la banda).
  - Cámara: `faceDistance = viewRadius = R` (la del tambor con N = 3) para
    **cualquier** count — 3, 2 o 1 — **con la malla activa
    (`QtQuick3D.Helpers`)**; en el fallback sin módulo — igual que en el
    transitorio de mount — la rama hoja/poligonal es la representación
    legítima y close/distant miden contra ella (ADR-026b: con 1-2 y
    tambor en efecto el `viewRadius` no puede tomar la rama de la hoja;
    **close/distant nunca quedan dentro del
    tambor** y los topes de rueda valen `[0.6·R, 8·R]`, con R≈776 nada de
    radios 32/28 dentro del sólido). Honestidad del close: llena la pantalla
    en **vertical** (la generatriz no se deforma); en horizontal la cuerda
    del arco ≈ 0.826·W con g = 0 → close deja ~8-9 % de casco a cada lado
    (bordes curvos proyectados, no un bug).
- **Culling: NoCulling siempre, también en cilindro** (rectificación del
  usuario sobre ADR-025 pt.12): la pared interior espejada de las caras
  traseras **debe verse** por los huecos y cantos — paridad con el polígono
  (ADR-023); lo que no debe es pintarse ENCIMA de las frontales (overlap,
  sobre todo al girar). Un `BackFaceCulling` dinámico (fuera de 1.05·R) se
  probó y **se retiró del runtime**: suprimía las dos cosas. El helper puro
  `cylinderCullMode(cam, r)` (tokens 1/0) queda en `constants.js` testeado
  como semilla documentada del fix real, que es de orden de pintado: el
  overlay imprime `blend=0|1` (`1` = las caras están en la pasada
  transparente por `FaceOpacity/FaceRotationOpacity < 0.99`) para que la
  captura del momento «encima» distinga el orden por centroide (blend=1) de
  un bug de profundidad (blend=0).
  **Resuelto (ADR-026)**: el interior se ve por huecos y canto correcto — la
  pared lejana **nunca** se pinta encima de una frontal; cada cara lleva su
  centroide de sort a distancia R (colocación como el polígono) y el material
  elige la pasada por umbral (`Mask` en reposo escribe profundidad, `Blend`
  al girar ordena de atrás adelante), con los huecos de la textura siguiendo
  translúcidos.
- Con `Shape = Polygon` los casos 1-2 siguen siendo la hoja plana exacta de
  §1.3 (ADR-024 intacto).

### 1.3 Hoja 2D plana (1-2 escritorios, Shape = Polygon)

La hoja vive dentro de `Cube` (ADR-024): con menos de 3 escritorios el sólido no
es un polígono, son quads pegados en el centro. `ScreenView`, el casco, las
capturas, la dim, el debug y la cámara son los mismos que con cubo. Con
`Shape = Cylinder` estos dos casos son un **tambor de tres slots** (§1.2,
ADR-025 pt.11 re-rectificado + ADR-026), no la hoja; lo de abajo es la
representación plana, default e intacta — y el destino del fallback
`Cylinder` sin `QtQuick3D.Helpers`.

**2 escritorios — hoja doble cara:**

- Un quad por escritorio, ambos en el centro del espacio, girados 0° y 180°
  (cada uno mira a un lado). **Separación proporcional (≥2 unidades)**
  (`sheetGap` = 0.5 % del `viewRadius`, suelo 1, las dos caras quedan a ±gap):
  un hueco fijo de 1 px se come con la cuantización del depth buffer (24-bit,
  `clipNear` 10) y puede Z-fightear en 4K lejos; proporcional, no.
- `Material.NoCulling` (como las caras del cubo): cada lado se ve desde fuera.
- Giro **completo**: cualquier azimut muestra un escritorio real; al pasar de
  ±90° se ve el otro. El tick es de 180° (las flechas saltan de cara a cara).

**1 escritorio — hoja simple:**

- Un solo quad (frente, z = +`sheetGap`, el lado que mira la cámara en reposo;
  ver ADR-024).
- Con `NoCulling` el dorso muestra el contenido **espejado**, así que el giro se
  **limita a ±80° de azimut** (160° de recorrido): el revés nunca queda frente a
  la cámara. El límite es fijo en `constants.js` (`SHEET_AZIMUTH_LIMIT_DEG`);
  no hay clave de configuración (futuro si el usuario la pide).
- Las flechas eligen la siguiente **cara real** (una sola cara →
  la misma: delta 0, sin salto; helper puro `arrowAzimuth` con el rango
  `flatAzimuthRange(1)` = [-80, 80]); la activación y los estados siguen a
  `desktopAzimuth` (la cara del escritorio actual, no tick crudo).
- El arrastre que cruza ±180 **no teletransporta**: el drag clampa la suma
  directa (sin `%360` ni normalizar); solo las flechas y los estados
  normalizan (`arrowAzimuth` / `clampAzimuthRange`).

Común:

- Sin interior (no hay volumen). El casco se sigue viendo alrededor.
- Esta sección es la representación con `Shape = Polygon`; con `Cylinder`
  1-2 escritorios el sólido es el tambor de tres slots (§1.2) — geometría
  fija N = 3, slot 0 en 0°, giro **libre** sin topes y tick 120°.
- **`CubeFaceDisplacement`**: en la hoja su `faceDistance` es el
  `sheetGap` de las caras, no el radio de un polígono — el hueco g del KCM
  no se lee aquí (la hoja vive del §1.3). En el cilindro, en cambio, g
  **sí aplica a todos los counts** (tambor 3+ y tambor de tres slots 1-2:
  R = 3(W+g)/2π; ADR-026), con los negativos clampeados a 0 (ver §4).
- Cambiar el nº de escritorios **con el efecto abierto** re-sincroniza la
  cámara (`Connections` sobre `cube.faceCount`, y también sobre
  `cylinderActive` cuando cambia la forma sin cambiar el
  número): re-clampa el azimut al límite de la forma nueva, re-alinea al
  escritorio actual y recalcula el `radius` con el `viewRadius` nuevo (los
  `PropertyChanges` de los estados mueren al primer arrastre/flecha/rueda;
  el handler reescribe rotation/radius explícitamente).

## 2. Sólido: caras

- Cada cara = captura del **wallpaper real** de su escritorio (QML, sin shader)
  - las ventanas de ese escritorio.
- Sin piel/superficie entre caras.
- Sin espejo ni reflexión de contenido (exigirían shader; fuera).

## 2.0 Transparencia de caras (opacidad al girar)

Las caras pueden ser semitransparentes mientras el cubo gira, para ver el casco
y las caras de detrás a través del sólido (como la transparencia de Compiz). En
reposo vuelven a ser opacas por defecto. Es modificable y aplica a **las dos
formas**: la opacidad se aplica al material de cada cara, no a su geometría,
así que la malla curva del cilindro (ADR-025) la hereda sin cambios.

| Clave                 | Tipo   | Rango  | Default | Requerimiento                                                     |
| --------------------- | ------ | ------ | ------- | ----------------------------------------------------------------- |
| `FaceOpacity`         | Double | 0.1–1  | 1       | Opacidad de las caras en reposo (1 = opacas, como el cubo virgen) |
| `FaceRotationOpacity` | Double | 0.1–1  | 0.7     | Opacidad de las caras SOLO mientras gira (semitransparente)       |
| `FaceFadeMs`          | Int    | 0–1000 | 120     | Fundido entre opacidad de reposo y de giro (0 = corte seco)       |

Reglas:

- «Gira» es la misma señal que la atenuación del casco: arrastre con el puntero
  (`CubeCameraController.busy`) **o** la animación de rotación (flechas,
  activación, cambio de escritorio). El zoom con rueda NO cuenta.
- Mínimo 0.1 (no 0): una cara invisible no se puede elegir ni clicar; el rango
  evita el sólido fantasma.
- La opacidad multiplica el alfa del material de la cara (ADR-026: `PrincipledMaterial.opacity`
  con `alphaMode` por umbral — `Mask` en reposo **solo en las caras
  cilíndricas** (`alphaCutoff` explícito 0.5), `Blend` al girar; el polígono y
  la hoja conservan `Blend` en reposo, paridad con el look virgen de ADR-023);
  el casco NO se atenúa por esto (eso es `DimWhileRotating`, §5.1, y sigue siendo
  independiente).
- **Todas las caras se pintan siempre** (ADR-023, sustituye el LOD de
  ADR-022 punto 3): no hay ocultado por orientación. Con `CubeFaceDisplacement
  > 0` los interiores de las caras traseras se ven a través de los huecos
  > entre caras (el cubo usa materiales sin culling); es **intencionado** — es
  > el look del cubo virgen de KDE, y ocultar esas caras abría agujeros por los
  > que asomaba el casco en reposo (medido en el anidado 2026-11-25). El coste
  > de capturas se atacará con LOD real por distancia cuando llegue
  > WindowLayering (§2.1), no por orientación. Con alfa < 1 el material entra en
  > el pase transparente de QtQuick3D, que ya ordena de atrás hacia delante; no
  > se reordena el modelo a mano.

## 2.1 Capas de ventana (z-index / separación de ventanas)

Con `WindowLayering` activo, cada ventana de una cara es su propio quad 3D,
empujado hacia **FUERA** del sólido (+z, la normal de la cara) según su orden de
apilado real (z-index del escritorio) — **enmienda medida 2026-11-27**: hacia
dentro los huecos dejaban ver el interior del cubo (cuña blanca de quads/caras
lejanas, «ABA» espejado) y las ventanas se leían hundidas, y el quad casi
coplanar con su cara parpadeaba al girar (sort de centroides inestable). La cara
NO se mueve: sigue siendo la superficie del shell, pero su grab pone `wId = ""`
en cada ventana que gana capa — el compuesto queda con un **hueco transparente**
exacto donde estaba la ventana (el hueco se queda: sin él, la ventana plana y su
quad se dibujarían doble) y el quad flota **delante de su propio hueco**, siendo
la ventana de mayor z-index la **más cercana al observador**. El **plate vela los
huecos** (z = −2, justo detrás del plano de la cara) para que no asome el
interior. Las ventanas solapadas se separan en profundidad y la de atrás
se ve por los bordes del hueco (parallax). Con el flag apagado (default) una cara
= un compuesto plano, píxel a píxel como hoy (ADR-028).

| Clave                     | Tipo   | Rango    | Default   | Requerimiento                                                                                     |
| ------------------------- | ------ | -------- | --------- | ------------------------------------------------------------------------------------------------- |
| `WindowLayering`          | Bool   | —        | **false** | Cada ventana como capa 3D (si false, una cara = un compuesto plano; paridad píxel con el virgen)   |
| `WindowLayerGap`          | Int    | 0–600 px | 120       | Paso de profundidad entre capas (hacia fuera, +z); 0 = todas a +ε, paridad con el plano                 |
| `WindowLayerLodFaces`     | Int    | 0–8      | 1         | Caras alrededor del escritorio actual con capas (distancia por índice; 0 = todas)                  |
| `WindowLayerPlateOpacity` | Double | 0–1      | 0.25      | Velo oscuro justo detrás del plano de la cara (z = −2): vela los huecos para que no asome el interior del sólido (0 = sin velo)      |
| `WindowLayerRotationOpacity` | Double | 0–1   | 0.7       | Opacidad ABSOLUTA de las capas al girar (en reposo valen SIEMPRE 1); 1.0 = ventanas sólidas también al girar, ordenadas por profundidad; default = paridad con el fundido de la cara |
| `WindowLayerThickness`    | Int    | 0–300 px | **24**    | Grosor simulado: la capa es UNA caja cerrada (frente texturizado + cantos del color de canto); el **efectivo** se recorta a gap/2 (dos capas jamás se atraviesan); 0 = plano (paridad píxel) |
| `WindowLayerEdgeColor`    | Color  | —      | #141719   | Color de los cantos del slab (mismo tono oscuro del velo por defecto); solo se ve con grosor efectivo > 0 |

Reglas:

- Tope global del stack: **150 px**. Si no cabe, se **reparte** el paso sobre
  los `maxRank + 1` pasos que ocupa el stack (mismo paso menor para cada rango,
  orden preservado, sin aplanar dos capas en un plano) y la capa **más exterior**
  cae EXACTA en el tope (+`cap`, con el ε fuera).
- Presupuesto: **cap directo en TODAS las formas** (polígono, hoja y tambor). El
  presupuesto por representación `min(faceDistance · 0.5, cap)` quedó **sin
  efecto** con la enmienda: hacia fuera no hay paredes interiores que proteger
  (el `maxLayerDepth` por forma desapareció del código).
- Dirección: la ventana de **mayor z-index es la más cercana al observador** (la
  más exterior). **El stack flota entero** (medido 2026-11-27: con la de abajo
  en el +ε puro se leía «pegada al escritorio todo el tiempo»): la de abajo
  (rank 0) arranca a **+paso** (`fittedGap + ε`), cada rango sube un paso más y
  la de arriba cae en el tope (+`cap + ε` con overflow; una sola ventana con gap
  grande queda EXACTA en +cap). Excepción deliberada: **gap 0 = todas pegadas al
  plano (+ε, paridad con el cubo vírgen)**.
- **Orden en reposo (medido 2026-11-27)**: el centroide del quad no respeta el
  rank (lleva el offset lateral de su ventana), así que los quads usan el umbral
  Mask/Blend de ADR-026 sobre su opacidad efectiva: `≥ 0.99 → Mask` con
  `alphaCutoff 0.5` clavado (pase opaco, escribe profundidad — **en reposo gana
  el mayor z-index por geometría**, el interior lejano no gana píxeles),
  `< 0.99 → Blend` (al girar el orden vuelve a centroides: el intercambio
  residual solo existe **mientras gira**).
- **Opacidad de giro propia (`WindowLayerRotationOpacity`)**: en reposo las
  capas valen SIEMPRE 1; al girar toman el valor de la clave (absoluto; default
  0.7 =
  paridad con el fundido de la cara porque
  `Constants.faceOpacity(1, v, true) == v` y 0.7 es también el default de
  `FaceRotationOpacity`). Con 1.0 las ventanas quedan sólidas **y
  depth-ordered también al girar**; con valores bajos se vuelven velo. El plate
  funda con la pila (`plateOpacity × layerOpacity`). **Con capas apagadas las
  ventanas comparten la transparencia del escritorio (son píxeles del grab);
  esta clave solo actúa con las capas activas** (gate (g1): flag off + la clave
  a 0.2/0.7/1.0 → cero quads, grab íntegro, materiales de la cara siguen
  dependiendo solo de faceOpacity). Trade-off conocido: en reposo el borde
  AA/sombra de la ventana se corta duro en el cutoff (misma clase del hueco en
  cilindro).
- **Trade-off medido y aceptado**: al orbitar, los quads pueden asomar fuera de la
  silueta de su cara (ventanas flotando sobre el escritorio). Es el look pedido
  (metáfora del escritorio), no un defecto.
- **Grosor simulado (cuarta ampliación, 2026-11-27; rediseño medido
  2026-11-28)**: con `WindowLayerThickness` > 0 (default **24**; el primer
  default 2 se midió invisible en el anidado — «sigue sin grosor»: la caja se
  construía pero el canto de 2 px no se leía) cada capa es
  **una sola caja cerrada** — un `ProceduralMesh` unitario compartido con dos
  subsets de material: subset 0 el frente (texturizado con la ventana, UVs
  idénticas al `#Rectangle` probado — el índice frontal es construido, no
  adivinado), subset 1 los cuatro cantos + la posterior con
  `WindowLayerEdgeColor`; ambos materiales con `BackFaceCulling`. La vía "un
  cubo con seis materiales" no existe (`Model.customMaterials` no está en Qt
  6.12, medido en el motor vivo; el built-in **#Cube** es un solo subset), y el
  intermedio "quad delante + cubo detrás sin culling" quedó refutado con
  captura: los márgenes transparentes del thumbnail dejaban ver el interior
  negro de la caja — un bisel gigante, no un canto. Reglas: el grosor
  **efectivo** es `min(solicitado, fittedGap/2)` → dos capas **jamás se
  atraviesan** (pedir más que gap/2 no separa nada, se recorta); la caja mide
  el **rectángulo exacto** de la ventana (el margen de sombra del grab NO
  entra: por eso 24 px se leen como sólido en oblicuo, sin margen de sombra
  que se convierta en bisel); **el frente de la caja marca la
  profundidad** — el nodo se centra en `layerDepthOut − eff/2` y la ladder y el
  tope 150 siguen midiendo el frente, no el centro; **0 = plano exacto**
  (paridad píxel con el modelo sin grosor; sin `QtQuick3D.Helpers` la caja
  degrada a plano, el patrón arc/capas). **Regla visual del sólido**
  (medido 2026-11-28: el canto sin luz era un color plano que «se lee como
  sombra»): el material de canto lleva `lighting: Fragment` (roughness 0.7,
  metalness 0) y la escena añade un **headlight en la cámara**
  (DirectionalLight con offset euler (25, −35), brightness 0.8) **solo
  mientras `WindowLayering` está activo** — flag off = cero nodos nuevos,
  paridad estricta del cubo virgen también en el árbol; el frente, las caras
  y el plate siguen NoLighting (ADR-026).
- Profundidad **fija** mientras gira (no se anima): el stack se lee como un sólido;
  animar el hueco produce un «pop» al parar.
- Solo cuentan las ventanas de esa cara/escritorio/pantalla. Descartes: las
  minimizadas no existen (igual que en el plano); **docks y ventana-wallpaper
  quedan planos en el grab, nunca se huecan** (un hueco sin su quad delante solo
  mostraría el velo: ventana fantasma). La capa de una ventana se libera con `wId = ""` (QUuid nulo,
  trucos-aprendidos §N), no con `visible: false`.
- **LOD = presupuesto de coste, no de orden**: el culling de `Model` no se propaga
  al `Texture.sourceItem`, así que una capa instanciada cuesta una captura por
  frame aunque no se vea; `WindowLayerLodFaces` limita cuántas caras instancian
  quads (distancia de índice al escritorio actual) y las demás mantienen el
  compuesto plano. El orden de pintado NO depende del LOD: lo dan los centroides de
  la pasada transparente (ADR-026) y el `Mask` con escritura de profundidad en
  reposo.
- Semántica ángulo/transparencia: en reposo (opacidad 1) cada cara es opaca, cada
  hueco lo cubre su propio quad flotando delante (y el velo a z = −2 detrás) — el
  escritorio se lee plano salvo por las capas; al girar
  (`FaceRotationOpacity`, ADR-021) las caras funden y se ven las pilas de las otras
  caras a través; en ángulo de dos caras simultáneas ambas pilas se ven y ordenan
  por centroide; en vistas muy picadas de arriba/abajo, con muchas ventanas, los
  stacks asoman por huecos y caras translúcidas. **La pila (quads + plate) funda
  con su propia opacidad de giro** (`WindowLayerRotationOpacity`, § arriba; el
  default 0.7 la hace fundar igual que la cara out-of-the-box): si solo fundiera
  la base, al girar quedarían ventanas duras sobre cara derretida.
- Picking: el quad es `pickable` y hace lo de su cara (clic → ese escritorio).
  Activar la ventana clickeada **no** se implementa aquí: `Workspace::activateWindow`
  no es QML-expuesto para efectos (medido en `/usr/include/kwin`: `Window` solo
  expone `setMaximize`). Queda anotado como feature futura del módulo nativo. Esta
  feature no toca C++ y debe seguir funcionando sin compilar.
- Orden determinista: mapa `internalId → stackingOrder` + contador `revision` que
  re-evalúa posiciones (no depende del orden de delegates); ventana cerrada sale del
  mapa (los `internalId` se reciclan y una entrada vieja daría rango equivocado a la
  siguiente ventana con ese id).
- Pasos dentro de la MISMA versión (0.0.0.6): primero polígono (sólido ≥3 y hoja
  1-2 — funciona desde 1 escritorio), después tambor (cilindro 1-2). Si en la
  verificación del anidado el tambor no cierra (coste o visual), las capas del
  tambor se apagan por código y esa fase se pospone sin cambiar de versión.
- Futuro con clave propia: curvar/deformar las capas con el cilindro (esta feature:
  quads **planos** sobre la normal de la cara) y colisiones con otros efectos.
- UI del KCM (**enmienda 2026-11-27**, sustituye el reparto ADR-014 original):
  la pestaña **Ventanas** lleva `WindowLayering` + `WindowLayerGap` +
  `WindowLayerPlateOpacity` + `WindowLayerRotationOpacity` +
  `WindowLayerThickness` + `WindowLayerEdgeColor` — son configuración
  normal de la feature (los cinco controles arrancan deshabilitados y siguen al
  checkbox; el color de canto solo se nota con grosor > 0). **Avanzado** conserva SOLO
  `WindowLayerLodFaces`: es un presupuesto de coste GPU por frame, no un ajuste de
  aspecto, y ahí sí aplica el patrón ADR-014. Las claves del esquema (main.xml) no
  se mueven: solo cambia dónde se pintan los controles.

## 2.2 Tapas (superior e inferior)

Dos superficies de cierre del sólido: la tapa de **arriba** y la de **abajo**, una
en cada extremo del eje Y (a `y = ± faceHeight/2`). Cada una se habilita por
separado y pinta un contenido propio (color, degradado o imagen) con su propia
transparencia. Cierran el volumen por los extremos, pero **no** son una «piel»
lateral: entre las caras sigue viéndose el casco (ADR-003 intacto en eso).

| Clave             | Tipo  | Rango                                            | Default   | Requerimiento                                                                                                      |
| ----------------- | ----- | ------------------------------------------------ | --------- | ------------------------------------------------------------------------------------------------------------------ |
| `CapTop`          | Bool  | —                                                | false     | Habilita la tapa superior                                                                                          |
| `CapBottom`       | Bool  | —                                                | false     | Habilita la tapa inferior                                                                                          |
| `CapContent`      | Enum  | Color 0 / Gradient 1 / Image 2 / Arrow 3         | **3**     | Qué pinta la tapa: color, degradado, imagen o marcador de orientación (flecha cian + cuadrante magenta; ver abajo) |
| `CapColor`        | Color | —                                                | `#1b3fd8` | Color sólido (y respaldo cuando la imagen falla)                                                                   |
| `CapColor2`       | Color | —                                                | `#0a1a5e` | Segundo color del degradado                                                                                        |
| `CapGradientType` | Enum  | LinearVertical 0 / LinearHorizontal 1 / Radial 2 | 0         | Tipo de degradado                                                                                                  |
| `CapGradientStop` | Int   | 0–100                                            | 50        | Proporción del degradado (posición del corte: 0 = todo `CapColor2` salvo borde, 100 = transición hasta el final)   |
| `CapImage`        | Url   | —                                                | vacío     | Imagen local de la tapa (solo `file:`/ruta local; nada remoto)                                                     |
| `CapImageFit`     | Enum  | Cover 0 / Contain 1 / Stretch 2                  | 0         | Ajuste de la imagen                                                                                                |
| `CapOpacity`      | Int   | 0–100                                            | 80        | Opacidad de la tapa (0 = transparente, 100 = opaca)                                                                |

Geometría por forma (una sola malla compartida, ver abajo):

- **Polígono** (3+ escritorios): la tapa se acota a las **esquinas de cara**,
  no a la intersección de los planos (ADR-027 enmendado). Con N =
  `geometryCount` (= max(3, nº escritorios)) y apotema = `faceDistance`
  (`W/2 / tan(π/N) + CubeFaceDisplacement`), la regla tiene **dos ramas
  continuas en d = 0** (`betaCara = atan((W/2)/apotema)`, `halfStep = π/N`):

  - `d ≤ 0` (`betaCara ≥ halfStep`, tolerancia 1e-9 rad): las caras se
    tocan o solapan y la tapa es el **N-gono inscrito de siempre** (N
    vértices a `apotema / cos(π/N)`, cada lado sobre el plano de una cara).
    Cero regresión del look virgen.
  - `d > 0` (`betaCara < halfStep`): las caras están separadas; 2N
    vértices en las **esquinas reales de cada cara** (`rho = hypot(apotema,
W/2)`, azimuts `step·k ± betaCara`). Cada cara queda cubierta de canto
    a canto (`|tangencial| = W/2` EXACTO) y el hueco entre caras se cierra
    con una **cuerda recta** entre la esquina derecha de una cara y la
    izquierda de la siguiente — cuerda que queda POR DENTRO de los planos
    (`apotema − d·sin²(π/N)`), así que el casco sigue viéndose a través del
    hueco: la tapa sella las caras, no los agujeros.

  Invariantes duras (medidas por `scripts/check-cap.py`, evaluadas **por
  cara en el marco local de esa cara**, nunca contra ejes del mundo): ningún
  vértice asoma por fuera del plano de ninguna cara (`dot(v, n_k) ≤
apotema`) y ninguno cruza la esquina de la cara sobre la que está
  (`|dot(v, t_k)| ≤ W/2`). La fórmula antigua (solo el N-gono
  `apotema/cos(π/N)` a cualquier d) sacaba puntas tangenciales de hasta
  +519.6 px (n=3, d=300, W=2560) — ver la enmienda en el ADR-027.

- **Cilindro** (tambor, a cualquier count incluido el tambor de 3 slots con
  1-2 escritorios): la tapa es un **disco** de radio `R = cylinderRadius`
  (la misma `R = N·(W+g)/2π` de ADR-025, con `g` del usuario), triangulado en
  **abanico** con `CYLINDER_SEGMENTS` (64) segmentos. Tapa también las cuñas
  vacías del tambor. Misma posición `y = ± faceHeight/2`.
- **Hoja 2D** (`Polygon` con 1-2 escritorios): no hay volumen, así que las
  tapas quedan **deshabilitadas por código** (no es una opción del usuario),
  igual que el Interior (§4): una hoja plana no encierra nada que tapar.
- **Malla compartida**: UNA sola `ProceduralMesh` por forma, reutilizada por las
  dos tapas (espejadas por rotación), igual que las caras comparten
  `CylinderArcMesh` (ADR-025). Sin shader: la tapa es un polígono plano (o
  disco) con la textura de contenido. **El eje del flip es Z, no X** (ADR-027
  enmienda 2, medido con píxeles por el gate retirado (doc/trucos-aprendidos.md sección P)): la tapa
  inferior es el mismo nodo con `eulerRotation.z: 180`, el único giro de 180°
  que vuelca la normal +Y → −Y **y** deja el anillo invariante (manda
  α → −α). Con `eulerRotation.x: 180` (α → 180°−α) el anillo quedaba girado
  medio tick: los vértices llegaban a 928 sobre la normal de cara (pared a
  472 → la tapa atravesaba las caras) y la frontera en el azimut del hueco
  caía a 472 (no cerraba la esquina) — el bug "180° volteado" reportado.
- **Culling / normales**: coherente con las caras → `Material.NoCulling`
  (ADR-025 punto 12 revertido): la tapa se ve igual desde arriba y desde abajo.
- **Orden de pintado**: las tapas aportan centroides de ordenación propios en
  Y (±H/2); la regla de ADR-026 (centroides + `alphaMode` explícito por
  umbral) se extiende a ellas (ADR-027 enmienda 2): **`Mask` con
  `alphaCutoff: 0.5` desde `CapOpacity` ≥ 99** (escribe profundidad: ningún
  empate de orden puede pintar una tapa lejana sobre una cara cercana) y
  **`Blend` por debajo** (transparencia translúcida real, ordenada por
  centroides). Nunca `Opaque`/`SetToOpaque`: pintaría de negro los agujeros
  de alfa (medido en ADR-026).
- **Marcador de orientación (Arrow, default nuevo)**: una tapa de color
  uniforme no permite leer rotación ni espejo — no se puede distinguir "la
  tapa está girada" de "la tapa se pinta encima" — así que `CapContent`
  cambia su default a **Arrow (3)** (añadido AL FINAL del enum: los enteros
  guardados no se mueven; los kwinrc existentes conservan su valor). El
  marcador (`CapArrow.qml`) dibuja sin assets: fondo `CapColor`, **flecha
  cian** apuntando al borde superior del ítem (que según el grab medido
  corresponde a `v → 1` = +z local, el azimut de la cara 0) y **cuadrante
  magenta** en la esquina superior-izquierda — la flecha sola no basta porque
  un espejo puede parecer un giro; el cuadrante los distingue (el espejo Z de
  la tapa inferior mueve el cuadrante de lado x; un giro lo movería a otra
  esquina). `QtQuick.Shapes` es OPCIONAL aquí también (patrón HullRadial,
  ADR-022): `CapArrow.qml` se carga tras un `Loader`; sin el módulo la tapa
  degrada a `CapColor` plano y avisa **una vez**. Con `DebugOverlay` activo
  las tapas se pintan SIEMPRE en modo Arrow (diagnóstico sin tocar el valor
  guardado). Fijado en su momento con píxeles por el gate retirado (sección P de trucos; tabla de
  centroides por tapa y yaw).

Transparencia y contenido:

- `CapOpacity` es **Int 0–100** (como `DimWhileRotatingAmount`), no Double: un
  helper de `constants.js` lo pasa a 0..1 (`capOpacity`). Los resolvedores
  `capContent` / `capGradientType` / `capImageFit` caen a los **defaults de la
  tabla** cuando el valor guardado está fuera de rango (el patrón
  `backgroundMode` / `imageFit`).
- Los Enum se guardan como **entero** en kwinrc (regla KConfigXT: un string
  rompe el entorno, `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`); grupo
  `[Effect-kube-effect]`.
- Imagen **local** obligatoria (mismo filtro que `backgroundImageSource`): el
  compositor no descarga contenido al activarse. Si la imagen no existe o
  falla, la tapa cae a `CapColor` y avisa **una vez** (el patrón del vídeo de
  fondo).
- **Fuera de alcance (todavía no)**: vídeo como contenido de tapa, figuras
  animadas. Se recoge en §7.

## 3. Casco (espacio alrededor) — configurable

El casco es la ZONA (el espacio que rodea al sólido). Se pinta de varias formas
(modos). **SkyBox no es un modo aparte**: es la variante de "Imagen" con una
panorámica 360.

| Modo (`Background`)    | Qué pinta                                                                                                                                                                                                                                                                                   | Claves reales (tipo, rango, default)                                                                                                                                                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Color** (0, default) | Un color sólido                                                                                                                                                                                                                                                                             | `Background` Enum; `BackgroundColor` Color, default `#1b3fd8`                                                                                                                                                                                                          |
| **Image** (1)          | Imagen de fondo. Si el mapeo resuelve equirect **y** gira con el centro es **SkyBox** (entorno 360); si no, capa plana fullscreen estática                                                                                                                                                  | `SkyBox` Url (vacío = sin imagen); `BackgroundImageLayout` Enum (ver abajo); `BackgroundImageRotate` Bool default true; `BackgroundColor` actúa de color de respaldo                                                                                                   |
| **Gradient** (2)       | Degradado de dos colores sin shaders (Rectangle + Gradient QML). Tipos: vertical (arriba→abajo), horizontal, radial (real con Shapes; **opcional**: sin el módulo cae al lineal y avisa una vez)                                                                                            | `Background` Enum; `BackgroundGradientType` Enum (ver abajo); `BackgroundColor` Color `#1b3fd8`; `BackgroundColor2` Color `#ff8a00`; `BackgroundGradientStop` Int 0–100, default 50 (posición del corte: 0 = todo color2 salvo borde, 100 = transición hasta el final) |
| **Video** (3)          | **Vídeo** de fondo, igual que una imagen con otra fuente: equirect **y** girando = panorama 360 animado en una cúpula (ADR-020); Flat **o** sin girar = capa plana fullscreen con el ajuste. Requiere el módulo opcional QtMultimedia; sin él se pinta `BackgroundColor` y se avisa una vez | `BackgroundVideo` Url (vacío = sin vídeo; solo `file:`); `BackgroundImageLayout` / `BackgroundImageFit` / `BackgroundImageRotate` (compartidas con la imagen); `BackgroundColor` de respaldo                                                                           |
| (arena, futuro)        | Atenuación global del casco (0 = sin atenuar, 1 = negro)                                                                                                                                                                                                                                    | (sin clave aún) `CascoDim` reservado                                                                                                                                                                                                                                   |

- `BackgroundColor` (#1b3fd8 azul) y `BackgroundColor2` (#ff8a00 naranja) son los
  defaults **nuevos** de `main.xml`, elegidos para que el degradado se note de un
  vistazo.
- Enum `BackgroundImageLayout`: `Equirect` (forzar 360) / `Flat` (forzar plano). Ya no existe `Auto`: el usuario elige explícitamente si la imagen es panorámica o plana. La **clave** se renombró a propósito (antes `BackgroundImageMapping`): kwinrc guarda el índice, así que un valor viejo queda huérfano y se ignora en vez de reinterpretarse como `Flat`.
- `BackgroundImageFit` (Enum, default `Cover`): `Cover` / `Contain` / `Stretch`. Solo aplica a lo que va plano (imagen plana, equirect sin rotación, y el vídeo plano); decide cómo encaja en pantalla.
- `BackgroundImageRotate` (Bool, default `true`): solo aplica al mapeo equirect. `true` = entorno 360 que gira con el centro (SkyBox); `false` = capa plana estática fullscreen que no rota al mover la cámara. Compartida por imagen y vídeo.
- **Vídeo** (`Background=Video`, índice 3): el vídeo se trata **exactamente como una imagen** con otra fuente. `BackgroundVideo` es un Url local (`file:`; una URL de red se ignora) y el mapeo/ajuste/giro son las mismas tres claves de la imagen, en un grupo compartido del KCM («Imagen o vídeo: cómo se muestra»). Reproduce en bucle, sin sonido y **solo con el efecto visible** (pausa al desactivar, reanuda al activar). En la variante 360 el `BackgroundImageFit` **no aplica**: el `VideoOutput` fuerza el fotograma completo (Stretch) porque la esfera es la que envuelve; el ajuste solo manda en la capa plana. Atenuación al girar: velo 2D si va plano, esfera-velo negra si va como 360 (el entorno no puede muestrear un `VideoOutput`: ADR-020). **Dependencia opcional** `QtMultimedia`: si el módulo no está instalado, el vídeo se sustituye por `BackgroundColor` y el efecto sigue funcionando (ver §5.1).
- Solo se aceptan recursos **locales**: la imagen admite `file:` o `image:`, el vídeo (`BackgroundVideo`) solo `file:`; una URL de red se ignora en ambos casos (el compositor no descarga contenido al activar el efecto).
- Un camino **sin esquema** debe ser **absoluto**: uno relativo se resolvería contra el directorio de trabajo del compositor, que el efecto no define. Y cualquier segmento `..` descarta el recurso (camino de subida), también dentro de `file:` y de `image:`. Es **defensa en profundidad contra un kwinrc editado a mano, no una frontera de seguridad**: quien escribe `[Effect-kube-effect]` ya controla la sesión, y una ruta absoluta a cualquier fichero legible sigue aceptándose (eso es justo lo que escriben los selectores del KCM). Las reglas viven en `localSource()` (`constants.js`), compartidas por imagen, vídeo y `CapImage`.
- **KCM genérico con UI dinámica, sin C++**: `kcm_kwin4_genericscripted` solo carga
  `config/main.xml` y `config.ui` con QUiLoader; no hay `config.qml` ni lógica propia y
  `KConfigDialogManager` no admite dependencias entre entries. La pestaña Background usa un combo
  `kcfg_Background` + un `QStackedWidget` con una página por modo (en orden del enum) y una
  conexión de Qt Designer (`<connections>`: `currentIndexChanged(int)` → `setCurrentIndex(int)`)
  que QUiLoader recrea: al cambiar el modo solo se ven sus opciones. Un `kcfg_<Entry>` = un único
  widget, así que `BackgroundColor` (color sólido, primer color del degradado y respaldo de la
  imagen) va fuera del stack y siempre está visible.
- Al desactivar el efecto no queda nada pintado: el casco (color, degradado o imagen) se dibuja en
  la escena del efecto, no en el color de la ventana, y desaparece con él.
- Enum `BackgroundGradientType`: `LinearVertical` (0, default, arriba→abajo) / `LinearHorizontal` (1) / `Radial` (2, centrado). Enum = entero en kwinrc (grupo `[Effect-kube-effect]`).
- **Radial sin shader**: se implementa con `QtQuick.Shapes.RadialGradient` (expone `centerX/centerY/centerRadius/focal*` y `stops` en Qt 6.12); deja de caer a vertical. **No** hay tipo cónico/circular. No se inventan shaders ni C++.
- **Shapes pasa a ser opcional** (ADR-022): el radial vive en `HullRadial.qml`, cargado con `Loader` desde `HullGradient.qml`. Si el módulo `QtQuick.Shapes` falta, solo ese `Loader` falla: el degradado cae al lineal existente y se avisa **una vez** por log. Antes el import era dependencia dura de TODO el efecto (sin Shapes no había ni placeholder); las features `background-color`/`background-gradient`/`background-gradient-rotation` pasan a `requires: []` en `features.json`.
- `BackgroundGradientRotation` (Enum, default `Fixed`, solo casco degradado):
  `Fixed` (0) no gira; `FollowCube` (1) gira el degradado con el yaw del cubo;
  `FollowCubeInverse` (2) gira en sentido contrario. La rotación lineal es un
  `Rotation` sobre un `Rectangle` sobredimensionado (no se recrean objetos por
  frame). En `Radial` no se gira (un radial centrado es simétrico): se desplaza el
  **punto focal** sobre un círculo de radio `0.25 · max(w, h)`; con `Fixed` el foco
  queda en el centro.
- **SkyBox** = casco con imagen 360 equirectangular (entorno que envuelve la escena y gira con el centro). **Vídeo 360** = su versión animada: una esfera vista desde dentro con el `VideoOutput` como `baseColorMap` (Qt rechaza un `Texture.sourceItem` como `lightProbe`; ADR-020).
- Nombres antiguos del spec (`CascoColor`, `CascoColor2`, `CascoGradientType`, `CascoMode`): equivalen a `BackgroundColor`, `BackgroundColor2`, `BackgroundGradientType`, `Background`. Se documentan con las claves reales para no romper compatibilidad con kwinrc existente (`Background=0/1/2` conserva su significado; el índice 1
  pasó a llamarse `Image`).
- El casco se ve alrededor del sólido y por los huecos entre caras.
- No es la superficie del sólido (esa no existe).

## 4. Interior — objetos decorativos

- Objetos 3D y 2D, **animados por defecto**, además de imágenes y vídeos.
- Capacidad a cubrir (todos):
  - Objeto 3D **animado** (p. ej. planetas orbitando).
  - Objeto 3D **estático** (quieto aunque el sólido gire).
  - **Vídeo** como objeto interior.
  - **Imagen 2D** estática dentro del sólido (no en la cara).
- Arranque (2 objetos): **planetas** + **mini-cubo**. Los demás se añaden después,
  pero el sistema debe soportarlos todos.
- Sólo existe con volumen (3+ escritorios). Con 2 (hoja 2D) queda deshabilitado.

### 4.1 Modelo del usuario (ADR-029)

Primer objeto interior implementado: **el propio usuario elige un modelo 3D desde su
disco**. No hay catálogo, ni descarga, ni conversión, ni compilación: el KCM pone un
selector de fichero y el efecto lo carga tal cual.

- `ModelFile` (Url, default vacío = apagado): el usuario pulsa «Examinar…» y elige el
  fichero. Vacío ⇒ no se carga nada ni se crea el nodo (cero coste para quien no lo use).
- **Solo ficheros locales**, con el mismo filtro que la imagen de fondo y la imagen de
  tapa (`localSource`): `file:` o ruta absoluta sin esquema. Un `http(s):`/`qrc:` se
  descarta — el compositor no descarga contenido al activarse (§2.2, misma regla).
- **Formatos aceptados**: `.glb`, `.gltf` y `.obj`, leídos **en runtime** por
  `RuntimeLoader` (`QtQuick3D.AssetUtils`). Nada de `.fbx`/`.dae`/`.stl`: el cargador de
  runtime de Qt no los soporta, y tampoco lo hace `balsam` sin pasos extra.
- **El modelo es responsabilidad del usuario** (decisión explícita del ADR-029): que salga
  de Sketchfab/Poly Haven/Fab y lo exporte él. Lo que Qt **no** puede leer, medido en
  Qt 6.12 con ficheros generados por `gltf-transform`:
  `KHR_draco_mesh_compression`, `EXT_meshopt_compression` y `KHR_mesh_quantization`
  devuelven `RuntimeLoader.Error` (y `balsam` no saca ninguna malla de ahí tampoco).
  Los glTF **sin comprimir** sí cargan (`KHR_materials_unlit` incluido).
- `ModelScale` (Double 0.05–50, default 1.0) es un **multiplicador** del auto-ajuste, no
  una escala absoluta: el efecto mide `bounds` del modelo y lo encoge/crece para que quepa
  dentro del sólido (60 % de la altura interior). Así un modelo en metros (1.7) y uno en
  unidades de 400 quedan visibles sin que el usuario calcule nada. Con `bounds` todavía
  inválido (antes del primer frame renderizado) el nodo permanece invisible.
- **Degradación**: el `import QtQuick3D.AssetUtils` vive aislado en `InteriorModel.qml`,
  cargado con `Loader`. Si el módulo falta, solo ese Loader falla; el cubo se pinta igual.
  Si el fichero está mal o es ilegible, se avisa **una vez** con el `errorString` de Qt
  (así el usuario ve que su `.glb` venía comprimido con Draco) y no se pinta nada.
- Rotación: el modelo es **hijo del sólido**, gira con él (ADR-027/ADR-028 no lo separan).
  El objeto «estático aunque gire» del listado de arriba sigue sin implementar.
- Sin `native/`: la feature es 100 % QML (`native: false` en `features.json`).

## 5. Activación y comportamiento

| Clave                  | Tipo   | Rango       | Default | Requerimiento                                                                                                                                                                                                                                                                                                                                                                        |
| ---------------------- | ------ | ----------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BorderActivate`       | String | "1,7"       | vacío   | Bordes de pantalla (puntero) que activan el sólido (1=Arriba…8=ArribaIzq)                                                                                                                                                                                                                                                                                                            |
| `TouchBorderActivate`  | String | "5"         | vacío   | Igual, con toque                                                                                                                                                                                                                                                                                                                                                                     |
| `MouseInvertedX`       | Bool   | —           | false   | Invertir eje X del arrastre                                                                                                                                                                                                                                                                                                                                                          |
| `MouseInvertedY`       | Bool   | —           | false   | Invertir eje Y del arrastre                                                                                                                                                                                                                                                                                                                                                          |
| `CursorScreenOnly`     | Bool   | —           | false   | Dibuja el cubo solo en el monitor donde está el cursor al lanzarse; el resto de pantallas quedan normales. Sustituye al antiguo «casco por pantalla»; default `false` = todas las pantallas                                                                                                                                                                                          |
| `CubeFaceDisplacement` | Double | −500…500 px | 100     | Separación entre caras. 0 = caras pegadas; **negativo = se solapan** (el polígono encoge); positivo = huecos. **En cilindro (todos los counts, tambor y tambor de tres slots) es el hueco lineal entre arcos: los valores negativos se tratan como 0** (ADR-025/ADR-026 — g también rige R = 3(W+g)/2π con 1-2). La hoja plana (Polygon 1-2) no lo usa (su separación es `sheetGap`) |
| `DistanceFactor`       | Double | 0.5–5       | 1.75    | Distancia de la cámara al activar                                                                                                                                                                                                                                                                                                                                                    |

- Atajo por defecto: **Meta+K**. Se registra con `ShortcutHandler` → **KGlobalAccel**, y se
  cambia en **Preferencias del sistema → Atajos de teclado → KWin → «Toggle Kube Effect»**
  (estándar KDE). No se duplica en el KCM del efecto a propósito: `KGlobalAccel` guarda el
  valor en `kglobalshortcutsrc` y ese valor **pisa** al `sequence` del QML, así que una clave
  en `main.xml` sería una segunda fuente que nunca manda. El KCM solo muestra un aviso.
- Giro por arrastre del ratón y teclado; zoom por rueda **con límites**
  (ADR-022): el radio queda entre `0.6 · safeViewRadius` y `8 · safeViewRadius`
  — el apotema del polígono o el **radio R del tambor** (ADR-026: con 1-2
  cilindros R es el del tambor de tres slots, 3(W+g)/2π), pinned positivo—.
  Nota honesta: la rueda **sí puede** meter la cámara dentro del sólido
  (hasta 0.6·R) — es posible a propósito: el cilindro muestra su interior
  por los huecos igual que el polígono (`NoCulling` siempre,
  ADR-023/ADR-025 pt.12; el overlap que eso dejaba ver ENCIMA de las
  frontales quedó resuelto en ADR-026, diagnosticable con `blend=`). Lo que los límites
  evitan es el fallo real: por debajo de `clipNear` las caras desaparecían,
  y a distancia absurda se perdía el sólido de vista.

## 5.1 Advanced (opciones avanzadas)

Estas claves viven SOLO aquí; no se reparten por otras pestañas. **Advanced es el
único sitio para opciones avanzadas.**

| Clave                    | Tipo | Rango | Default | Requerimiento                                                                         |
| ------------------------ | ---- | ----- | ------- | ------------------------------------------------------------------------------------- |
| `DimWhileRotating`       | Bool | —     | false   | Oscurece el fondo SOLO mientras el cubo gira; vuelve al soltar                        |
| `DimWhileRotatingAmount` | Int  | 0–100 | 40      | Cuánto se oscurece el fondo al girar (solo con `DimWhileRotating`)                    |
| `CursorScreenOnly`       | Bool | —     | false   | Cubo solo en el monitor del cursor al lanzarse; default `false` = todas las pantallas |
| `DebugOverlay`           | Bool | —     | false   | Muestra estado interno del efecto en pantalla (diagnóstico)                           |

Implementación (QML puro, sin C++):

- **Atenuar al girar**: cubre los **cuatro** modos de casco, pero no siempre
  con el mismo objeto:
  - **Color / Degradado / imagen plana** → un velo negro (`hullDim`) pintado
    entre el casco y la escena 3D, así que oscurece el fondo y no las caras.
  - **Imagen 360 equirectangular (SkyBox 3D)** → `SceneEnvironment.probeExposure`
    (brillo del entorno): el SkyBox lo pinta el entorno 3D, no la capa 2D, así
    que el velo no lo alcanza y ponerlo delante del `View3D` taparía las caras.
    Se enciende mientras «el cubo se mueve»: `CubeCameraController.busy` (arrastre
    con el puntero) **o** la animación de rotación (`Behavior on rotation`, que
    cubre flechas, activación y cambio de escritorio). El zoom con la rueda no se
    considera giro. Un `Behavior` de 120 ms funde tanto el velo como la exposición
    para que no parpadeen cuando el puntero se detiene un frame.
    Fórmula única en `constants.js`: `skyBoxExposure(enabled, rotating, amount)` =
    `1.0` (sin atenuar) si `DimWhileRotating` está apagado o el cubo no gira; si
    no, `1 - dimOpacity(...)` recortado a `[0, 1]` — la misma cantidad que el velo
    2D. Nunca se aplican los dos a la vez sobre lo mismo: con el SkyBox ya pintado
    el velo 2D queda apagado (solo cubre el color de respaldo mientras la sonda
    decodifica).
- **Vídeo de fondo (dependencia opcional)**: `Background=Video` necesita el
  módulo `QtMultimedia` (paquete `qt6-multimedia` en Arch). Sin él, el
  `HullVideo.qml` cargado por `Loader` queda en `Error`, se avisa **una vez** y el
  casco se pinta con `BackgroundColor`; el resto del efecto no se toca. Advanced
  lo explica en lenguaje llano («Vídeo de fondo (opcional)»).
- **Dónde está Kube Effect Plus**: el diagnóstico, las dependencias y la versión
  compilada viven en **Preferencias del sistema → Gestión de ventanas → «Kube Effect
  Plus»** (`kcm_kube_effect_plus`), que solo aparece si se compiló `native/`. El
  engranaje del efecto sigue abriendo el menú QML de siempre: compilar **no** cambia
  ese botón. La pestaña Advanced del menú QML agrupa las claves avanzadas y una
  sección plegable que remite a Plus; no duplica las opciones del nativo.

- **Overlay de diagnóstico** (`DebugOverlay`, ADR-023): ni `console.log/warn`
  llega al journal en este KWin ni `supportInformation` por D-Bus devuelve las
  propiedades QML (cadena vacía medida en KWin 6.8.3, 2026-11-25; ver trucos
  §D). El único canal visible es pintar: con la clave activada, un texto rojo
  monoespaciado sobre el cubo muestra el estado vivo — fondo (modo, equirect,
  skybox listo), vídeo (wanted/ready/painted + `mediaStatus`), atenuación
  (`cubeMoving`, exposición), cámara (yaw/pitch/radio), geometría (caras,
  tick, distancia, cos por cara) y pantalla (nombre de la escena, del cursor,
  si pinta aquí). Máximo 2 líneas. El yaw y el pitch solo se descomponen del
  cuaternión con el overlay activo (mismo gateo que el yaw del degradado).

- **Pantalla del cursor**: al activar se captura la pantalla bajo el puntero con
  `KWinComponents.Workspace.screenAt(KWinComponents.Workspace.cursorPos)` (API
  QML de `org.kde.kwin`, disponible en KWin 6.8) y se guarda su nombre. Cada
  `SceneView` compara `SceneView.screen.name` con ese nombre: la que no
  coincide no pinta nada y deja ver el escritorio en vivo. **Limitación**: la
  pantalla se fija en la activación; si el puntero se mueve con el cubo abierto,
  el cubo no salta de monitor hasta la siguiente activación. Si un KWin no
  tuviera `screenAt`, la aproximación es la pantalla de la ventana activa
  (`Workspace.activeScreen`) — TODO: revisar en cada subida de Plasma.

## 6. Configuración (referencia)

Enum `Shape`: `Polygon` (0, default) / `Cylinder` (1) (ADR-025; tabla y
helper `shape()` en `constants.js`). El número de escritorios manda:
1 → hoja simple con giro limitado a ±80° (Polygon) o **tambor de tres slots
con 2 huecos** — cara en 0°, giro libre (Cylinder); 2 → hoja doble cara con
giro completo (Polygon) o **tambor de tres slots con 1 hueco** — caras en
0° y 120°, giro libre, tick 120° (Cylinder); 3+ → polígono o tambor
cilíndro elegido (ADR-024/ADR-025/ADR-026; el placeholder quedó retirado).

Enum `Background`: `Color` (0, default) / `Image` (1) / `Gradient` (2) / `Video` (3,
añadido al final para no reinterpretar los valores guardados). El índice 1 se
llamaba `SkyBox`; kwinrc guarda el entero, así que el valor no cambia.
Enum `BackgroundImageLayout`: `Equirect` / `Flat` (sin `Auto`: el usuario elige explícitamente). `BackgroundImageFit`: `Cover` (default) / `Contain` / `Stretch` (imagen plana, incluido equirect sin rotación).
`BackgroundImageRotate`: Bool, default `true` (solo aplica a equirect).
Enum `BackgroundGradientType`: `LinearVertical` (0, default) / `LinearHorizontal` (1) / `Radial` (2).
Enum `BackgroundGradientRotation`: `Fixed` (0, default) / `FollowCube` (1) / `FollowCubeInverse` (2); solo el degradado.
Enum `InteriorObject`: `Off` / `Planets` / `MiniCube` / … (extensible).
Enum `CapContent`: `Color` (0, default) / `Gradient` (1) / `Image` (2).
Enum `CapGradientType`: `LinearVertical` (0, default) / `LinearHorizontal` (1) / `Radial` (2).
Enum `CapImageFit`: `Cover` (0, default) / `Contain` (1) / `Stretch` (2).
`CapOpacity` es Int 0–100 (no Double); el helper `capOpacity()` de
`constants.js` lo pasa a 0..1. Los Bool `CapTop` / `CapBottom` (default false)
habilitan cada tapa por separado.
`ModelFile` es Url (default vacío = interior sin modelo) y `ModelScale` es Double
0.05–50 (default 1.0, **multiplicador** del auto-ajuste por `bounds`): ADR-029 y
§4.1. Helpers `modelSource()` / `modelScale()` en `constants.js`.

Las claves exactas y sus defaults para el MVP están en
`package/contents/config/main.xml`. El config arranca con el del cubo virgen y
crece a medida que se implementan las features de este spec.

Existe además **Kube Effect Plus**, un **módulo nativo opcional**
(`kcm_kube_effect_plus`, «Kube Effect Plus»), compilado bajo demanda desde
`native/` (y desde `package/contents/native/` en la copia instalada). El menú QML
(`config.ui` vía `kcm_kwin4_genericscripted`) **siempre funciona solo**, sin
compilar nada; el KCM nativo añade diagnóstico, comprobación de dependencias y
`reconfigureEffect`.

## 7. Fuera de alcance (y por qué)

- **Deformación no desarrollable** (curvar el contenido sobre una superficie con
  K>0): exige shader/teselación y distorsiona el texto. Incluye cualquier forma
  que no sea un plano o un cilindro.
- **Reflexión real de ventanas**: necesita un nodo espejo con shader.
- **Framebuffer por escritorio (workspace stream)**: KWin no lo expone.
