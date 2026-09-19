#!/bin/bash
# Builds whisper.cpp as static libraries with Metal, into Vendor/whisper/{include,lib}.
# Run once before `swift build`; scripts/build.sh calls it when the libraries are missing.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${WHISPER_TAG:-v1.9.4}"
SRC=build/whisper.cpp
OUT=Vendor/whisper
if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 --branch "$TAG" https://github.com/ggml-org/whisper.cpp "$SRC"
fi
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 >/dev/null
cmake --build "$SRC/build" --config Release -j "$(sysctl -n hw.ncpu)" 2>&1 | grep -E 'error|Linking|Built target' | tail -8
mkdir -p "$OUT/include" "$OUT/lib"
find "$SRC/build" -name '*.a' -exec cp {} "$OUT/lib/" \;
cp "$SRC/include/whisper.h" "$SRC/ggml/include/ggml.h" "$SRC/ggml/include/ggml-cpu.h" "$SRC/ggml/include/ggml-backend.h" "$SRC/ggml/include/ggml-alloc.h" "$OUT/include/" 2>/dev/null || true
echo "whisper $TAG built:"; ls "$OUT/lib"
