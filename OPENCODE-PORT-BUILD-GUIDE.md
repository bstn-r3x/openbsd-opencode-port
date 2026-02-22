# Bun + OpenCode Port to OpenBSD 7.8 — Build Guide

## Overview

This project ports [Bun](https://bun.sh) (JavaScript runtime) v1.3.10 to OpenBSD 7.8 amd64, to run [OpenCode](https://github.com/anomalyco/opencode) (a TUI for AI coding assistants).

Bun cannot be built natively on OpenBSD due to Zig's ELF linker bugs. Instead, Zig is cross-compiled on macOS and linked on OpenBSD.

## Environment

| Machine | Role | Details |
|---------|------|---------|
| **Mac host** | Cross-compilation, codegen, Claude Code | Workspace: `<MAC_WORKSPACE>/opencode-port` |
| **openbsd-host** (OpenBSD 7.8) | Linking, C++ compilation, runtime | `ssh openbsd-host` (192.168.x.x), Intel i5-8350U (8 cores), 16GB RAM |

### Directory Structure

**Mac (`<MAC_WORKSPACE>/opencode-port/`):**
```
bun-source/              # Bun source tree (patched for OpenBSD)
  build/                 # Zig cross-compile output (bun-zig.o)
  build/codegen/         # Generated code (TS→C++/Zig)
zig-mac/                 # Mac ARM64 zig compiler (oven-sh/zig 0.15.2)
oven-zig/lib/            # Zig standard library + OpenBSD system headers
strip_debug_sections.py  # Python ELF stripper (removes .debug_* sections)
opencode-src/            # OpenCode source (patched for OpenBSD)
PLAN.md                  # Master project plan with all phases
```

**openbsd-host (`/srv/opencode-port/`):**
```
bun                      # Final linked binary (91MB PIE ELF)
bun-build/               # CMake build dir (C++ objects, libbun-profile.a)
  bun-zig.o              # Zig object (stripped, copied from Mac)
  libbun-profile.a       # C++ static archive (~6.5GB)
  codegen/               # Codegen outputs (copied from Mac)
  boringssl/             # BoringSSL static libs
  mimalloc/              # mimalloc static lib
  zlib/ brotli/ cares/   # Other dependency static libs
  highway/ libdeflate/ lshpack/ libarchive/ hdrhistogram/
  zstd/ sqlite/ tinycc/ lolhtml/
jsc-build/               # JavaScriptCore (pre-built)
  lib/                   # libJavaScriptCore.a, libWTF.a, libbmalloc.a
libuv-build/             # libuv static lib
openbsd_stubs_c.o        # C stubs (stat64, posix_spawn, etc.)
openbsd_stubs_cpp.o      # C++ stubs
v8_array_bridge.o        # libstdc++→libc++ symbol trampoline
Generated*.o             # 5 bindgen C++ objects
opencode/                # OpenCode source + node_modules
zig3                     # Zig compiler (OpenBSD native, rarely used)
```

**Symlinks on openbsd-host:**
- `/usr/obj/bun-build` → `<OLD_OPENBSD_WORKSPACE>/bun-build` (disk space)
- `/usr/obj/jsc-build` → `<OLD_OPENBSD_WORKSPACE>/jsc-build`

### Orchestration Repo Layout (public repo)

The published `openbsd-opencode-port` repo is intentionally small and focused.

Core directories:
- `scripts/build/` — build helpers and wrappers
- `scripts/test/` — automated baseline and visible TUI launchers
- `scripts/tools/` — maintenance utilities used by the build workflow

Local-only directories that may exist in a private working workspace (not required in the published repo):
- `backups/<timestamp>/` — structured snapshots
- `archives/` — retained local reference artifacts/tarballs

Note: older private workspaces also used root-level compatibility symlinks (for example `run-openbsd-baseline.sh`). In the published repo, prefer calling scripts via their canonical paths under `scripts/`.

## Build Pipeline

The full build has 5 stages. For incremental rebuilds after Zig source changes, only stages 1-4 are needed.

### Stage 1: Cross-compile Zig on Mac

Zig's internal ELF linker crashes on OpenBSD, so we cross-compile on macOS targeting OpenBSD x86-64.

```bash
cd <MAC_WORKSPACE>/opencode-port/bun-source

# The build runner path changes if build.zig changes. Find it with:
# ls /tmp/zig-cache/local/o/*/build

/tmp/zig-cache/local/o/0a66f162578fb4b6d6a0450f6bb90e4a/build \
  <MAC_WORKSPACE>/opencode-port/zig-mac/bootstrap-aarch64-macos-none/zig \
  <MAC_WORKSPACE>/opencode-port/oven-zig/lib \
  <MAC_WORKSPACE>/opencode-port/bun-source \
  /tmp/zig-cache/local /tmp/zig-cache/global \
  --seed 0x1234 obj \
  --prefix <MAC_WORKSPACE>/opencode-port/bun-source/build \
  -Dobj_format=obj -Dtarget=x86_64-openbsd-none -Doptimize=ReleaseFast -Dcpu=haswell \
  -Denable_logs=false -Denable_asan=false -Denable_fuzzilli=false -Denable_valgrind=false \
  -Denable_tinycc=true -Duse_mimalloc=true -Dllvm_codegen_threads=0 \
  -Dversion=1.3.10 -Dreported_nodejs_version=24.3.0 -Dcanary=1 \
  -Dcodegen_path=<MAC_WORKSPACE>/opencode-port/bun-source/build/codegen \
  -Dcodegen_embed=true -Dsha=unknown
```

**Takes ~20 minutes.** Output: `build/bun-zig.o` (~242MB with debug info).

**Important flags:**
- `-Dtarget=x86_64-openbsd-none` — cross-compile target
- `-Dobj_format=obj` — produce relocatable object, not executable
- `-Denable_asan=false` — underscore, NOT hyphen
- Do NOT use `-Z0000000000000000` — causes "no step named ''" error

### Stage 2: Strip debug sections

LLD 19 on OpenBSD can't handle the 242MB object file. GNU objcopy corrupts relocation type 42. Use the custom Python stripper instead.

```bash
cd <MAC_WORKSPACE>/opencode-port
python3 strip_debug_sections.py bun-source/build/bun-zig.o bun-source/build/bun-zig-stripped.o
```

Reduces 242MB → ~38MB. Removes `.debug_*` and `.rela.debug_*` sections while preserving all relocations.

### Stage 3: Fix ELF ABI byte and copy to openbsd-host

The Zig cross-compiler writes ELF OS/ABI byte as 0 (ELFOSABI_NONE). OpenBSD's linker expects 12 (ELFOSABI_OPENBSD).

```bash
# Fix ABI byte (offset 7 in ELF header)
printf '\x0c' | dd of=bun-source/build/bun-zig-stripped.o bs=1 seek=7 count=1 conv=notrunc

# Copy to openbsd-host
scp bun-source/build/bun-zig-stripped.o openbsd-host:/srv/opencode-port/bun-build/bun-zig.o
```

Note: the file is renamed to `bun-zig.o` on openbsd-host (the link command references this name).

### Stage 4: Link on openbsd-host

**Critical: `bun-zig.o` must NOT be inside `libbun-profile.a`.** If it is (from a previous `ar r` step), remove it first:

```bash
ssh openbsd-host "cd /srv/opencode-port/bun-build && ar t libbun-profile.a | grep bun-zig && ar d libbun-profile.a bun-zig.o || echo 'not in archive'"
```

Then link:

```bash
ssh openbsd-host 'clang++ -o /srv/opencode-port/bun \
  -Wl,--strip-debug \
  /srv/opencode-port/bun-build/bun-zig.o \
  /srv/opencode-port/openbsd_stubs_c.o \
  /srv/opencode-port/openbsd_stubs_cpp.o \
  /srv/opencode-port/GeneratedFakeTimersConfig.o \
  /srv/opencode-port/GeneratedSSLConfig.o \
  /srv/opencode-port/GeneratedSocketConfig.o \
  /srv/opencode-port/GeneratedSocketConfigBinaryType.o \
  /srv/opencode-port/GeneratedSocketConfigHandlers.o \
  /srv/opencode-port/v8_array_bridge.o \
  -Wl,--whole-archive /srv/opencode-port/bun-build/libbun-profile.a -Wl,--no-whole-archive \
  /srv/opencode-port/jsc-build/lib/libJavaScriptCore.a \
  /srv/opencode-port/jsc-build/lib/libWTF.a \
  /srv/opencode-port/jsc-build/lib/libbmalloc.a \
  /srv/opencode-port/libuv-build/libuv.a \
  /srv/opencode-port/bun-build/boringssl/libcrypto.a \
  /srv/opencode-port/bun-build/boringssl/libssl.a \
  /srv/opencode-port/bun-build/boringssl/libdecrepit.a \
  /srv/opencode-port/bun-build/mimalloc/libmimalloc.a \
  /srv/opencode-port/bun-build/zlib/libz.a \
  /srv/opencode-port/bun-build/brotli/libbrotlicommon.a \
  /srv/opencode-port/bun-build/brotli/libbrotlidec.a \
  /srv/opencode-port/bun-build/brotli/libbrotlienc.a \
  /srv/opencode-port/bun-build/cares/lib/libcares.a \
  /srv/opencode-port/bun-build/highway/libhwy.a \
  /srv/opencode-port/bun-build/libdeflate/libdeflate.a \
  /srv/opencode-port/bun-build/lshpack/libls-hpack.a \
  /srv/opencode-port/bun-build/libarchive/libarchive/libarchive.a \
  /srv/opencode-port/bun-build/hdrhistogram/src/libhdr_histogram_static.a \
  /srv/opencode-port/bun-build/zstd/lib/libzstd.a \
  /srv/opencode-port/bun-build/sqlite/libsqlite3.a \
  /srv/opencode-port/bun-build/tinycc/libtcc.a \
  /srv/opencode-port/bun-build/lolhtml/release/liblolhtml.a \
  /usr/local/lib/libicudata.a \
  /usr/local/lib/libicui18n.a \
  /usr/local/lib/libicuuc.a \
  -lc -lpthread -lm -lc++ -lkvm \
  -fno-exceptions -fno-rtti -Wl,--allow-multiple-definition'
```

**Takes ~2 minutes.** Output: `/srv/opencode-port/bun` (~91MB PIE ELF).

#### Why this link order matters

1. **`bun-zig.o` first, separate from `libbun-profile.a`** — avoids duplicate `stat64` symbols. The archive already contains C++ objects that define `stat64` wrappers; having `bun-zig.o` inside the archive creates conflicts.
2. **`--whole-archive` around `libbun-profile.a`** — forces all C++ objects to be included (many are only referenced via Zig's extern declarations, which the linker can't resolve from archive metadata).
3. **`v8_array_bridge.o`** — provides assembly trampoline for `v8::Array::New`. Zig emits a symbol expecting `std::function` (libstdc++ mangling: `St8function`) but libc++ provides `std::__1::function` (mangling: `NSt3__18function`). The trampoline bridges them.
4. **`--allow-multiple-definition`** — handles remaining duplicate symbols (e.g., `uv_tty_reset_mode` defined in both libuv and Bun's usockets).
5. **Static ICU** (`/usr/local/lib/libicu*.a`) — avoids runtime dependency on ICU shared libs.
6. **`-lkvm`** — OpenBSD-specific, needed for process introspection.

### Stage 5: Test

```bash
# Version check
ssh openbsd-host "/srv/opencode-port/bun --version"
# Expected: 1.3.10

# Quick eval
ssh openbsd-host '/srv/opencode-port/bun -e "console.log(1+1)"'
# Expected: 2

# Launch OpenCode TUI (interactive)
ssh -t openbsd-host "cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/bun run --conditions=browser src/index.ts"
# Expected: TUI renders and stays alive, keyboard input works

# Check CPU at idle (in another terminal)
ssh openbsd-host "top -b -d1 | head -20"
# Target: < 15% CPU for bun process
```

### Stage 5A: Interactive validation (manual, visible)

Use tmux for source-mode and compiled-mode TUI validation so rendering and keyboard behavior are visible.

Recommended launcher (from this orchestration repo):

```bash
./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>
```

This starts two tmux windows on the OpenBSD host:
- source mode TUI
- compiled binary TUI

Attach to the tmux session:

```bash
ssh <your-openbsd-host> 'tmux attach -t 8'
```

Direct launch commands used for interactive validation (appendix material):

Source mode:
```sh
ssh -t openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/bun run --conditions=browser src/index.ts'
```

Compiled mode:
```sh
ssh -t openbsd-host 'cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/opencode-bin'
```

### Stage 5B: Test evidence and release gate notes

When validating a new build or preparing a stable promotion:

1. Capture command outputs and exit codes for failed checks.
2. Save the generated baseline report under `artifacts/`.
3. Update `PORT-STATUS.md` and this build guide when behavior or commands change.
4. Treat a state as release-ready only when:
   - baseline automation passes,
   - interactive source and compiled TUI checks pass,
   - remaining bugs are explicitly documented with rationale/mitigation.

## Known Workarounds

### v8_array_bridge.o (libstdc++ → libc++ trampoline)

Zig's V8 bindings emit symbols mangled for libstdc++ (`std::function`), but OpenBSD uses libc++ (`std::__1::function`). The bridge is an assembly file that defines the expected symbol and jumps to the real one.

Source: `/srv/opencode-port/v8_array_bridge.S` (on openbsd-host).

### openbsd_stubs_c.o / openbsd_stubs_cpp.o

Provide OpenBSD implementations for functions Bun expects from Linux/macOS:
- `stat64`, `fstat64`, `lstat64` → aliased to `stat`, `fstat`, `lstat`
- `Bun__Os__getFreeMemory` → `sysctl(CTL_HW, HW_USERMEM64)`
- `sysctlbyname` → stub (returns -1)
- Signal forwarding stubs

### stat64 symbol conflicts

Bun's Zig code references `stat64` (macOS naming). OpenBSD only has `stat`. The stubs provide the alias. When linking, `bun-zig.o` must be a separate object (not inside `libbun-profile.a`) to avoid duplicate definitions with C++ objects that also wrap stat.

### ELF debug section stripping

LLD 19 on OpenBSD can't parse large (>200MB) ELF .o files. GNU objcopy 2.17 corrupts relocation type 42 (`R_X86_64_REX_GOTPCRELX`). The custom Python stripper (`strip_debug_sections.py`) removes `.debug_*` sections while preserving all relocations.

### kevent vs kevent64

macOS uses `kevent64_s` with `KEVENT_FLAG_ERROR_EVENTS`. OpenBSD uses standard `struct kevent`. Bun's usockets layer was patched to use `kevent()` with no eventlist in `kqueue_change()` to prevent event consumption.

### CPU burn mitigation (Phase I)

Three changes reduce idle CPU from 40-92% to <15%:
1. **Timer.zig**: 1ms minimum kevent timeout on OpenBSD (prevents busy-polling)
2. **ZigGlobalObject.cpp**: Reduced JSC thread pool (2 GC markers, 1 DFG, 1 FTL)
3. **opencode app.tsx**: `targetFps: 30` (halved from 60)

## Files Modified from Upstream Bun

See PLAN.md Phase C for the complete list (~50+ Zig files, ~20+ C++ files, CMake files). Key categories:

- **Platform detection**: `env.zig`, `build.zig`
- **System calls**: `sys.zig`, `fd.zig`, `bun.zig`
- **Event loop**: `posix_event_loop.zig`, `io.zig`, `event_loop.zig`, `Timer.zig`
- **kqueue**: `epoll_kqueue.c`, `epoll_kqueue.h`, related usockets files
- **Node.js compat**: `node_os.zig`, `node_fs.zig`, `dir_iterator.zig`
- **Process/spawn**: `process.zig`, `spawn.zig`, `bun-spawn.cpp`
- **C++ bindings**: `BunProcess.cpp`, `BunObject.cpp`, `c-bindings.cpp`, `ZigGlobalObject.cpp`
- **JSC patches**: 8 WebKit source files (see PLAN.md Phase D)
- **CMake**: `BuildBun.cmake`, `SetupWebKit.cmake`, `SetupBun.cmake`, `SetupZig.cmake`

## Files Modified from Upstream OpenCode

- `packages/opencode/src/tui/app.tsx` — `targetFps: 30`
- `packages/opencode/src/util/shell.ts` — OpenBSD shell detection
- `packages/opencode/src/util/clipboard.ts` — xclip/xsel for OpenBSD
- `packages/opencode/src/util/watcher.ts` — fs.watch polyfill
- `packages/opencode/src/pty/index.ts` — OpenBSD PTY support
- `packages/opencode/build.ts` — OpenBSD build target

## Testing Checklist

- [x] `bun --version` → 1.3.10
- [x] `bun -e "console.log(1+1)"` → 2
- [x] OpenCode TUI launches and stays alive (no premature exit) — verified via non-interactive 4s liveness smoke
- [ ] CPU at idle < 15% — not measured in automated baseline
- [x] Keyboard input works in TUI across source and compiled modes — Enter submit user-verified with model response path
- [x] No errors in `~/.local/share/opencode/log/dev.log` (error-pattern scan)
- [x] `fetch()` works (localhost + HTTPS)
- [x] `Bun.spawn` works
- [x] `bun install` works (smoke test)

Open issue tracking:
- OpenCode TUI visual artifact in tmux/OpenBSD: mitigation patch applied (safe tmux/OpenBSD logo rendering + session-header ANSI removal) and compiled binary rebuilt; final visual acceptance is pending manual confirmation.

Latest automated baseline report:
- `artifacts/openbsd-baseline-20260221-191735.md`

Latest comprehensive execution report:
- `artifacts/comprehensive-test-report-20260221-1558.md`
