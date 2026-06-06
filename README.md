# Beam iOS app

Native Swift app that consumes atman as a C-ABI static library.

## Layout

```
ios/
├── Beam/                     # Swift sources + bridging header + Info.plist
├── atman/                       # libatman.a + atman.h (produced by build_atman.sh)
├── build_atman.sh               # builds atman → atman/{libatman.a,atman.h}
├── project.yml                  # xcodegen config
└── README.md
```

`atman` lives at `../submodules/atman` (git submodule).

## One-time setup

1. Make sure submodules are initialized:
   ```
   git submodule update --init --recursive
   ```
2. Install Rust iOS targets:
   ```
   rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
   ```
3. Install `cbindgen` (header generator) and `xcodegen`:
   ```
   cargo install cbindgen
   brew install xcodegen
   ```
4. Set your Apple development team (so signing works):
   ```
   export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
   ```

## Generate the Xcode project

```
cd ios
xcodegen
```

## Build atman before opening Xcode

Xcode doesn't run the Rust build itself — invoke `build_atman.sh` by hand
whenever atman's source has changed, then open the project.

```
./build_atman.sh --arm64        # device
./build_atman.sh --x86_64       # simulator
./build_atman.sh                # both archs (lipo'd)
./build_atman.sh --release      # release profile
```

The script produces `atman/atman.h` + `atman/libatman.a`. Xcode picks them
up via the `HEADER_SEARCH_PATHS` / `LIBRARY_SEARCH_PATHS` settings.

```
open Beam.xcodeproj
```

## Keeping atman in sync with `beam-tauri`

The Tauri shell (under `../src-tauri/`) consumes atman via Cargo as a git
dep against the same upstream repo. The submodule pointer here and that git
dep are two independent pointers at atman — bump them together when you
move atman forward, otherwise the two shells can ship different protocol
behavior.

## What's wired

- **Send tab**: pick a file via `.fileImporter`, call
  `send_atman_blobs_send_files_command`, render the returned ticket as a Core Image
  QR code.
- **Receive tab**: scan a QR with `AVCaptureMetadataOutput` (or paste a
  ticket), call `send_atman_blobs_download_files_command` into the app's tmp dir,
  then route the result:
  - images / videos → `PHPhotoLibrary` (Photos)
  - everything else → app's `Documents/beam/` (Files-app exposed)
