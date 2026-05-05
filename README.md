# sm64ex-macaroni

> **🚧 Work in progress** - sm64ex family build/run flow is working end-to-end. App bundling is nearly there, DMG packaging and the Ghostship preset are next up.

Wrapper scripts for building **Super Mario 64 PC ports** on **Intel Macs** running **macOS Tahoe** (26.x).

Inspired by [haframjolk/sm64ex-mac](https://github.com/haframjolk/sm64ex-mac), restructured to match the conventions used in my other macOS game-port wrappers (see [Related projects](#related-projects)).

## Status

| Script | Version | Status |
|---|---|---|
| `sm64-macaroni-initial-setup.sh` | v0.11 | ✅ tested |
| `sm64-macaroni-build.sh` | v0.11 | ✅ tested with `sm64pc/sm64ex` |
| `run-sm64-macaroni.sh` | v0.11 | ✅ tested - boots into Mario, exits clean |
| `sm64-macaroni-bundle.sh` | v0.12 | 🔧 LC_RPATH dedup fix landed, re-test pending |
| `sm64-macaroni-package.sh` | - | ⏳ planned (DMG creation) |
| `sm64-macaroni-sysinfo.sh` | - | ⏳ planned (system snapshot for bug reports) |
| `sm64-macaroni-collect-crash.sh` | - | ⏳ planned (crash-report collector) |

## Supported upstreams

Pick your fork via the `--upstream` flag. Each preset belongs to a **build family** that determines how the upstream is compiled and how its assets are loaded.

| Preset | Upstream | Family | What it adds | Tested? |
|---|---|---|---|---|
| `sm64ex` *(default)* | [sm64pc/sm64ex](https://github.com/sm64pc/sm64ex) | sm64ex (gmake) | Vanilla + options menu, BetterCamera | ✅ |
| `render96ex` | [Render96/Render96ex](https://github.com/Render96/Render96ex) | sm64ex (gmake) | HD model & texture-pack support | ⏳ |
| `coopdx` | [coop-deluxe/sm64coopdx](https://github.com/coop-deluxe/sm64coopdx) | sm64ex (gmake) | Online co-op + Lua mod API | ⏳ |
| `ghostship` | [HarbourMasters/Ghostship](https://github.com/HarbourMasters/Ghostship) | libultraship (CMake) | HM ecosystem, runtime Metal/OpenGL switching, `.o2r` mods | ⏳ scaffolding planned |

### Build families

| | sm64ex family | libultraship family |
|---|---|---|
| Build system | `gmake OSX_BUILD=1` | `cmake --build` |
| Asset processing | `extract_assets.py us` → raw `.inc.c` files in source tree | `.o2r` archive (libultraship resource format) generated at first run |
| Engine | Direct decomp + minimal PC layer | [libultraship](https://github.com/Kenix3/libultraship) + [Torch](https://github.com/HarbourMasters/Torch) |
| Renderer | Compile-time (`RENDER_API=GL`) | Runtime selectable: Metal / OpenGL |
| Config | `sm64config.txt` (plain text) | `<App>.cfg.json` (JSON) |
| Mods | Texture pack overlays | `.o2r` archives in `mods/` |

Both families consume the **same Super Mario 64 (US) ROM**: SHA-1 `9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE`. One ROM in `roms/`, all four upstream presets work.

Arbitrary forks: pass `--upstream-url <git-url>` alongside whichever preset has a compatible build contract (sm64ex preset for sm64ex-derived forks; ghostship preset for libultraship-derived forks).

## Quick start

### 1. First-run setup

```zsh
./sm64-macaroni-initial-setup.sh
```

Installs Xcode CLT, Homebrew, and the common build deps spanning both families: `gcc`, `make`, `cmake`, `audiofile`, `sdl2`, `glew`, `glfw`, `pkg-config`, `dylibbundler`, `python3`, `git`. Idempotent - safe to re-run.

### 2. Provide your ROM

Place your **Super Mario 64 (US, .z64)** ROM at:

```
roms/sm64.us.z64
```

- SHA-1: `9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE`
- Must be the US version in big-endian `.z64` format.
- Gitignored - never committed, never leaves your machine.
- Used by all four upstream presets.

### 3. Build

```zsh
./sm64-macaroni-build.sh                          # default: sm64pc/sm64ex
./sm64-macaroni-build.sh --upstream render96ex
./sm64-macaroni-build.sh --upstream coopdx
./sm64-macaroni-build.sh --upstream ghostship     # ⏳ in flight
./sm64-macaroni-build.sh --skip-deps              # skip Homebrew dep check
```

First sm64ex-family build runs in roughly 5-12 minutes on an Intel i7. Ghostship build timing TBD once scaffolding lands.

### 4. Launch

```zsh
./run-sm64-macaroni.sh                            # auto-detects most recent build
./run-sm64-macaroni.sh --upstream sm64ex          # force specific build
./run-sm64-macaroni.sh --restore-cfg              # restore latest config backup
```

### 5. Bundle (WIP)

```zsh
./sm64-macaroni-bundle.sh                         # auto-detect upstream
./sm64-macaroni-bundle.sh --upstream sm64ex
```

Produces `dist/<App>.app` with `dylibbundler`-bundled Homebrew dylibs and an ad-hoc codesign for Tahoe Gatekeeper.

## Repo layout

```
sm64ex-macaroni/
├── README.md
├── roms/                              # gitignored - place sm64.us.z64 here
├── src/                               # icon.icns, icon.png
├── screenshots/                       # README assets (TBD)
├── logs/                              # build / run / bundle logs (gitignored)
├── dist/                              # output .app bundles (gitignored)
├── sm64ex/                            # auto-cloned upstream (gitignored)
├── Render96ex/                        # auto-cloned upstream (gitignored)
├── sm64coopdx/                        # auto-cloned upstream (gitignored)
├── Ghostship/                         # auto-cloned upstream (gitignored)
├── sm64-macaroni-initial-setup.sh
├── sm64-macaroni-build.sh
├── run-sm64-macaroni.sh
├── sm64-macaroni-bundle.sh            # WIP
├── sm64-macaroni-package.sh           # planned
├── sm64-macaroni-sysinfo.sh           # planned
└── sm64-macaroni-collect-crash.sh     # planned
```

Log filenames include the upstream preset for easy disambiguation:

```
logs/build-sm64ex-20260505-0937.log
logs/build-render96ex-20260505-1042.log
logs/build-ghostship-20260506-1108.log
logs/bundle-sm64ex-20260505-1115.log
logs/run-20260505-1002.log
```

## Tested on

- macOS Tahoe 26.4.1 (build 25E253)
- MacBook Pro 16,2 (Intel Core i7, 2.3 GHz quad-core, 32 GB)
- Intel Iris Plus Graphics + DELL P2317H secondary display

Apple Silicon: untested. May work via Rosetta 2 - feedback welcome.

## Known issues

- **App bundle launch (sm64ex family)**: dyld `SIGABRT` on launch caused by duplicate `LC_RPATH '@executable_path/../libs/'` entries. sm64ex's `OSX_BUILD=1` path adds the rpath at link time and `dylibbundler` adds it again. macOS 14+ refuses to load binaries with duplicate rpaths. Fixed in `sm64-macaroni-bundle.sh` v0.12 (Step 7.5: enumerate via `otool -l`, dedupe via `install_name_tool -delete_rpath` + `-add_rpath` before `codesign`). End-to-end re-test pending.
- **Ghostship preset**: scaffolding being added; not yet runnable.
- **Render96ex / coopdx**: preset tables in place but not yet exercised on Tahoe.
- **No `.dmg` distribution yet**: package script not written. For now the bundle script's output in `dist/` is the share artifact.

## Roadmap

- [x] First-run setup script (sm64ex family)
- [x] Build script with multi-upstream support (sm64ex family)
- [x] Launcher with auto-detect + config backup
- [ ] App bundle script (LC_RPATH fix verified end-to-end)
- [ ] Ghostship preset: build-family branching in build/run/bundle scripts
- [ ] Validation pass on Render96ex
- [ ] Validation pass on sm64coopdx
- [ ] Validation pass on Ghostship
- [ ] DMG package script
- [ ] System info collector (for bug reports)
- [ ] Crash report collector
- [ ] Apple Silicon native build (or Rosetta-only support documentation)
- [ ] Screenshots in `screenshots/`

## Related projects

My other macOS port wrappers, all following the same script-and-CHANGELOG conventions:

- [perfectdark-macvanta](https://github.com/mkoterski/perfectdark-macvanta) - [HarbourMasters/Perfect Dark](https://github.com/HarbourMasters/PerfectDark) wrapper
- [spaghettikart-maccheese](https://github.com/mkoterski/spaghettikart-maccheese) - [HarbourMasters/SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) (Mario Kart 64) wrapper
- [starship-macalfa](https://github.com/mkoterski/starship-macalfa) - [HarbourMasters/Starship](https://github.com/HarbourMasters/Starship) (Star Fox 64) wrapper

Three of those wrap [HarbourMasters](https://github.com/HarbourMasters) ports built on libultraship, which is why the `ghostship` preset is being added here: it's the HarbourMasters Super Mario 64 port and slots cleanly alongside the others architecturally.

## Credits

- [haframjolk/sm64ex-mac](https://github.com/haframjolk/sm64ex-mac) - original macOS build script that this repo's sm64ex-family flow is based on.
- [sm64pc/sm64ex](https://github.com/sm64pc/sm64ex), [Render96/Render96ex](https://github.com/Render96/Render96ex), [coop-deluxe/sm64coopdx](https://github.com/coop-deluxe/sm64coopdx) - the actual sm64ex-family game ports.
- [HarbourMasters/Ghostship](https://github.com/HarbourMasters/Ghostship) - libultraship-based SM64 port.
- [Kenix3/libultraship](https://github.com/Kenix3/libultraship), [HarbourMasters/Torch](https://github.com/HarbourMasters/Torch) - the engine and asset-extraction toolchain underpinning the libultraship family.
- The broader Super Mario 64 decomp and PC port community.

This is a hobby wrapper project; all credit for the actual ports goes to the upstream authors and contributors.

## License

MIT for the wrapper scripts in this repo. Each upstream retains its own license terms.

You must provide your own legally-obtained Super Mario 64 (US) ROM. No ROMs, extracted assets, or copyrighted material are distributed with this repo.
