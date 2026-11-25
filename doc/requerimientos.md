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

| Escritorios | Forma                                                                            | Interior                                              |
| ----------- | -------------------------------------------------------------------------------- | ----------------------------------------------------- |
| 1           | Placeholder: pide añadir hasta tener 3 (no hay sólido)                           | —                                                     |
| 2           | **Hoja 2D doble cara**: un escritorio por delante y otro por detrás; sin volumen | **No permitido** (no hay volumen donde poner objetos) |
| 3+          | **Polígono** (default) o **Cilindro** (elegible)                                 | Sí                                                    |

### 1.1 Polígono (default)

- N caras planas (una por escritorio) en el perímetro de un N-gono regular.
- No deforma nada: las caras son planas; se ven las aristas entre caras.
- N = número de escritorios (3 = triángulo, 4 = cubo, 5 = pentágono…).

### 1.2 Cilindro

- Las MISMAS caras, pero curvadas sobre un cilindro. Mapeo **isométrico**: el
  cilindro es una superficie **desarrollable** (curvatura gaussiana K=0), así que
  un plano se envuelve sobre él **sin distorsión** (una recta se vuelve arco de
  igual longitud; el contenido no se estira).
- Implementación: malla curva generada en QML (`ProceduralMesh`, ver
  `doc/ARQUITECTURA.md`); UVs con `θ = W/R` y `u = s/W`. **Sin vertex shader.**
- N ≥ 3 (el mínimo lo fija la forma; con 2 solo cabe la hoja 2D).
- Relación arco↔textura: `arco = R·θ` debe igualar el ancho de la cara; si no, la
  textura se estira o comprime.

### 1.3 Hoja 2D (2 escritorios)

- Una sola hoja plana, **doble cara**: un escritorio por delante, otro por detrás.
- Sin interior (no hay volumen). El casco se sigue viendo alrededor.

## 2. Sólido: caras

- Cada cara = captura del **wallpaper real** de su escritorio (QML, sin shader)
    - las ventanas de ese escritorio.
- Sin piel/superficie entre caras.
- Sin espejo ni reflexión de contenido (exigirían shader; fuera).

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
| **Gradient** (2)               | Degradado de dos colores sin shaders (Rectangle + Gradient QML). Tipos: vertical (arriba→abajo), horizontal, radial (real, con Shapes) | `Background` Enum; `BackgroundGradientType` Enum (ver abajo); `BackgroundColor` Color `#1b3fd8`; `BackgroundColor2` Color `#ff8a00`; `BackgroundGradientStop` Int 0–100, default 50 (posición del corte: 0 = todo color2 salvo borde, 100 = transición hasta el final) |
| **Video** (3)                  | **Vídeo** de fondo, igual que una imagen con otra fuente: equirect **y** girando = panorama 360 animado en una cúpula (ADR-020); Flat **o** sin girar = capa plana fullscreen con el ajuste. Requiere el módulo opcional QtMultimedia; sin él se pinta `BackgroundColor` y se avisa una vez | `BackgroundVideo` Url (vacío = sin vídeo; solo `file:`); `BackgroundImageLayout` / `BackgroundImageFit` / `BackgroundImageRotate` (compartidas con la imagen); `BackgroundColor` de respaldo |
| (arena, futuro)                | Atenuación global del casco (0 = sin atenuar, 1 = negro)                                                                      | (sin clave aún) `CascoDim` reservado                                                                                              |

- `BackgroundColor` (#1b3fd8 azul) y `BackgroundColor2` (#ff8a00 naranja) son los
  defaults **nuevos** de `main.xml`, elegidos para que el degradado se note de un
  vistazo.
- Enum `BackgroundImageLayout`: `Equirect` (forzar 360) / `Flat` (forzar plano). Ya no existe `Auto`: el usuario elige explícitamente si la imagen es panorámica o plana. La **clave** se renombró a propósito (antes `BackgroundImageMapping`): kwinrc guarda el índice, así que un valor viejo queda huérfano y se ignora en vez de reinterpretarse como `Flat`.
- `BackgroundImageFit` (Enum, default `Cover`): `Cover` / `Contain` / `Stretch`. Solo aplica a lo que va plano (imagen plana, equirect sin rotación, y el vídeo plano); decide cómo encaja en pantalla.
- `BackgroundImageRotate` (Bool, default `true`): solo aplica al mapeo equirect. `true` = entorno 360 que gira con el centro (SkyBox); `false` = capa plana estática fullscreen que no rota al mover la cámara. Compartida por imagen y vídeo.
- **Vídeo** (`Background=Video`, índice 3): el vídeo se trata **exactamente como una imagen** con otra fuente. `BackgroundVideo` es un Url local (`file:`; una URL de red se ignora) y el mapeo/ajuste/giro son las mismas tres claves de la imagen, en un grupo compartido del KCM («Imagen o vídeo: cómo se muestra»). Reproduce en bucle, sin sonido y **solo con el efecto visible** (pausa al desactivar, reanuda al activar). Atenuación al girar: velo 2D si va plano, esfera-velo negra si va como 360 (el entorno no puede muestrear un `VideoOutput`: ADR-020). **Dependencia opcional** `QtMultimedia`: si el módulo no está instalado, el vídeo se sustituye por `BackgroundColor` y el efecto sigue funcionando (ver §5.1).
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
| `CubeFaceDisplacement` | Double | −500…500 px | 100     | Separación entre caras. 0 = caras pegadas; **negativo = se solapan** (el polígono encoge); positivo = huecos |
| `DistanceFactor`       | Double | 0.5–5       | 1.75    | Distancia de la cámara al activar                                                                            |

- Atajo por defecto: **Meta+K**. Se registra con `ShortcutHandler` → **KGlobalAccel**, y se
  cambia en **Preferencias del sistema → Atajos de teclado → KWin → «Toggle Kube Effect»**
  (estándar KDE). No se duplica en el KCM del efecto a propósito: `KGlobalAccel` guarda el
  valor en `kglobalshortcutsrc` y ese valor **pisa** al `sequence` del QML, así que una clave
  en `main.xml` sería una segunda fuente que nunca manda. El KCM solo muestra un aviso.
- Giro por arrastre del ratón y teclado; zoom por rueda.

## 5.1 Advanced (opciones avanzadas)

Estas claves viven SOLO aquí; no se reparten por otras pestañas. **Advanced es el
único sitio para opciones avanzadas.**

| Clave                    | Tipo | Rango | Default | Requerimiento                                                              |
| ------------------------ | ---- | ----- | ------- | -------------------------------------------------------------------------- |
| `DimWhileRotating`       | Bool | —     | false   | Oscurece el fondo SOLO mientras el cubo gira; vuelve al soltar             |
| `DimWhileRotatingAmount` | Int  | 0–100 | 40      | Cuánto se oscurece el fondo al girar (solo con `DimWhileRotating`)        |
| `CursorScreenOnly`       | Bool | —     | false   | Cubo solo en el monitor del cursor al lanzarse; default `false` = todas las pantallas |

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
  ese botón. La pestaña Advanced del menú QML agrupa las tres claves avanzadas y una
  sección plegable que remite a Plus; no duplica las opciones del nativo.

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

Enum `Shape`: `Polygon` (default) / `Cylinder`. El número de escritorios manda:
1 → placeholder; 2 → hoja 2D; 3+ → forma elegida.

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
