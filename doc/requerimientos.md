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

| Escritorios | Forma                                                                                                                                      | Interior                                              |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| 1           | Con `Polygon` (default): **hoja simple**, un solo quad; giro limitado a ±80° (el dorso se vería espejado, no debe verse). Con `Cylinder`: **tambor de 3 slots con 2 vacíos** — un arco de W en el slot 0 (azimut 0), los slots 1/2 sin cara: por ahí se ve el casco; giro **libre**, sin topes (§1.2) | **No permitido** (no hay volumen)                     |
| 2           | Con `Polygon`: **hoja 2D doble cara**, un quad por escritorio, separación proporcional en z (`sheetGap`, ≥2 unidades); giro completo (cada lado es un escritorio real). Con `Cylinder`: **tambor de 3 slots con 1 vacío** — arcos en los slots 0 y 1 (azimuts 0° y 120°), el slot 2 sin cara (se ve el casco), giro **libre** sin topes, tick de selección 120° (§1.2) | **No permitido** (no hay volumen donde poner objetos) |
| 3+          | **Polígono** (default) o **Cilindro** — tambor cerrado de N arcos (elegible)                                                               | Sí                                                    |

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

| Clave             | Tipo   | Rango | Default | Requerimiento                                                       |
| ----------------- | ------ | ----- | ------- | ------------------------------------------------------------------- |
| `FaceOpacity`     | Double | 0.1–1 | 1       | Opacidad de las caras en reposo (1 = opacas, como el cubo virgen)    |
| `FaceRotationOpacity` | Double | 0.1–1 | 0.7 | Opacidad de las caras SOLO mientras gira (semitransparente)      |
| `FaceFadeMs`      | Int    | 0–1000 | 120    | Fundido entre opacidad de reposo y de giro (0 = corte seco)          |

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
  entre caras (el cubo usa materiales sin culling); es **intencionado** — es
  el look del cubo virgen de KDE, y ocultar esas caras abría agujeros por los
  que asomaba el casco en reposo (medido en el anidado 2026-11-25). El coste
  de capturas se atacará con LOD real por distancia cuando llegue
  WindowLayering (§2.1), no por orientación. Con alfa < 1 el material entra en
  el pase transparente de QtQuick3D, que ya ordena de atrás hacia delante; no
  se reordena el modelo a mano.

## 2.1 Capas de ventana (z-index / separación de ventanas)

Cada ventana de una cara puede ser su propio quad 3D, empujado hacia DENTRO del
sólido según su orden de apilado real (z-index del escritorio). Así las ventanas
solapadas se separan en profundidad y la de atrás se ve por los bordes (parallax).

| Clave                     | Tipo   | Rango    | Default | Requerimiento                                                       |
| ------------------------- | ------ | -------- | ------- | ------------------------------------------------------------------- |
| `WindowLayering`          | Bool   | —        | true    | Cada ventana como capa 3D (si false, una cara = un compuesto plano) |
| `WindowLayerGap`          | Int    | 0–600 px | 120     | Paso de profundidad entre capas (hacia dentro)                      |
| `WindowLayerLodFaces`     | Int    | 0–8      | 1       | Caras con capas (distancia al escritorio actual; 0 = todas)         |
| `WindowLayerPlateOpacity` | Double | 0–1      | 0.25    | Velo oscuro detrás de las capas (0 = sin velo)                      |

Reglas:

- Tope global del stack: **150 px**. Si no cabe, se **reparte** el paso (mismo paso
  menor para cada rango, orden preservado, sin aplanar dos capas en un plano).
- La ventana de arriba (mayor z-index) es la más cercana; las de abajo se hunden.
- Profundidad **fija** mientras gira (no se anima): el stack se lee como un sólido.
- Solo cuentan las ventanas de esa cara/escritorio/pantalla; minimizadas, docks y
  el wallpaper del escritorio se descartan.
- las ventanas ventanas podrian o no deformarse con el cilindro esto abria que verificar y ser configurable para el usuario tambien en un futuro podria tener colisiones para otros tipos de efecto

## 3. Casco (espacio alrededor) — configurable

El casco es la ZONA (el espacio que rodea al sólido). Se pinta de varias formas
(modos). **SkyBox no es un modo aparte**: es la variante de "Imagen" con una
panorámica 360.

| Modo (`Background`)        | Qué pinta                                                                                                                     | Claves reales (tipo, rango, default)                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Color** (0, default)         | Un color sólido                                                                                                               | `Background` Enum; `BackgroundColor` Color, default `#1b3fd8`                                                                     |
| **Image** (1)                  | Imagen de fondo. Si el mapeo resuelve equirect **y** gira con el centro es **SkyBox** (entorno 360); si no, capa plana fullscreen estática | `SkyBox` Url (vacío = sin imagen); `BackgroundImageLayout` Enum (ver abajo); `BackgroundImageRotate` Bool default true; `BackgroundColor` actúa de color de respaldo |
| **Gradient** (2)               | Degradado de dos colores sin shaders (Rectangle + Gradient QML). Tipos: vertical (arriba→abajo), horizontal, radial (real con Shapes; **opcional**: sin el módulo cae al lineal y avisa una vez) | `Background` Enum; `BackgroundGradientType` Enum (ver abajo); `BackgroundColor` Color `#1b3fd8`; `BackgroundColor2` Color `#ff8a00`; `BackgroundGradientStop` Int 0–100, default 50 (posición del corte: 0 = todo color2 salvo borde, 100 = transición hasta el final) |
| **Video** (3)                  | **Vídeo** de fondo, igual que una imagen con otra fuente: equirect **y** girando = panorama 360 animado en una cúpula (ADR-020); Flat **o** sin girar = capa plana fullscreen con el ajuste. Requiere el módulo opcional QtMultimedia; sin él se pinta `BackgroundColor` y se avisa una vez | `BackgroundVideo` Url (vacío = sin vídeo; solo `file:`); `BackgroundImageLayout` / `BackgroundImageFit` / `BackgroundImageRotate` (compartidas con la imagen); `BackgroundColor` de respaldo |
| (arena, futuro)                | Atenuación global del casco (0 = sin atenuar, 1 = negro)                                                                      | (sin clave aún) `CascoDim` reservado                                                                                              |

