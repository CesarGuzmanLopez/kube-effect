# Trucos aprendidos — qué NO funciona y qué SÍ

Bitácora de trampas del pipeline real (KWin 6 + Qt 6.12 + QtQuick3D, QML
`declarativescript`). Cada punto se verificó en la sesión real o en el KWin
anidado. Si algo aquí contradice un tutorial, gana esta lista: son hechos
medidos en ESTA máquina.

## A. Recarga de código (el que más tiempo costó)

### ❌ FALSO: `unloadEffect` + `loadEffect` recarga el QML

No. KWin cachea el QML compilado **en memoria por URL** (bug KDE #514131,
CONFIRMADO). Reinstalar el paquete y recargar deja corriendo la versión VIEJA.
Lo medimos: cambiar `animationDuration` a 777 y seguir viendo 400 tras recargar.

### ❌ FALSO: `reconfigureEffect` recarga el QML

No. Solo re-lee la CONFIG, no recompila QML.

### ❌ FALSO: borrar `~/.cache/kwin/qmlcache/*.qmlc`

No sirve. El caché que manda es el **en memoria** del `QQmlEngine`, no el disco.

### ✅ VERDADERO: reiniciar KWin, o usar un KWin anidado

- Recarga real: `systemctl --user restart plasma-kwin_wayland.service` (cierra y
  reabre ventanas, ~10 s; no cierra sesión). O cerrar/iniciar sesión.
- **Mejor para desarrollar**: KWin anidado (`scripts/kwin-nested-test.sh`), que es
  un proceso NUEVO → compila desde disco. Aislado (bus privado, `XDG_CONFIG_HOME`

### ✅ VERDADERO: `window.color` para el fondo plano (Color/Black)

Como el cubo upstream: `Binding { target: Window.window; property: "color";
value: flatClearColor }` (opaco, alpha 1) + `SceneEnvironment.Transparent`.
La ventana pinta el color y la escena transparente deja verlo detrás del cubo.
Para los modos con textura (SkyBox/vídeo/wallpaper) la ventana va transparente y
el fondo se pinta DENTRO de la escena.

## C. Animaciones de `vector3d` (el flood de NaN)

### ❌ FALSO: `NumberAnimation on scale` / `on position` / `on eulerRotation`

Un `NumberAnimation` anima un `real`; si el destino es un `vector3d` escribe UN
solo double y Qt llena el journal con
`Could not find any constructor for value type QQuickVector3DValueType ...
QVariant(double, nan/0)` (~200/s), corrompiendo la escena.

### ❌ FALSO: `Vector3dAnimation` en un `Behavior on scale` o `SequentialAnimation on scale`

En esta versión también produjo NaN (el patrón value-source sobre `scale` con
varios consumidores choca).

### ✅ VERDADERO: animar un ESCALAR y derivar el vector

```qml
property real pulse: 1.6
scale: Qt.vector3d(pulse, pulse, pulse)
SequentialAnimation on pulse { NumberAnimation { from: 1.5; to: 1.7; ... } }
```

Lo mismo para rotación: `property real orbit; eulerRotation: Qt.vector3d(tilt, orbit, 0)`
con `NumberAnimation on orbit`. Nunca animar `scale`/`eulerRotation`/`position`
directamente.

## D. Diagnóstico en caliente

### ❌ FALSO: `console.log` / `console.warn` desde QML

En este KWin NO llegan al journal (ni `journalctl -b` ni `--user`). Inútil para
depurar en caliente.

### ✅ VERDADERO: exponer propiedades y leerlas por D-Bus

Añadir `readonly property string dbgX: ...` al `SceneEffect` (main.qml) y leer:

```
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.supportInformation kube-effect
```

Muestra el valor vivo (incluye `activated`, `visible`). Sirve para confirmar qué
versión está cargada (`animationDuration`) y qué config resuelve.

## E. Geometría y culling (QtQuick3D)

- La cámara mira hacia **-Z**. Un quad hijo de la cámara a `z = -d` muestra su
  cara **trasera** → con `BackFaceCulling` desaparece. Usar `Material.NoCulling`
  para quads colgados de la cámara.
- Hoja 2D (2 escritorios): doble cara; un quad `NoCulling` (o dos quads) para
  verla por delante y por detrás.
- **Cilindro sin shader**: el cilindro es desarrollable (K=0), así que curvar el
  escritorio sobre él es isométrico (no estira). Se construye con
  `ProceduralMesh` (`import QtQuick3D.Helpers`): posiciones `(R·sin φ, t, R·cos φ)`
  con `φ = s/R`, UV `u = s/W`, `v = t/H`, y `θ = W/R`. Material estándar
  (`PrincipledMaterial.NoLighting` + `baseColorMap`) — **sin vertex shader**.
  El primitivo `#Cylinder` NO sirve (cilindro completo, UV propias, no un arco).
- Curvar el contenido sobre una superficie **no desarrollable** (K>0) SÍ estira →
  exige shader/teselado → fuera de alcance.

## G. KConfigXT y formato

- **Enum = ENTERO en kwinrc** (p. ej. `Background=0`). Un string rompe el
  entorno (`GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`). Grupo `[Effect-kube-effect]`.
- `make check` compara con el ÍNDICE: ejecutar `qmlformat -i`, luego `git add -A`,
  luego `make check` (si no, el `git diff` da "falso rojo").
- El KCM genérico (`kcm_kwin4_genericscripted`) auto-genera el formulario desde
  `main.xml`; no hace falta `config.ui` para el cubo virgen.

## H. Flujo de prueba recomendado

1. Editar QML.
2. `./scripts/kwin-nested-test.sh` (KWin anidado aislado, nunca tu sesión).
3. Verificar el cubo en la ventana WL-0 (Meta+K ahí, o `toggleEffect` por D-Bus).
4. Iterar. NUNCA reiniciar la sesión real del usuario para probar.
