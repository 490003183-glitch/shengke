#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAME_DIR="$PROJECT_DIR/ThirdParty/lame"
if [ ! -f "$LAME_DIR/install/lib/libmp3lame.0.dylib" ]; then
    ARCHIVE_HASH="$(shasum -a 256 "$LAME_DIR/lame-3.100.tar.gz" | awk '{print $1}')"
    if [ "$ARCHIVE_HASH" != 'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e' ]; then
        printf '%s\n' 'LAME source archive checksum mismatch.' >&2
        exit 1
    fi
    tar -xzf "$LAME_DIR/lame-3.100.tar.gz" -C "$LAME_DIR"
    python3 - "$LAME_DIR/lame-3.100/include/libmp3lame.sym" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_text(p.read_text().replace('lame_init_old\n',''))
PY
    cd "$LAME_DIR/lame-3.100"
    ./configure --prefix="$LAME_DIR/install" --disable-frontend --disable-static --enable-shared --disable-dependency-tracking CC=clang CFLAGS='-O2 -mmacosx-version-min=14.0'
    make -j4
    make install
fi
install_name_tool -id '@rpath/libmp3lame.0.dylib' "$LAME_DIR/install/lib/libmp3lame.0.dylib"
