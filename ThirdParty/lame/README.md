# LAME dependency

LAME 3.100, used only for MP3 encoding through a dynamically linked library. Audio editing, decoding, UI and file workflow remain Swift / Apple frameworks.

- Official project: https://lame.sourceforge.io/
- Source: https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
- Retrieved: 2026-11-26.
- SHA-256: ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
- License: GNU Library General Public License version 2 or later; see upstream COPYING and source headers.
- Local patch: remove the obsolete `lame_init_old` symbol from `include/libmp3lame.sym`. Current Apple arm64 linker rejects this exported symbol because the upstream library does not define it. No encoding algorithm changes.
- Build: run `scripts/build-lame.sh` from the application source tree. It applies the one-line patch, builds with the macOS 14 deployment target and installs a replaceable dylib with an `@rpath` install name.
- Distribution: app Frameworks contains `libmp3lame.0.dylib`; Resources/ThirdParty/LAME includes the unmodified source archive, this notice, patch, build script and full COPYING license. The app uses local ad-hoc signing without library validation/hardened runtime.

The unpacked source and install directory are build dependencies. The source archive and patch are retained for reproduction. No system-wide codec or package manager is installed.
