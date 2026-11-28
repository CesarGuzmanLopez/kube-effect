# kube-effect — cubo de escritorios para KWin

Clon del cubo de escritorios de KDE (efecto KWin en **QML puro**). Arranca como
el **cubo virgen** de KDE (caras planas en polígono) y crece feature a feature.

- Id: `kube-effect`. Atajo: `Meta+K`. Licencia: GPL-2.0-or-later. Versión: 0.0.0.6.

## Qué es (estado actual)

N escritorios alrededor de un **polígono** (el cubo virgen de KDE) o de un
**cilindro** — las mismas caras curvadas sobre arcos isométricos sin distorsión
(`Shape = Cylinder`, ADR-025; 64 segmentos por cara, una sola malla compartida).
Con 1-2 escritorios y Polygon la forma es **hoja 2D** (ADR-024: doble cara con
2 (giro completo), simple con 1 (giro limitado a ±80°; el dorso se vería
espejado)); con Cylinder el sólido es un **tambor de tres posiciones con las
que faltan vacías** — R = 3(W+g)/2π con el hueco g, caras en 0° y 120°, giro
libre sin topes, la pared interior se ve como en el polígono (ADR-025 pt.11
re-rectificado + ADR-026; los topes de banda [-60°,60°]/[-60°,180°] se
probaron y retiraron). Sobre el sólido pueden cerrarlo arriba y abajo las
**tapas** (`CapTop`/`CapBottom`, ADR-027: N-gono inscrito o disco según la
forma, con color/degradado/imagen local propios y opacidad; deshabilitadas por
código en la hoja 2D). Sobre
el virgen: **casco configurable** (Color / Imagen / Degradado / **Vídeo**, con sus
claves en `package/contents/config/main.xml`) y un **KCM genérico con UI
dinámica** (combo de modo + páginas apiladas vía `<connections>`, sin C++). El
arnés de test anidado apaga el resto de efectos.

La imagen y el **vídeo** comparten mapeo (equirect 360 o plano), ajuste y giro: el
vídeo puede envolver la escena como skydome animado o quedarse fijo como una foto.
El vídeo usa `QtMultimedia`, una **dependencia opcional** (`qt6-multimedia` en Arch,
pestaña Advanced → «Vídeo de fondo (opcional)»): si no está instalada, el fondo de
vídeo se sustituye por el color de respaldo y el resto del efecto sigue igual.

## Documentación

- `doc/requerimientos.md` — features, configuraciones y definiciones (cara, casco,
  fondo de escritorio, fondo de cara…).
- `doc/Estado-del-arte.md` — Compiz/Wayfire/KDE: qué hay, dónde, qué es viable.
- `doc/trucos-aprendidos.md` — trampas del pipeline (caché QML, NaN de vector3d…).

## Instalar / probar

```bash
make check                # qmllint + formato + esquema + UI + geometría (7 s, sin Sonar)
make lint                 # make check + SonarQube en localhost:9000
make install              # kpackagetool6 --upgrade package/
```

**Prueba solo en KWin anidado** (`scripts/kwin-nested-test.sh`), nunca en la
sesión real. Ver `AGENTS.md`.

