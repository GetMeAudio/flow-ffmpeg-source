# Flow by GetMeAudio - FFmpeg source offer

Flow 0.1.0 includes a copy of **FFmpeg**, licensed under the **GNU Lesser General Public License
version 3 or later (LGPL-3.0-or-later)**. FFmpeg is built without GPL or non-free components
(`--disable-gpl --disable-nonfree --enable-version3`). Flow starts FFmpeg as a separate program; Flow's own
code is not part of it. FFmpeg is a trademark of Fabrice Bellard.

This page identifies the exact source of the FFmpeg files shipped in Flow 0.1.0, and the build recipe.
Questions or requests for a copy of any source: support@getmeaudio.com

## Replacing FFmpeg

You may build your own FFmpeg from the sources below. Flow uses the FFmpeg program found in its installation
folder (`resources/ffmpeg/`); you may replace that file with your own compatible build.

## macOS (Apple Silicon and Intel)

Built from the FFmpeg 7.1.1 release with the script `macos/build-ffmpeg-macos.sh` in this repository.

- FFmpeg source: https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz
- SHA-256: `733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1`
- `./configure` arguments (also in `macos/configure.txt`):

```
--disable-gpl --disable-nonfree --enable-version3 --enable-libass --enable-libmp3lame --enable-videotoolbox --enable-audiotoolbox --disable-ffplay --disable-ffprobe --disable-sdl2 --disable-doc --disable-debug --disable-xlib --disable-libxcb --disable-lzma --arch=arm64 --pkg-config-flags=--static --extra-cflags=-I/opt/homebrew/include --extra-ldflags='-L/var/folders/wx/fw072f252jd5b0j8_7cnrz5m0000gn/T//gma-ffmpeg-build-arm64/static-libs -L/opt/homebrew/lib' --extra-libs='-lc++ -lmpg123'
```

Libraries linked statically into the macOS `ffmpeg` executable (obtain each library's source for the listed
version from its project page):

| Library | Version | Licence | Project |
| --- | --- | --- | --- |
| libass | 0.17.5 | ISC | https://github.com/libass/libass |
| FreeType | 2.14.3 | FTL | https://freetype.org |
| HarfBuzz | 14.5.0 | MIT | https://github.com/harfbuzz/harfbuzz |
| graphite2 | 1.3.15 | MIT | https://github.com/silnrsi/graphite |
| FriBidi | 1.0.17 | LGPL-2.1-or-later | https://github.com/fribidi/fribidi |
| GLib | 2.90.0 | LGPL-2.1-or-later | https://gitlab.gnome.org/GNOME/glib |
| GNU gettext (libintl) | 1.0 | LGPL-2.1-or-later | https://www.gnu.org/software/gettext/ |
| PCRE2 | 10.49 | BSD-3-Clause | https://github.com/PCRE2Project/pcre2 |
| libpng | 1.6.58 | libpng-2.0 | https://www.libpng.org |
| libunibreak | 8.0 | zlib | https://github.com/adah1972/libunibreak |
| LAME | 4.0 | LGPL-2.0-or-later | https://lame.sourceforge.io |
| mpg123 | 1.33.7 | LGPL-2.1-or-later | https://www.mpg123.de |

`macos/ffmpeg-checksums.json` records the SHA-256 of the FFmpeg and graphite2 source archives used.

## Windows (x64)

Flow ships the unmodified **BtbN "lgpl" FFmpeg build** (FFmpeg-Builds), which is built without GPL or non-free
components.

- Release tag: `autobuild-2026-10-12-13-12`
- Archive: https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-12-13-12/ffmpeg-N-127388-g615b07170e-win64-lgpl.zip
- SHA-256: `1ef240c07e11f2a5f286a02b7267c21f5a2443cb918344729c0385507491c936`
- FFmpeg source: git commit `615b07170e` of https://git.ffmpeg.org/ffmpeg.git
  (mirror: https://github.com/FFmpeg/FFmpeg)
- Build scripts and the sources of the libraries inside the build: https://github.com/BtbN/FFmpeg-Builds
  (repository state at the release tag above)

## Licence texts

`licenses/LGPL-3.0.txt` and `licenses/GPL-3.0.txt` (incorporated by the LGPL). Licence texts for every library
are also in `THIRD-PARTY-NOTICES.txt`, installed with Flow.
