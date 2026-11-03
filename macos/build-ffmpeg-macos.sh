#!/usr/bin/env bash
# scripts/build-ffmpeg-macos.sh
#
# Builds an LGPL-only, libass-enabled FFmpeg for macOS that runs on every supported Mac (system
# frameworks only, minimum macOS from scripts/ffmpeg-checksums.json). Conforms to
# docs/adr/0012-ffmpeg-binary-sourcing.md.
#
#   Apple Silicon (arm64):  ./scripts/build-ffmpeg-macos.sh            -> bin/mac-arm64/ffmpeg
#   Intel (x64), on an Intel Mac or Intel CI runner:
#                           ./scripts/build-ffmpeg-macos.sh            -> bin/mac-x64/ffmpeg
#   Intel (x64), on an Apple Silicon Mac (builds natively under Rosetta 2, no cross-compiling):
#                           arch -x86_64 /bin/bash scripts/build-ffmpeg-macos.sh
#
# Every library linked into the binary (FreeType, FriBidi, HarfBuzz, libunibreak, libass, LAME) is built HERE from
# the exact source archive pinned in scripts/ffmpeg-checksums.json ("macDeps"), with
# MACOSX_DEPLOYMENT_TARGET set. Homebrew's own libraries are never linked: they are compiled for the
# build machine's macOS version, so a binary linked against them refuses to run on older macOS.
#
# Build tools only (not shipped), from Homebrew or pip:  pkg-config, meson, ninja (+ nasm on Intel)
#
# Environment:  FFMPEG_VERSION (default from the manifest), UPDATE_CHECKSUMS=1 to record a source's
# SHA-256 (do this once on a trusted machine and commit). CI=true refuses an unrecorded checksum.

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
DEPS_PREFIX="${BUILD_ROOT}/deps"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

CHECKSUMS="${SCRIPT_DIR}/ffmpeg-checksums.json"
manifest() { node -e "const m=require('${CHECKSUMS}');const v=$1;console.log(v===undefined||v===null?'':v)"; }
FFMPEG_VERSION="${FFMPEG_VERSION:-$(manifest 'm.source.version')}"
MIN_MACOS="$(manifest 'm.macMinimumSystemVersion')"
[ -n "${MIN_MACOS}" ] || { echo "macMinimumSystemVersion missing from ${CHECKSUMS}" >&2; exit 1; }

for tool in pkg-config meson ninja; do
  command -v "${tool}" >/dev/null || { echo "${tool} missing: brew install ${tool} (build tool only)" >&2; exit 1; }
done
if [ "${HOST_ARCH}" = "x86_64" ]; then
  command -v nasm >/dev/null || { echo "nasm missing: brew install nasm" >&2; exit 1; }
fi

# Everything below compiles for the minimum macOS, and pkg-config only ever sees OUR libraries.
export MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}"
export CFLAGS="-O2 -arch ${HOST_ARCH} -mmacosx-version-min=${MIN_MACOS}"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-arch ${HOST_ARCH} -mmacosx-version-min=${MIN_MACOS}"
export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH

echo "=== Building FFmpeg ${FFMPEG_VERSION} for macOS ${MIN_MACOS}+ on ${HOST_ARCH} (electron arch: ${ELECTRON_ARCH}) ==="
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}" "${OUTPUT_DIR}" "${DEPS_PREFIX}"
cd "${BUILD_ROOT}"

# fetch <manifest path, e.g. m.source> <file name>: download and check against the recorded SHA-256.
fetch() {
  local key="$1" file="$2"
  local url expected actual
  url="$(manifest "${key}.url")"
  expected="$(manifest "${key}.sha256")"
  echo "--> Downloading ${url}"
  curl -fsSL "${url}" -o "${file}"
  actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  if [ "${UPDATE_CHECKSUMS:-}" = "1" ]; then
    node -e "const fs=require('fs');const p='${CHECKSUMS}';const m=require(p);${key}.sha256='${actual}';fs.writeFileSync(p,JSON.stringify(m,null,2)+'\n')"
    echo "    recorded sha256 ${actual} (review and commit)"
  elif [ -n "${expected}" ]; then
    [ "${expected}" = "${actual}" ] || { echo "ERROR: checksum mismatch for ${file} (expected ${expected}, got ${actual})" >&2; exit 1; }
    echo "    checksum verified"
  elif [ "${CI:-}" = "true" ]; then
    echo "ERROR: no checksum recorded for ${file}; CI refuses unverified sources (UPDATE_CHECKSUMS=1 locally)." >&2
    exit 1
  else
    echo "WARNING: no checksum recorded for ${file}. sha256 = ${actual}"
  fi
}

