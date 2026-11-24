# ADR — decisiones de diseño (Kube Effect)

Registro de decisiones tomadas en el grill de alcance. Cada una con su porqué.
No reabrir sin motivo; si cambia, se añade un ADR nuevo que la sustituye.

## ADR-001 — Solo dos formas: polígono y cilindro.

**Decisión**: el efecto sólo ofrece **polígono** (N caras planas en N-gono) y
**cilindro** (las mismas caras curvadas). No hay una tercera forma.
**Porqué**: polígono y cilindro son topológicamente el mismo sólido (un prisma
N-gonal); el cilindro es una superficie **desarrollable** (K=0), así que curvar el
contenido es isométrico (sin distorsión). Una forma con curvatura positiva (K>0)
exige deformar el contenido (Theorema Egregium) → shader/teselado y texto
deformado → fuera del contrato "solo QML".

## ADR-002 — Cilindro isométrico con ProceduralMesh, sin shader.

**Decisión**: el cilindro se construye con `ProceduralMesh` (QML puro):
`P(s,t) = (R·sin φ, t, R·cos φ)`, `φ = s/R`, UV `u = s/W`, `v = t/H`, con
`θ = W/R`. Material estándar (`PrincipledMaterial.NoLighting` + `baseColorMap`).
**Porqué**: el mapeo plano→cilindro es isométrico (no estira); no hace falta
vertex shader. El primitivo `#Cylinder` no sirve (cilindro completo, UV propias,
no un arco). 32–64 segmentos bastan (66–130 vértices).

## ADR-003 — Sin piel: el sólido son sólo caras; el "casco" es el espacio tambien llamado skybox

**Decisión**: no hay superficie/piel entre caras. El sólido = caras (una por
escritorio). **Casco** = el **espacio alrededor** - sky - cielo (fondo/entorno), no la superficie
del sólido.
**Porqué**: separar conceptos evita la ambigüedad El cubo KDE es sólo caras; entre ellas se ve el fondo.

## ADR-004 — Fondo de cara = wallpaper REAL del escritorio

    esto debe deformar el escritorio y usarlo esto es importante para que se sigan usando el fondo real del usuario como pared del cubasi esta sea animada o video hay que verificar como hacer esto de forma optima sobre todo buscar como funciona wayland y wayfire como lo hace si es necesario

## ADR-005 — Reglas por número de escritorios.

**Decisión**: 1 y 2 → **hoja 2D doble cara** (un
escritorio por delante, otro por detrás), sin interior; 3+ → polígono (default) o
cilindro (elegible).
**Porqué**: polígono y cilindro necesitan 3+ caras. Con 2 sólo cabe una hoja; con
1 no hay sólido.

## ADR-006 — Casco configurable (todas las opciones).

**Decisión**: `CascoMode` = Color (default) / Gradient (lineal/radial/circular) /
Video (360) / Image (fija o girando con el centro) hay que mantener estatico el fondo o puede ser jirable , más `CascoDim`.
**Porqué**: el usuario quiere un casco rico, no limitado a dos fondos.

## ADR-007 — Interior = objetos decorativos 3D/2D.

**Decisión**: objetos dentro del sólido: 3D animado (planetas), 3D estático
(quieto al girar), vídeo, imagen 2D. Arranque: planetas + mini-cubo. Sólo con 3+
escritorios (con 2, hoja 2D, deshabilitado).
**Porqué**: "lo que puede ir dentro" del cubo es parte del ámbito; el sistema debe
cubrir los tipos, aunque se empiece con dos.

## ADR-008 — Capas de ventana (z-index) hacia dentro, tope 150 px.

**Decisión**: cada ventana = quad propio empujado hacia fuera del solido según su orden de
apilado; tope del stack 150 px con paso repartido (`fittedGap`);
esto es actibable y configurable el usuario puede decir cuanta separacion hay entre ventanas y si 2 ventanas estan abiertas pero no estan una sobre la otra entonces pertenecen al mismo z index pero si una esta sobre otra la que esta alado comparte z index con el que esta mas abajo asi da un efecto de apilado sincronizado

## ADR-009 — Recargar QML: reiniciar KWin o anidado.

**Decisión**: los cambios de QML se prueban en un KWin anidado (proceso nuevo) o
reiniciando KWin; nunca con `unloadEffect`+`loadEffect` sobre la sesión real.
**Porqué**: KWin cachea el QML compilado en memoria (bug #514131); recargar no
recompila.

## ADR-010 — Animar escalares, derivar vectores.

**Decisión**: nunca animar `scale`/`position`/`eulerRotation` directamente; animar
un `real` (pulso/órbita) y derivar el `vector3d`.
**Porqué**: animar un vector3d escribe un solo double y llena el journal de
`QVariant(double, nan/0)`, corrompiendo la escena.