- `BackgroundColor` (#1b3fd8 azul) y `BackgroundColor2` (#ff8a00 naranja) son los
  defaults **nuevos** de `main.xml`, elegidos para que el degradado se note de un
  vistazo.
- Enum `BackgroundImageLayout`: `Equirect` (forzar 360) / `Flat` (forzar plano). Ya no existe `Auto`: el usuario elige explícitamente si la imagen es panorámica o plana. La **clave** se renombró a propósito (antes `BackgroundImageMapping`): kwinrc guarda el índice, así que un valor viejo queda huérfano y se ignora en vez de reinterpretarse como `Flat`.
- `BackgroundImageFit` (Enum, default `Cover`): `Cover` / `Contain` / `Stretch`. Solo aplica a lo que va plano (imagen plana, equirect sin rotación, y el vídeo plano); decide cómo encaja en pantalla.
- `BackgroundImageRotate` (Bool, default `true`): solo aplica al mapeo equirect. `true` = entorno 360 que gira con el centro (SkyBox); `false` = capa plana estática fullscreen que no rota al mover la cámara. Compartida por imagen y vídeo.
- **Vídeo** (`Background=Video`, índice 3): el vídeo se trata **exactamente como una imagen** con otra fuente. `BackgroundVideo` es un Url local (`file:`; una URL de red se ignora) y el mapeo/ajuste/giro son las mismas tres claves de la imagen, en un grupo compartido del KCM («Imagen o vídeo: cómo se muestra»). Reproduce en bucle, sin sonido y **solo con el efecto visible** (pausa al desactivar, reanuda al activar). En la variante 360 el `BackgroundImageFit` **no aplica**: el `VideoOutput` fuerza el fotograma completo (Stretch) porque la esfera es la que envuelve; el ajuste solo manda en la capa plana. Atenuación al girar: velo 2D si va plano, esfera-velo negra si va como 360 (el entorno no puede muestrear un `VideoOutput`: ADR-020). **Dependencia opcional** `QtMultimedia`: si el módulo no está instalado, el vídeo se sustituye por `BackgroundColor` y el efecto sigue funcionando (ver §5.1).
- Solo se aceptan recursos **locales**: la imagen admite `file:` o `image:`, el vídeo (`BackgroundVideo`) solo `file:`; una URL de red se ignora en ambos casos (el compositor no descarga contenido al activar el efecto).
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

## 5. Activación y comportamiento

| Clave                  | Tipo   | Rango       | Default | Requerimiento                                                                                                |
| ---------------------- | ------ | ----------- | ------- | ------------------------------------------------------------------------------------------------------------ |
| `BorderActivate`       | String | "1,7"       | vacío   | Bordes de pantalla (puntero) que activan el sólido (1=Arriba…8=ArribaIzq)                                    |
| `TouchBorderActivate`  | String | "5"         | vacío   | Igual, con toque                                                                                             |
| `MouseInvertedX`       | Bool   | —           | false   | Invertir eje X del arrastre                                                                                  |
| `MouseInvertedY`       | Bool   | —           | false   | Invertir eje Y del arrastre                                                                                  |
| `CursorScreenOnly`     | Bool   | —           | false   | Dibuja el cubo solo en el monitor donde está el cursor al lanzarse; el resto de pantallas quedan normales. Sustituye al antiguo «casco por pantalla»; default `false` = todas las pantallas |
| `CubeFaceDisplacement` | Double | −500…500 px | 100     | Separación entre caras. 0 = caras pegadas; **negativo = se solapan** (el polígono encoge); positivo = huecos. **En cilindro (todos los counts, tambor y tambor de tres slots) es el hueco lineal entre arcos: los valores negativos se tratan como 0** (ADR-025/ADR-026 — g también rige R = 3(W+g)/2π con 1-2). La hoja plana (Polygon 1-2) no lo usa (su separación es `sheetGap`) |
| `DistanceFactor`       | Double | 0.5–5       | 1.75    | Distancia de la cámara al activar                                                                            |

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

| Clave                    | Tipo | Rango | Default | Requerimiento                                                              |
| ------------------------ | ---- | ----- | ------- | -------------------------------------------------------------------------- |
| `DimWhileRotating`       | Bool | —     | false   | Oscurece el fondo SOLO mientras el cubo gira; vuelve al soltar             |
| `DimWhileRotatingAmount` | Int  | 0–100 | 40      | Cuánto se oscurece el fondo al girar (solo con `DimWhileRotating`)        |
| `CursorScreenOnly`       | Bool | —     | false   | Cubo solo en el monitor del cursor al lanzarse; default `false` = todas las pantallas |
| `DebugOverlay`           | Bool | —     | false   | Muestra estado interno del efecto en pantalla (diagnóstico)                            |

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
