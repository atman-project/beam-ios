# Beam iOS app

Native Swift app that consumes `atman` as a C-ABI static library.

<p align="center">
  <a href="https://apps.apple.com/app/id6777431954">
    <img
      src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg"
      alt="Download on the App Store"
      height="60">
  </a>
</p>


## Layout

```
ios/
├── Beam/                     # Swift sources + bridging header + Info.plist
├── atman/                       # libatman.a + atman.h (produced by build_atman.sh)
├── build_atman.sh               # builds atman → atman/{libatman.a,atman.h}
├── project.yml                  # xcodegen config
└── README.md
```

`atman` lives at `./submodules/atman` (git submodule).

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

## Generate the Xcode project

```
DEVELOPMENT_TEAM="YOUR_TEAM_ID" xcodegen
```

## Build `atman` before opening Xcode

Xcode doesn't run the Rust build itself — invoke `build_atman.sh` by hand
whenever atman's source has changed, then open the project.

```
./build_atman.sh --arm64                 # device
./build_atman.sh --sim-arm64             # simulator (Apple Silicon)
./build_atman.sh --x86_64                # simulator (Intel)
./build_atman.sh <target> --release      # release profile
```

The script produces `atman/atman.h` + `atman/libatman.a`. Xcode picks them
up via the `HEADER_SEARCH_PATHS` / `LIBRARY_SEARCH_PATHS` settings.

```
open Beam.xcodeproj
```
