# Estado del arte — cubos de escritorio (Compiz, Wayfire, KDE)

Documento vivo. Qué existe, dónde está el código en esta máquina, qué se
aprendió y qué se puede trasladar a un efecto KWin en QML puro.

> Regla del proyecto: se describe comportamiento, no se copia código.
> Compiz es GPL-2.0-or-later, Wayfire es MIT, KDE es GPL-2.0-or-later.

## 1. Ubicaciones en esta máquina

| Referencia               | Ruta                                     | Notas                                                                                                                                        |
| ------------------------ | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Cubo oficial KDE (vivo)  | `../kdeplasma-addons/kwin/effects/cube/` | Fuente de `DesktopView.qml`, `Cube.qml`, `ScreenView.qml`. Versión 6.8.1 copiada en `_referencias/cube-upstream-6.8.1/`                      |
| Cubo oficial KDE (copia) | `_referencias/cube-upstream-6.8.1/`      | Base del reset a "cubo virgen"                                                                                                               |
| Cubo C++ de zzag         | `../kwin-effects-cube/`                  | Referencia C++ (zzag), no QML; útil para leer la geometría                                                                                   |
| Compiz (fuente)          | `../_referencias/compiz-experimental/`   | Árbol de fuentes de Compiz. Plugins: `plugins/cube/`, `plugins/cubeaddon/`, `plugins/rotate/`, `plugins/deformation/`, `plugins/reflection/` |
| Wayfire (fuente)         | **NO clonado**                           | Clonar desde `https://github.com/WayfireWM/wayfire`, ruta `plugins/cube/` (`cube.cpp`, `cubemap.cpp`)                                        |

Si se clona Wayfire: `git clone --depth 1 https://github.com/WayfireWM/wayfire ../_referencias/wayfire`
(y quedará en `../_referencias/wayfire/plugins/cube/`).

## 2. Cómo está montado cada cubo

### Compiz (X11, arquitectura de plugins)

- `cube`: geometría del prisma, fondo (skydome/color), transparencia mientras gira.
- `rotate`: el giro (input, inercia, snap a escritorio).
- `cubeaddon`: extensiones — tapas superior/inferior (caps), unfold.
- `deformation`: deforma las caras del cubo (curvatura no desarrollable)
  **mientras giras** (teselado por shader).
- `reflection`: reflejo espejado bajo el cubo.
- `skydome`: una imagen panorámica envolvente que gira con el cubo.

Separaba _estado_ (ángulos, zoom) del _mecanismo que lo muta_ (input/IPC). Ese
patrón es el correcto y se mantiene hoy.

### Wayfire (Wayland, plugin único por-output)

- Una instancia **independiente por monitor** (`per_output_plugin_instance_t`):
  cada salida tiene su cámara y su animación.
- **Workspace stream**: cada workspace se renderiza a un framebuffer offscreen
  (fondo + ventanas + capas) y esa textura se mapea a la cara del cubo. Es el
  "fondo real por escritorio" completo.
- **Dos pasadas** (traseras → frontales) para resolver profundidad sin
  depth-buffer y permitir alfa sin artefactos de sorting.
- Modos de fondo: `simple` (color), `skydome` (entorno esférico), `cubemap`
  (6 texturas).
- La **deformación** a superficies con curvatura no desarrollable es teselado GPU
  en shader (nivel 30/50).

### KDE (KWin, efecto QML `declarativescript`)

- Cubo de caras planas: N escritorios en un polígono regular. Sin casco, sin
  deformación. Giro por ratón (drag) y teclado.
- Cada cara muestra su escritorio vía `DesktopView`/`WindowThumbnail`.
- Atajo por defecto `Meta+C` (aquí se cambia a `Meta+K`).

## 3. Qué se puede aplicar en QML puro (y qué no)

