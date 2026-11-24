# kube-effect — cubo de escritorios para KWin

Clon del cubo de escritorios de KDE (efecto KWin en **QML puro**). Arranca como
el **cubo virgen** de KDE (caras planas en polígono) y crece feature a feature.

- Id: `kube-effect`. Atajo: `Meta+K`. Licencia: GPL-2.0-or-later. Versión: 0.0.0.1.

## Qué es (estado actual)

N escritorios alrededor de un polígono (el cubo virgen de KDE), con giro por
ratón y teclado. Sobre el virgen: **casco configurable** (Color / Imagen 360 o
plana / Degradado, con sus claves en `package/contents/config/main.xml`) y un
**KCM genérico con UI dinámica** (combo de modo + páginas apiladas vía
`<connections>`, sin C++). El arnés de test anidado apaga el resto de efectos.

## Documentación

- `doc/requerimientos.md` — features, configuraciones y definiciones (cara, casco,
  fondo de escritorio, fondo de cara…).
- `doc/Estado-del-arte.md` — Compiz/Wayfire/KDE: qué hay, dónde, qué es viable.
- `doc/trucos-aprendidos.md` — trampas del pipeline (caché QML, NaN de vector3d…).

## Instalar / probar

```bash
make check                # qmllint + formato + esquema + UI + constants (sin Sonar)
make lint                 # make check + SonarQube en localhost:9000
make install              # kpackagetool6 --upgrade package/
```

**Prueba solo en KWin anidado** (`scripts/kwin-nested-test.sh`), nunca en la
sesión real. Ver `AGENTS.md`.

> Recarga de QML: KWin cachea el QML compilado (bug #514131); `unloadEffect` +
> `loadEffect` NO recarga. Hay que reiniciar KWin o usar el KWin anidado.

## Estructura

- `package/` — el efecto (sale a KDE Store). Solo QML.
- `doc/` — documentación del proyecto.
- `scripts/` — checks y arnés de test anidado.
