#!/usr/bin/env bash
# scripts/build-ffmpeg-macos.sh
#
# Builds an LGPL-only, libass-enabled FFmpeg for macOS that runs on a clean Mac (system frameworks
# only). Conforms to docs/adr/0012-ffmpeg-binary-sourcing.md.
#
#   Apple Silicon (arm64):  ./scripts/build-ffmpeg-macos.sh            -> bin/mac-arm64/ffmpeg
#   Intel (x64), on an Intel Mac or Intel CI runner:
#                           ./scripts/build-ffmpeg-macos.sh            -> bin/mac-x64/ffmpeg
#   Intel (x64), on an Apple Silicon Mac (builds natively under Rosetta 2, no cross-compiling):
#                           arch -x86_64 /bin/bash scripts/build-ffmpeg-macos.sh
#       one-time prerequisite: an Intel Homebrew in /usr/local
#         arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#
# Prerequisites (per architecture, from that architecture's Homebrew):  brew install pkg-config nasm libass lame
#
# Environment:  FFMPEG_VERSION (default from scripts/ffmpeg-checksums.json), UPDATE_CHECKSUMS=1 to record
# the source tarball's SHA-256 (do this once on a trusted machine and commit). CI=true refuses an
# unrecorded checksum.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_ARCH="$(uname -m)"           # arm64 | x86_64 (x86_64 also under Rosetta via `arch -x86_64`)
case "${HOST_ARCH}" in
  arm64)  ELECTRON_ARCH="arm64" ;;
  x86_64) ELECTRON_ARCH="x64" ;;
  *) echo "Unsupported architecture: ${HOST_ARCH}" >&2; exit 1 ;;
esac

OUTPUT_DIR="${REPO_ROOT}/bin/mac-${ELECTRON_ARCH}"      # matches electron-builder's bin/${os}-${arch}
BUILD_ROOT="${TMPDIR:-/tmp}/gma-ffmpeg-build-${ELECTRON_ARCH}"

CHECKSUMS="${SCRIPT_DIR}/ffmpeg-checksums.json"
read_manifest() { node -e "const m=require('${CHECKSUMS}');console.log(m.source.$1||'')"; }
FFMPEG_VERSION="${FFMPEG_VERSION:-$(read_manifest version)}"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
EXPECTED_SHA="$(read_manifest sha256)"

BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
[ -n "${BREW_PREFIX}" ] || { echo "Homebrew for ${HOST_ARCH} not found (see the header of this script)." >&2; exit 1; }
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
command -v pkg-config >/dev/null || { echo "pkg-config missing: brew install pkg-config" >&2; exit 1; }
command -v lame >/dev/null || [ -f "${BREW_PREFIX}/lib/libmp3lame.a" ] || { echo "lame missing for ${HOST_ARCH}: brew install lame" >&2; exit 1; }
pkg-config --exists libass || { echo "libass missing for ${HOST_ARCH}: brew install libass" >&2; exit 1; }

echo "=== Building FFmpeg ${FFMPEG_VERSION} for macOS ${HOST_ARCH} (electron arch: ${ELECTRON_ARCH}) ==="
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}" "${OUTPUT_DIR}"
cd "${BUILD_ROOT}"

echo "--> Downloading ${FFMPEG_URL}"
curl -fsSL "${FFMPEG_URL}" -o ffmpeg.tar.xz
ACTUAL_SHA="$(shasum -a 256 ffmpeg.tar.xz | awk '{print $1}')"
if [ "${UPDATE_CHECKSUMS:-}" = "1" ]; then
  node -e "const fs=require('fs');const p='${CHECKSUMS}';const m=require(p);m.source.sha256='${ACTUAL_SHA}';fs.writeFileSync(p,JSON.stringify(m,null,2)+'\n')"
  echo "--> Recorded source sha256 ${ACTUAL_SHA} in scripts/ffmpeg-checksums.json (review and commit)"
elif [ -n "${EXPECTED_SHA}" ]; then
  [ "${EXPECTED_SHA}" = "${ACTUAL_SHA}" ] || { echo "ERROR: source checksum mismatch (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})" >&2; exit 1; }
  echo "--> Source checksum verified"
elif [ "${CI:-}" = "true" ]; then
  echo "ERROR: no source checksum recorded; CI refuses unverified sources (run with UPDATE_CHECKSUMS=1 locally)." >&2
  exit 1
else
  echo "WARNING: no source checksum recorded. sha256 = ${ACTUAL_SHA}"
fi

tar -xf ffmpeg.tar.xz
cd "ffmpeg-${FFMPEG_VERSION}"

# Homebrew installs BOTH libfoo.a and libfoo.dylib and the linker prefers the dylib, which would leave
# the binary depending on /opt/homebrew (it would not run on any other Mac). Put ONLY the static
# archives of libass and everything it needs in a private directory searched first, so they get linked in.
STATIC_DIR="${BUILD_ROOT}/static-libs"
mkdir -p "${STATIC_DIR}"

