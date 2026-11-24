# AGENTS.md — kube-effect

Cubo de escritorios para KWin, en **QML puro**. Arranca como el cubo **virgen**
de KDE y crece feature a feature. Docs en español, código en inglés.

## Qué se hace

Clon del cubo KDE con Id `kube-effect`. Un cambio por vez, verificado antes de
pasar al siguiente.

## Reglas

- Solo QML en `package/`
- **Prueba solo en KWin anidado. Nunca en sesión del host** (`scripts/kwin-nested-test.sh`).
- Código y comentarios en inglés. Docs en español.
- Todo lo comprueba `make lint`. Limpio antes de commit.
- Cada asset va con origen y licencia (cuando haya assets).
- Antes de implementar una feature, actualiza `doc/requerimientos.md`.

## Dónde va cada cosa

- `package/` — el efecto (sale a KDE Store). Solo QML.
- `doc/` — requerimientos, estado del arte y trucos aprendidos.
- `scripts/` — checks y arnés de test anidado.
- `../kdeplasma-addons/kwin/effects/cube/` — cubo oficial KDE (referencia viva).
- `../kwin-effects-cube/` — cubo C++ de zzag (referencia de geometría).
- `../kwin-effect-kkube/` — proyecto anterior (exploración con features), referencia. no copiar codigo entenderlo

## Recarga de QML (CRÍTICO)

KWin cachea el QML compilado en memoria (bug KDE #514131). `unloadEffect` +
`loadEffect` **NO recarga**; `reconfigureEffect` tampoco. Para ver cambios:
reiniciar KWin o usar el **KWin anidado** (proceso nuevo, compila desde disco).
Detalle en `doc/trucos-aprendidos.md`. esto para probarlo en host pero durante
desarrollo no se usa esto

## Arnés de test anidado

`./scripts/kwin-nested-test.sh` — KWin privado (bus propio,
`XDG_CONFIG_HOME` aislado), nunca toca la sesión real. Configura el efecto en
`[Effect-kube-effect]`, lo activa y captura. Apaga TODOS los demás efectos del
host en el anidado (menos carga); `KUBE_NESTED_KEEP_EFFECTS="blur,screenshot"`
conserva los que indiques (`screenshot` hará falta para thumbnails/wallpapers
reales). Para parar, `kill` del pid que imprime.

## Verificación

`make lint` (qmllint + qmlformat + esquema + json/yaml). Si hay SonarQube local,
`make lint` corre además el escaneo; si no, `make check` basta.

## KConfigXT

Enum = **entero** en kwinrc (`Background=0`, `Shape=2`). Strings rompen el
entorno (`GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT`). Grupo `[Effect-kube-effect]`.
Secretos: token Sonar en `.sonar-token` (600, gitignored), si se usa Sonar.
