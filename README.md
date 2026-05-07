# sm64-macaroni

> **🚧 Work in progress** - sm64ex and coopdx build/run flow is working. Render96ex was attempted and abandoned (broken upstream — see [Known issues](#known-issues)). App bundling, DMG packaging, and the Ghostship preset are next up.

Wrapper scripts for building **Super Mario 64 PC ports** on **Intel Macs** running **macOS Tahoe** (26.x).

This repo wraps two distinct port lineages under one set of scripts: the **sm64ex family** (gmake-based, originally inspired by [haframjolk/sm64ex-mac](https://github.com/haframjolk/sm64ex-mac)) and the **libultraship family** ([HarbourMasters/Ghostship](https://github.com/HarbourMasters/Ghostship)). Pick a fork, run the scripts. Conventions match my other macOS game-port wrappers (see [Related projects](#related-projects)).

> **Note on naming:** this repo was originally `sm64ex-macaroni` and was renamed to `sm64-macaroni` once Ghostship support was scoped in. sm64ex is no longer the only target. Bundle IDs migrated to `com.mkoterski.sm64-macaroni.<preset>` in `sm64-macaroni-bundle.sh` v0.13.

## Status

| Script | Version | Status |
|---|---|---|
| `sm64-macaroni-initial-setup.sh` | v0.12 | ✅ tested |
| `sm64-macaroni-build.sh` | v0.18 | ✅ sm64ex / ✅ coopdx / ❌ render96ex (broken upstream) |
| `run-sm64-macaroni.sh` | v0.12 | ✅ sm64ex - boots into Mario, exits clean |
| `sm64-macaroni-bundle.sh` | v0.13 | 🔧 LC_RPATH dedup fix landed, re-test pending |
| `sm64-macaroni-package.sh` | - | ⏳ planned (DMG creation) |
| `sm64-macaroni-sysinfo.sh` | - | ⏳ planned (system snapshot for bug reports) |
| `sm64-macaroni-collect-crash.sh` | - | ⏳ planned (crash-report collector) |

**Active focus:** adding the `ghostship` preset, which requires a `BUILD_FAMILY` rework across the build/run/bundle scripts to handle the libultraship/CMake/`.o2r` toolchain alongside the existing sm64ex/gmake/raw-asset toolchain.

## Supported upstreams

Pick your fork via the `--upstream` flag. Each preset belongs to a **build family** that determines how the upstream is compiled and how its assets are loaded.

| Preset | Upstream | Family | What it adds | Tested? |
|---|---|---|---|---|
| `sm64ex` *(default)* | [sm64pc/sm64ex](https://github.com/sm64pc/sm64ex) | sm64ex (gmake) | Vanilla + options menu, BetterCamera | ✅ |
| `coopdx` | [coop-deluxe/sm64coopdx](https://github.com/coop-deluxe/sm64coopdx) | sm64ex (gmake) | Online co-op + Lua mod API | ✅ builds, launch untested |
| `render96ex` | [Render96/Render96ex](https://github.com/Render96/Render96ex) | sm64ex (gmake) | HD model & texture-pack support | ❌ broken upstream |
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
- Used by all upstream presets.

### 3. Build

```zsh
./sm64-macaroni-build.sh                          # default: sm64pc/sm64ex
./sm64-macaroni-build.sh --upstream coopdx
./sm64-macaroni-build.sh --upstream ghostship     # ⏳ in flight
./sm64-macaroni-build.sh --skip-deps              # skip Homebrew dep check
```

First sm64ex build runs in roughly 3-5 minutes on an Intel i7. coopdx takes longer (~7-10 minutes) due to its larger dependency surface (Discord SDK, libcoopnet, libjuice).

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
sm64-macaroni/
├── README.md
├── roms/                              # gitignored - place sm64.us.z64 here
├── src/                               # icon.icns, icon.png
├── screenshots/                       # README assets (TBD)
├── logs/                              # build / run / bundle logs (gitignored)
├── dist/                              # output .app bundles (gitignored)
├── sm64ex/                            # auto-cloned upstream (gitignored)
├── sm64coopdx/                        # auto-cloned upstream (gitignored)
├── Render96ex/                        # auto-cloned upstream (gitignored, broken)
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
logs/build-coopdx-20260505-1957.log
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

### Render96ex: broken upstream on macOS Tahoe ❌

Render96ex's macOS support is effectively unmaintained. Five distinct issues surfaced during the porting attempt, in roughly this order:

1. **`vsnprintf` undeclared** in `tools/aiff_extract_codebook.c` due to `_XOPEN_SOURCE 500` gating C99 functions out of stdio.h's API surface (Tahoe clang treats implicit declarations as a hard error).
2. **`<malloc.h>` not found** in `tools/n64graphics_ci_dir/exoquant/exoquant.c` (Linux glibc-ism; macOS uses `<stdlib.h>`).
3. **`tabledesign` linker race** against `libaudiofile.a` under `-j8` parallelism.
4. **`cpp-9: command not found`** — Makefile hardcodes GCC 9's preprocessor; Homebrew currently ships gcc-15.
5. **`<SDL2/SDL.h>` not found** — render96ex source uses Linux include convention against Homebrew's `-I/usr/local/include/SDL2` cflags.

Patches 1–5 were implemented and shipped in `sm64-macaroni-build.sh` v0.14–v0.17 (preserved in the script for future revival but gated on `--upstream render96ex`). A 6th issue (`cpp-15` linemarker output mangling generated headers) was reached before stopping the porting work.

The dependency chain of upstream-specific patches needed to bring up render96ex on Tahoe makes this wrapper effectively a fork of a fork — outside the scope of what these scripts should be doing.

**Workaround for HD-texture users:** vanilla `sm64ex` with `EXTERNAL_DATA=1` (the wrapper's default) supports texture-pack drop-in. Most Render96 texture packs work directly against vanilla sm64ex's external-data layout.

`./sm64-macaroni-build.sh --upstream render96ex` will print a warning on launch but will still attempt the build, in case anyone wants to keep iterating against a different render96 fork via `--upstream-url`.

### App bundle launch (sm64ex family)

dyld `SIGABRT` on launch caused by duplicate `LC_RPATH '@executable_path/../libs/'` entries. sm64ex's `OSX_BUILD=1` path adds the rpath at link time and `dylibbundler` adds it again. macOS 14+ refuses to load binaries with duplicate rpaths. Fixed in `sm64-macaroni-bundle.sh` v0.11+ (Step 7.5: enumerate via `otool -l`, dedupe via `install_name_tool -delete_rpath` + `-add_rpath` before `codesign`). End-to-end re-test pending.

### Ghostship preset

Scaffolding planned but not yet implemented. Adding it requires a `BUILD_FAMILY` field on the preset table and case-branching the clone/extract/build steps to handle CMake + `.o2r` instead of gmake + raw assets. This is the next major piece of work.

### No `.dmg` distribution yet

Package script not written. For now the bundle script's output in `dist/` is the share artifact.

## Roadmap

- [x] First-run setup script (sm64ex family)
- [x] Build script with multi-upstream support (sm64ex family)
- [x] Launcher with auto-detect + config backup
- [x] Validation pass on coopdx (build only; runtime test pending)
- [x] Render96ex: attempted, abandoned — see [Known issues](#known-issues)
- [ ] App bundle script (LC_RPATH fix verified end-to-end)
- [ ] Runtime test of coopdx
- [ ] Ghostship preset: `BUILD_FAMILY` rework in build/run/bundle scripts
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
- [sm64pc/sm64ex](https://github.com/sm64pc/sm64ex), [coop-deluxe/sm64coopdx](https://github.com/coop-deluxe/sm64coopdx) - the actual sm64ex-family game ports running today.
- [Render96/Render96ex](https://github.com/Render96/Render96ex) - HD-textures fork; macOS bringup hit the limit of what reasonable wrapper-script patching can do, see [Known issues](#known-issues).
- [HarbourMasters/Ghostship](https://github.com/HarbourMasters/Ghostship) - libultraship-based SM64 port.
- [Kenix3/libultraship](https://github.com/Kenix3/libultraship), [HarbourMasters/Torch](https://github.com/HarbourMasters/Torch) - the engine and asset-extraction toolchain underpinning the libultraship family.
- The broader Super Mario 64 decomp and PC port community.

This is a hobby wrapper project; all credit for the actual ports goes to the upstream authors and contributors.

## License

MIT for the wrapper scripts in this repo. Each upstream retains its own license terms.

You must provide your own legally-obtained Super Mario 64 (US) ROM. No ROMs, extracted assets, or copyrighted material are distributed with this repo.