# graphite2 (a harfbuzz dependency) is shipped by Homebrew as a dylib only, so build a static copy.
# Licensed LGPL-2.1+ / MPL-2.0 / GPL-2.0+ / MIT (1.3.15's LICENSE file): we use it under MIT (see docs/LICENSE-AUDIT.md).
GRAPHITE_VERSION="$(node -e "console.log(require('${CHECKSUMS}').graphite2.version)")"
GRAPHITE_URL="https://github.com/silnrsi/graphite/releases/download/${GRAPHITE_VERSION}/graphite2-${GRAPHITE_VERSION}.tgz"
GRAPHITE_EXPECTED="$(node -e "console.log(require('${CHECKSUMS}').graphite2.sha256||'')")"
echo "--> Building static graphite2 ${GRAPHITE_VERSION}"
curl -fsSL "${GRAPHITE_URL}" -o graphite2.tgz
GRAPHITE_ACTUAL="$(shasum -a 256 graphite2.tgz | awk '{print $1}')"
if [ "${UPDATE_CHECKSUMS:-}" = "1" ]; then
  node -e "const fs=require('fs');const p='${CHECKSUMS}';const m=require(p);m.graphite2.sha256='${GRAPHITE_ACTUAL}';fs.writeFileSync(p,JSON.stringify(m,null,2)+'\n')"
  echo "--> Recorded graphite2 sha256 ${GRAPHITE_ACTUAL} (review and commit)"
elif [ -n "${GRAPHITE_EXPECTED}" ]; then
  [ "${GRAPHITE_EXPECTED}" = "${GRAPHITE_ACTUAL}" ] || { echo "ERROR: graphite2 checksum mismatch (expected ${GRAPHITE_EXPECTED}, got ${GRAPHITE_ACTUAL})" >&2; exit 1; }
elif [ "${CI:-}" = "true" ]; then
  echo "ERROR: no graphite2 checksum recorded; run with UPDATE_CHECKSUMS=1 locally." >&2; exit 1
fi
tar -xzf graphite2.tgz
# Its Darwin branch runs a shared-library-only check even for a static build ("TARGET_SONAME_FILE is
# allowed only for SHARED libraries"); skip that check.
sed -i.bak 's|^\( *\)nolib_test(stdc++ \$<TARGET_SONAME_FILE:graphite2>)|\1# nolib_test skipped (static build)|' \
  "graphite2-${GRAPHITE_VERSION}/src/CMakeLists.txt"
cmake -S "graphite2-${GRAPHITE_VERSION}" -B graphite2-build -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="${HOST_ARCH}" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DGRAPHITE2_COMPARE_RENDERER=OFF -DCMAKE_INSTALL_PREFIX="${BUILD_ROOT}/graphite2-dist" >/dev/null
cmake --build graphite2-build -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >/dev/null
GRAPHITE_A="$(find graphite2-build -name 'libgraphite2.a' | head -1)"
[ -n "${GRAPHITE_A}" ] || { echo "graphite2 static build failed" >&2; exit 1; }
cp "${GRAPHITE_A}" "${STATIC_DIR}/libgraphite2.a"
SEARCH_DIRS="${BREW_PREFIX}/lib"
for flag in $(pkg-config --static --libs libass); do
  case "${flag}" in -L*) SEARCH_DIRS="${SEARCH_DIRS} ${flag#-L}";; esac
done
for flag in $(pkg-config --static --libs libass); do
  case "${flag}" in
    -l*)
      name="lib${flag#-l}.a"
      for dir in ${SEARCH_DIRS}; do
        if [ -f "${dir}/${name}" ]; then ln -sf "${dir}/${name}" "${STATIC_DIR}/${name}"; break; fi
      done
      ;;
  esac
done
# MP3 encoder for Combine Audio (.mp3 output). LGPL-2+, no pkg-config file: link its static archive directly.
[ -f "${BREW_PREFIX}/lib/libmp3lame.a" ] && ln -sf "${BREW_PREFIX}/lib/libmp3lame.a" "${STATIC_DIR}/libmp3lame.a"
# Homebrew builds lame 4.x against mpg123 (LGPL-2.1+), so its static archive needs libmpg123.a as well.
[ -f "${BREW_PREFIX}/lib/libmpg123.a" ] && ln -sf "${BREW_PREFIX}/lib/libmpg123.a" "${STATIC_DIR}/libmpg123.a"
echo "--> Static archives staged: $(ls "${STATIC_DIR}" | tr '\n' ' ')"

# Strictly LGPL (no --enable-gpl, no libx264/x265), libass for hard-burned subtitles, Apple hardware
# H.264 via VideoToolbox. libass is linked statically so the binary only needs system frameworks.
echo "--> Configuring"
./configure \
  --prefix="${BUILD_ROOT}/dist" \
  --disable-gpl \
  --disable-nonfree \
  --enable-version3 \
  --enable-libass \
  --enable-libmp3lame \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-sdl2 \
  --disable-doc \
  --disable-debug \
  --disable-xlib \
  --disable-libxcb \
  --disable-lzma \
  --arch="${HOST_ARCH}" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I${BREW_PREFIX}/include" \
  --extra-ldflags="-L${STATIC_DIR} -L${BREW_PREFIX}/lib" \
  --extra-libs="-lc++ -lmpg123"

echo "--> Compiling"
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cp ffmpeg "${OUTPUT_DIR}/ffmpeg"
chmod +x "${OUTPUT_DIR}/ffmpeg"
cd "${REPO_ROOT}"

echo "=== Verification ==="
node scripts/verify-ffmpeg.mjs "${OUTPUT_DIR}/ffmpeg"
echo "=== Success: ${OUTPUT_DIR}/ffmpeg ==="
