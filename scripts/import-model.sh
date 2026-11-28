#!/usr/bin/env bash
# Convierte un modelo (glTF/GLB/OBJ/FBX/DAE) a .mesh para Kube Effect.
# Opcional: Kube Effect carga glTF/GLB/OBJ en runtime con RuntimeLoader si el plugin
# importador de Qt está operativo (paquete assimp). Convertir a .mesh antes
# evita depender de ese plugin y es más rápido en cada frame.
# Uso: scripts/import-model.sh modelo.glb [destino/]
set -u
[ $# -ge 1 ] || {
  echo "Uso: $0 <modelo.glb|.gltf|.obj|.fbx|.dae> [destino/]"
  exit 2
}
SRC=$1
OUT=${2:-$HOME/.local/share/kube-effect/models}
[ -f "$SRC" ] || {
  echo "ERROR: no existe $SRC"
  exit 1
}
mkdir -p "$OUT"
BALSAM=$(command -v balsam || echo /usr/lib/qt6/bin/balsam)
[ -x "$BALSAM" ] || {
  echo "ERROR: falta balsam (paquete qt6-quick3d)"
  exit 1
}
if ! ldconfig -p | grep -q "libassimp.so.6"; then
  echo "AVISO: falta el paquete 'assimp' (libassimp.so.6); sin él balsam no"
  echo "       reconoce glTF/OBJ. Instálalo con: sudo pacman -S assimp"
fi
"$BALSAM" "$SRC" -o "$OUT" || {
  echo "ERROR: balsam no pudo convertir $SRC"
  exit 1
}
# balsam genera <Destino>/<Nombre>.qml + <Destino>/meshes/*.mesh
MESH=$(find "$OUT" -name "*.mesh" -print 2>/dev/null | head -1)
[ -n "$MESH" ] || {
  echo "ERROR: balsam no generó ningún .mesh en $OUT"
  exit 1
}
echo "mesh=$MESH"
find "$OUT" -maxdepth 2 -type d -name meshes -print -quit
echo "Pégalo en Ajustes > Efectos de escritorio > Kube Effect > Model file"
