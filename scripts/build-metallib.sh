#!/bin/bash
# Compiles MLX generated Metal shaders to mlx.metallib and places it next to the binary.
# Must be run after `swift build -c release` so .build/checkouts/mlx-swift exists.
set -euo pipefail

WORKTREE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATED="$WORKTREE_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
OUT_DIR="$WORKTREE_DIR/.build/release"
METALLIB="$OUT_DIR/mlx.metallib"

if [ ! -d "$GENERATED" ]; then
    echo "error: mlx-generated not found at $GENERATED" >&2
    exit 1
fi

# Skip if metallib already exists and is newer than all .metal files
if [ -f "$METALLIB" ]; then
    newest_metal=$(find "$GENERATED" -name "*.metal" -newer "$METALLIB" | head -1)
    if [ -z "$newest_metal" ]; then
        echo "mlx.metallib is up to date"
        exit 0
    fi
fi

echo "Compiling MLX Metal shaders..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

AIR_FILES=()
while IFS= read -r -d '' metal_file; do
    rel="${metal_file#$GENERATED/}"
    name="${rel//\//_}"
    name="${name%.metal}"
    air_file="$TMPDIR/$name.air"
    xcrun -sdk macosx metal \
        -I "$GENERATED" \
        -target air64-apple-macosx14.0 \
        -O2 \
        -c "$metal_file" \
        -o "$air_file"
    AIR_FILES+=("$air_file")
done < <(find "$GENERATED" -name "*.metal" -print0)

echo "Linking mlx.metallib..."
xcrun -sdk macosx metallib -o "$METALLIB" "${AIR_FILES[@]}"
echo "Done: $METALLIB"