> Recarga de QML: KWin cachea el QML compilado (bug #514131); `unloadEffect` +
> `loadEffect` NO recarga. Ver **«Aplicar cambios»** abajo.

## Modelo híbrido

> El KCM compilado es **Preferencias → Gestión de ventanas → «Kube Effect Plus»**.
> Solo aparece ahí si está instalado en el sistema (`make native-install`). Con el prefijo
> privado (`make native`) hay que abrir Preferencias con `prefix.sh`, porque System Settings
> busca los módulos en los _Qt plugin paths_: `~/.local/lib/plugins` no se escanea solo.
> (nativo opcional)

Sin compilar nada, el efecto es completo en QML (menú de configuración incluido:
`config.ui` vía el KCM genérico `kcm_kwin4_genericscripted`). Compilar
`native/` añade **Kube Effect Plus**, un **módulo nativo opcional**
(`kcm_kube_effect_plus`, «Kube Effect Plus») con diagnóstico, comprobación de
dependencias y dos acciones:
**«Reconfigurar efecto»** (aplica ajustes) y **«Recargar compositor»** (aplica
cambios de código). El QML no depende del nativo: si el `.so` falta o es
incompatible, el cubo sigue intacto.

Pasos, de menos a más:

1. `make native` — compila e instala `native/` en `~/.local` (sin root) y escribe
   `~/.local/share/kube-effect/{native-stamp.json,prefix.sh}`. Es la forma de probar
   sin tocar el sistema: el KCM se abre con `prefix.sh` + `kcmshell6` /
   `systemsettings`, **no** desde Preferencias.
2. `make native-install` — instalación de sistema en `/usr`
   (`/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kube_effect_plus.so`). Aquí sí
   aparece en **Preferencias → Gestión de ventanas → «Kube Effect Plus»**.
   El target compila como tu usuario y solo invoca `sudo` en el paso final de
   instalación (pide la contraseña una vez, no deja artefactos de root en el
   árbol de build). No hace falta poner `sudo` delante de `make`.
3. `make native-status` — compara el stamp con el Plasma/Qt instalados (exit 1 si
   falta o está viejo). `make native-clean` borra los árboles de build.

El paquete distribuible incluye las **fuentes** de Plus en
`package/contents/native/` (copia de `native/`, sin árboles de build): `native/`
sigue siendo la fuente de verdad y `make sync-package-native` las mantiene
iguales (`make check` falla si divergen; `make install` sincroniza antes de
instalar). Así el usuario que instala desde KDE Store puede compilar sin el
repositorio:

```bash
cd ~/.local/share/kwin/effects/kube-effect/contents/native
./build.sh            # solo para tu usuario
./build.sh --system   # aparece en Preferencias (pide contraseña)
```

El propio KCM trae una sección **«Comandos»** con ese bloque listo para copiar
(botón «Copiar comandos»), usando la ruta guardada en el stamp (`source`: raíz
del repo o carpeta `contents/native` de la copia instalada); si el stamp es
viejo y no la tiene, imprime una ruta de ejemplo y avisa de que hay que
ajustarla.

`make native-status` compara el stamp con el Plasma/Qt instalados (exit 1 si falta
o está viejo) y el arnés lo respeta: sin flag compila siempre antes de arrancar.

El arnés puede lanzarse en modo **sin compilar** (`--no-native`): no ejecuta
`make native`, no sourcea `prefix.sh` ni abre el KCM. Sirve para comprobar que el
efecto QML funciona completo sin el lado nativo, y para ver la diferencia con el
anidado compilado:

```bash
./scripts/kwin-nested-test.sh --no-native   # experiencia sin compilar
./scripts/kwin-nested-test.sh --help        # opciones (incl. KUBE_NESTED_KEEP_EFFECTS)
```

Tras `make native`, para ver el KCM fuera de System Settings:

```bash
source ~/.local/share/kube-effect/prefix.sh && kcmshell6 kcm_kube_effect_plus
```

## Aplicar cambios (sin saber de KWin)

KWin guarda el QML compilado **en memoria**, así que reinstalar el efecto solo
cambia los ficheros: pulsar «Reconfigurar efecto» aplica **ajustes**, no
**código**. Para ver el código nuevo:

- Con Kube Effect Plus (`make native`): Preferencias del sistema → «Kube Effect
  Plus» → **«Recargar compositor»**. Pide confirmación, cierra y reabre las
  ventanas (~10 s) y no cierra la sesión. Por dentro es
  `systemctl --user restart plasma-kwin_wayland.service`.
- Sin compilar nada: cierra sesión y vuelve a entrar.
- Mientras desarrollas: `./scripts/kwin-nested-test.sh` levanta un compositor
  aparte (proceso nuevo, lee el código de disco). Ahí «Recargar compositor» se
  niega a propósito: el compositor es del script, se para cerrándolo y se vuelve
  a lanzar para recargar.

## Estructura

- `package/` — el efecto (sale a KDE Store). Solo QML, más
  `package/contents/native/` (copia de las fuentes de Plus; KWin no la carga).
- `native/` — fuentes de Kube Effect Plus (fuente de verdad).
- `doc/` — documentación del proyecto.
- `scripts/` — checks y arnés de test anidado.
