# Contributing

Shengke is a native macOS editor for one audio file at a time. Keep the workflow direct: open a file from Finder, edit, listen and save. The three primary file actions remain overwrite in the source encoding, save a copy in the source encoding, and replace the source with WAV after successful verification.

## Development

1. Install Xcode or Apple Command Line Tools and Python 3.
2. Run `./scripts/build-lame.sh` before compiling Swift targets.
3. Run `./scripts/build-app.sh` to create the locally signed app in `dist/`.
4. Run `swift run --build-system native CoreChecks` for audio and persistence checks.
5. Run `swift run --build-system native WorkflowChecks` on a Mac with an available audio output device. It exercises the actual playback engine with monitoring muted.

Use generated test signals or files you are permitted to share. Do not submit personal recordings, application usage notes, credentials, absolute home-directory paths, build caches or reference manuals.

Audio changes should check frame counts, sample rates, channel relationships, selection boundaries, undo and output readback. Keep objective checks separate from subjective listening and hardware verification. Do not label a feature as tested merely because it builds.

Issues should include the app version, macOS version, input container/codec/sample rate/channel count, steps to reproduce, expected behavior and actual behavior. A minimal synthetic example is preferable to private audio.
