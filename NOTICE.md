# Licenses and attribution

Original Shengke / Wave Studio code, documentation and the generated waveform icon are provided under the [MIT License](LICENSE). The icon is drawn by [scripts/make-icon.swift](scripts/make-icon.swift).

## LAME

MP3 encoding dynamically links to LAME 3.100, which retains its upstream GNU Library General Public License version 2 or later. The MIT license does not replace any upstream license.

- [Dependency details](ThirdParty/lame/README.md)
- [Upstream COPYING](ThirdParty/lame/COPYING)
- [Corresponding source archive](ThirdParty/lame/lame-3.100.tar.gz)
- [Local symbol-list patch](ThirdParty/lame/remove-obsolete-symbol.patch)
- [Rebuild script](scripts/build-lame.sh)

The source archive also contains upstream tools and build files with their own notices. Preserve those notices. The application bundle contains the replaceable LAME dylib, full license, corresponding source archive, patch and rebuild script. The build script uses local ad-hoc signing; it does not enable hardened runtime or library validation. After replacing a library in a locally built app, re-sign the bundle before running it.

## Reference software

This is an independent audio editor inspired by single-file waveform editing workflows. It is not affiliated with or endorsed by Felt Tip. Sound Studio is referenced only to identify the product used for workflow research.

No Sound Studio manual, webpage snapshot, screenshot, icon or source code is included in this public repository. Reference material remains with its respective owners; consult the [official documentation](https://www.felttip.com/ss/reference.html) and [release notes](https://www.felttip.com/ss/release-notes.html).

Apple system frameworks and SF Symbols are used through macOS APIs and are not redistributed as open-source components of this project.