# unpack <manifest key under macDeps>: downloads, verifies and extracts; prints the source folder.
unpack() {
  local name="$1" url file
  url="$(manifest "m.macDeps.${name}.url")"
  file="$(basename "${url}")"
  fetch "m.macDeps.${name}" "${file}" >&2
  tar -xf "${file}"
  echo "${BUILD_ROOT}/${file%.tar.*}"
}

meson_static() {
  local src="$1"; shift
  meson setup "${src}/build" "${src}" --prefix="${DEPS_PREFIX}" --libdir=lib --buildtype=release \
    --default-library=static -Db_ndebug=true "$@" >/dev/null
  ninja -C "${src}/build" -j"${JOBS}" >/dev/null
  ninja -C "${src}/build" install >/dev/null
}

# 1. FreeType (font rasterising for libass). No PNG/zlib/bzip2/brotli/HarfBuzz back-references.
echo "--> FreeType"
SRC="$(unpack freetype)"
meson_static "${SRC}" -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dbrotli=disabled -Dharfbuzz=disabled

# 2. FriBidi (bidirectional text).
echo "--> FriBidi"
SRC="$(unpack fribidi)"
meson_static "${SRC}" -Ddocs=false -Dbin=false -Dtests=false

# 3. HarfBuzz (text shaping) with FreeType only: no GLib/gettext/PCRE2/graphite2/ICU/Cairo.
echo "--> HarfBuzz"
SRC="$(unpack harfbuzz)"
meson_static "${SRC}" -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
  -Dchafa=disabled -Dicu=disabled -Dgraphite2=disabled -Dintrospection=disabled -Dtests=disabled \
  -Ddocs=disabled -Dutilities=disabled -Dcoretext=disabled

# 4. libunibreak (Unicode line breaking, so burned-in subtitles wrap correctly in every script).
echo "--> libunibreak"
SRC="$(unpack libunibreak)"
(
  cd "${SRC}"
  ./configure --prefix="${DEPS_PREFIX}" --enable-static --disable-shared \
    --disable-dependency-tracking >/dev/null
  make -j"${JOBS}" >/dev/null
  make install >/dev/null
)

# 5. libass (subtitle burn-in), using macOS CoreText for fonts: no fontconfig.
echo "--> libass"
SRC="$(unpack libass)"
meson_static "${SRC}" -Dfontconfig=disabled -Dcoretext=enabled -Ddirectwrite=disabled \
  -Dlibunibreak=enabled -Drequire-system-font-provider=true -Dtest=false -Dprofile=false

# 6. LAME (MP3 encoder for Combine Audio). Encoder only: no decoder, so no mpg123.
echo "--> LAME"
SRC="$(unpack lame)"
(
  cd "${SRC}"
  # 3.100's export list names a symbol that no longer exists; harmless for a static library but
  # the generated libtool rule still reads it.
  sed -i.bak '/lame_init_old/d' include/libmp3lame.sym
  ./configure --prefix="${DEPS_PREFIX}" --enable-static --disable-shared --disable-frontend \
    --disable-decoder --disable-dependency-tracking >/dev/null
  make -j"${JOBS}" >/dev/null
  make install >/dev/null
)

# 7. FFmpeg itself.
fetch "m.source" ffmpeg.tar.xz
tar -xf ffmpeg.tar.xz
cd "ffmpeg-${FFMPEG_VERSION}"

# Strictly LGPL (no --enable-gpl, no libx264/x265), libass for hard-burned subtitles, Apple hardware
# H.264 via VideoToolbox and AAC via AudioToolbox.
echo "--> Configuring FFmpeg"
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
  --disable-bzlib \
  --disable-iconv \
  --arch="${HOST_ARCH}" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I${DEPS_PREFIX}/include -mmacosx-version-min=${MIN_MACOS}" \
  --extra-ldflags="-L${DEPS_PREFIX}/lib -mmacosx-version-min=${MIN_MACOS}" \
  --extra-libs="-lc++"

echo "--> Compiling FFmpeg"
make -j"${JOBS}"

cp ffmpeg "${OUTPUT_DIR}/ffmpeg"
chmod +x "${OUTPUT_DIR}/ffmpeg"
cd "${REPO_ROOT}"

echo "=== Verification ==="
npx tsx scripts/verify-ffmpeg.mjs "${OUTPUT_DIR}/ffmpeg"
echo "=== Success: ${OUTPUT_DIR}/ffmpeg ==="