| Feature                                     | Compiz/Wayfire | ¿Viable en KWin QML? | Motivo                                                                                     |
| ------------------------------------------- | -------------- | -------------------- | ------------------------------------------------------------------------------------------ |
| Caras planas en polígono (N escritorios)    | Ambos          | **SÍ**               | Ya es el cubo base de KDE                                                                  |
| Giro por ratón + zoom por rueda             | Ambos          | **SÍ**               | `CubeCameraController`                                                                     |
| Transparencia al girar                      | Compiz         | **SÍ**               | Atenuar (opacidad) el sólido (caras) o el casco mientras se gira                           |
| Skydome (entorno envolvente)                | Ambos          | **SÍ**               | `SceneEnvironment.SkyBox` + `lightProbe` (panorámica 2:1)                                  |
| Cubemap (6 texturas)                        | Wayfire        | **SÍ (coste medio)** | Un `Texture` con `mappingMode: Environment`; 6 assets                                      |
| Caps superior/inferior (tapas)              | Compiz         | **SÍ**               | Quads horizontales en los extremos del prisma                                              |
| Unfold (desplegar a plano)                  | Compiz/Wayfire | **SÍ**               | Rotar cada cara sobre su arista al cambiar escritorio                                      |
| Reflexión de suelo (silueta)                | Compiz         | **SÍ (parcial)**     | Nodo espejado `scale.y = -1` + velo; duplica overdraw (2x)                                 |
| Zoom dedicado del cubo (≠ cámara)           | Compiz         | **SÍ**               | Escalar el nodo raíz de la forma, no la cámara                                             |
| Rotation inertia                            | Compiz         | **Parcial**          | Hay easing OutCubic; falta continuar el giro tras soltar                                   |
| Workspace stream (FBO por escritorio)       | Wayfire        | **NO**               | KWin no expone un framebuffer por workspace; solo `WindowThumbnail` por ventana            |
| Deformación de CONTENIDO (curvar pantallas) | Compiz/Wayfire | **NO (en QML puro)** | `CustomMaterial` no tesela un `#Rectangle`; deformar degrada el texto. Requiere shader/C++ |
| Reflexión REAL de ventanas                  | Compiz         | **NO (en QML puro)** | No hay nodo "espejo" de contenido sin shader                                               |
| Dos pasadas traseras→frontales              | Wayfire        | **Parcial**          | Ordenar caras a mano con `alphaMode: Blend` si hay artefactos                              |

## 4. Lecciones clave (resumen)

1. **El cubo de KDE es solo caras planas.** Todo lo demás (casco, formas,
   fondos, tapas) es añadido; hay que construirlo encima.
2. **KWin no da frames por escritorio.** Lo más cercano es capturar el
   wallpaper del escritorio actual (`desktopWindow` → `WindowThumbnail`) y
   componer las ventanas por capas (`WindowLayering`).
3. **La deformación de contenido es el techo del QML puro.** Curvar el contenido
   de las ventanas (texto nítido) exige shader con teselación → fuera del
   contrato "solo QML". Se puede simular la SILUETA (casco) pero no deformar las
   caras con texto.
4. **Separar estado de animación del input** (Wayfire/Compiz) es el patrón para
   que el giro, el zoom y el toggle no se pisen.
5. **El pipeline de KWin para efectos QML** tiene dos trampas documentadas en
   `doc/trucos-aprendidos.md`: cachea el QML (necesita KWin nuevo para recargar)
   y `SceneEnvironment.clearColor` no pinta fiablemente en modo `Offscreen`.

## 5. Fuentes

- Compiz cube: <https://www.compiz-fusion.org/wiki_subdomain/plugins/cube.html>
- Configurar el aspecto del cubo Compiz: <https://www.ghacks.net/2009/07/30/configuring-the-appearance-of-the-compiz-cube/>
- Wayfire: <https://github.com/WayfireWM/wayfire> · docs cubo <https://deepwiki.com/WayfireWM/wayfire/10.2-cube-and-3d-effects>
- Wayfire 0.9: <https://wayfire.org/2024/08/23/Wayfire-0-9.html>
- Cubo oficial KDE: <https://invent.kde.org/plasma/kwin/-/tree/master/src/effects/cube>
- QtQuick3D `CustomMaterial` (no tesela): <https://doc.qt.io/qt-6/qml-qtquick3d-custommaterial.html>
