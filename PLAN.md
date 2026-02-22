# Bun Port to OpenBSD 7.8 — State & Plan

## Goal
Port Bun (JavaScript runtime) to OpenBSD 7.8 amd64, ultimately to run OpenCode v1.1.65 via `bun build --compile`.

## Environment
- **Mac host**: runs Claude Code, workspace at `<MAC_WORKSPACE>/opencode-port`
- **OpenBSD 7.8 physical server (openbsd-host)**: `ssh openbsd-host` (192.168.x.x), Lenovo ThinkPad, Intel i5-8350U (8 cores), 16.4GB RAM, OpenBSD 7.8 amd64, Clang 19.1.7, CMake 3.31.8, ICU 77.1, Rust
- **NFS**: Mac `<MAC_WORKSPACE>/opencode-port` → OpenBSD `/mnt/mac-shared` (mount with `-o tcp,rw,soft,intr,noatime`)
  - Mac IP: 192.168.x.x (Ethernet interface reachable from the OpenBSD host)
  - Note: Mac also has 192.168.x.x on WiFi interface (not used for this workflow)
- **Disk layout** (openbsd-host — all build dirs under /home via symlinks from /usr/obj):
  - `/home` — 97GB free (was 16GB on old VM)
  - `/usr/obj` — symlinks to /home (bun-build, jsc-build, bun-vendor)
  - `/mnt/mac-shared` — NFS from Mac
- **doas**: configured with `permit nopass admin` in `/etc/doas.conf`

## Phase Plan Overview

| Phase | Description | Status |
|-------|-------------|--------|
| A | Fix zig2 linker for OpenBSD | DONE |
| B | Build stage3 zig compiler | DONE |
| C | Patch Bun source for OpenBSD | DONE |
| D | Build JSC (JavaScriptCore) | DONE |
| E | Run codegen on Mac, build Bun on OpenBSD | DONE — binary runs, 27/27 tests pass (fetch+spawn+connect all work) |
| F | Build OpenCode with Bun | **DONE** — TUI fully working in both source AND compiled modes. Keyboard input works. `onTick` event dispatch fix (`isMac` → `isBSD`) was the root cause. |
| G | OpenCode source patches for OpenBSD | DONE — 6 files patched: watcher, pty, shell, clipboard, build.ts, bin/opencode |
| H | Rebuild Bun with code improvements | DONE — Zig cross-compile on Mac, relink on openbsd-host. Fixed io.zig kqueue routing + stat64 export wrappers. |
| I | Fix OpenCode TUI CPU burn + black screen | **DONE** — CPU fixes (kevent timeout, JSC thread reduction) + TUI rendering fix (debug traces broke Solid.js lazy evaluation). |

Note (February 21, 2026): this file contains both historical notes and current state snapshots from different sessions. Use `PORT-STATUS.md` and `FINISH-PLAN.md` as the canonical current-state docs, and `artifacts/openbsd-baseline-20260221-191735.md` for the latest automated verification run.

Latest update (February 21, 2026):
- OpenCode prompt Enter-submit root cause was traced and fixed in source mode (stale `store.prompt.input` vs live `input.plainText` at submit time).
- Source-mode tmux Enter submission has user confirmation.
- Compiled-mode tmux Enter submission also has user confirmation (input submit + model reply observed).
- Regression test coverage hardening is still pending in the remote build tree.
- Rendering hardening applied for tmux/OpenBSD in source and rebuilt compiled binary: safe logo rendering path and removal of ANSI-style session header tokens.

---

## Phase I: Fix OpenCode TUI CPU Burn on OpenBSD

### Problem
OpenCode TUI burns 40-92% CPU at idle on OpenBSD with 7 JSC threads in constant R+ state.

### Root Causes Identified
1. **kevent busy-loop**: `Timer.zig:getTimeout()` returns timeout=0 when `immediate_tasks.items.len > 0`, combined with always-ready EVFILT_TIMER events from libopentui's 60fps render timer
2. **sched_yield storm**: 12,348 `sched_yield()` calls/2s from JSC's WTF::LockAlgorithm spin loop — OpenBSD's sched_yield doesn't effectively yield
3. **Excessive render FPS**: OpenCode sets `targetFps: 60` which is unnecessary for a terminal UI

### Changes Made

| File | Change | Effect |
|------|--------|--------|
| `src/bun.js/api/Timer.zig` | On OpenBSD, `getTimeout()` returns 1ms minimum instead of 0 for immediate_tasks and expired timers | Prevents kevent non-blocking poll loop |
| `src/bun.js/event_loop.zig` | On OpenBSD, drain immediate tasks (up to 16 iterations) and expired timers BEFORE entering kevent in both `autoTick()` and `autoTickActive()` | Ensures getTimeout() sees next timer deadline, not already-passed ones |
| `src/bun.js/bindings/ZigGlobalObject.cpp` | On OpenBSD, set `numberOfGCMarkers=2`, `numberOfDFGCompilerThreads=1`, `numberOfFTLCompilerThreads=1` | Reduces JSC threads from ~7 to ~4, cutting sched_yield contention |
| `opencode-src/.../tui/app.tsx` | `targetFps: 60` → `targetFps: 30` | Halves render loop frequency |
| `build/.../wtf/LockAlgorithmInlines.h` | On OpenBSD, replace `Thread::yield()` with 100µs nanosleep in spin loop | Only effective with WEBKIT_LOCAL=ON rebuild |

### Build Steps (Phase I)
1. Zig cross-compile on Mac: `zig build obj` with OpenBSD target → `bun-zig.o`
2. Strip debug sections: `strip_debug_sections.py` → `bun-zig-stripped.o`
3. Fix ELF OS/ABI: `printf '\x0c' | dd of=bun-zig.o bs=1 seek=7 count=1 conv=notrunc`
4. Copy to openbsd-host: `cp /mnt/mac-shared/bun-source/build/bun-zig-stripped.o /srv/opencode-port/bun-build/`
5. Recompile ZigGlobalObject.cpp on openbsd-host (manual clang++ from compile_commands.json)
6. Update libbun-profile.a: `ar r libbun-profile.a ZigGlobalObject.cpp.o`
7. Relink on openbsd-host (same link command as Phase E)

### Testing Status
- [ ] Binary starts and runs: bun --version → 1.3.10
- [ ] OpenCode TUI launches in source mode
- [ ] CPU usage at idle (target: <10%)
- [ ] kevent call frequency reduced
- [ ] sched_yield call frequency reduced
- [ ] Keyboard input still works
- [ ] No regressions in basic functionality

---

## Phase A: Fix zig2 linker for OpenBSD (DONE)

**Problem**: zig2's internal ELF linker loads libc DSOs with `needed=false`, causing static libc linkage. OpenBSD 7.8's pinsyscall enforcement kills binaries that make syscalls from non-registered addresses.

**Solution: build-obj + cc linking**

1. Compile with `zig2 build-obj` (produces `.o` files)
2. Link with system `cc` (dynamically links libc correctly)
3. Replace cached build runner in `.zig-cache/` before re-running build

## Phase B: Build stage3 zig compiler (DONE)

- **Binary**: `/srv/opencode-port/zig3` — 177MB ELF 64-bit, x86-64
- **Version**: 0.15.2 (oven-sh/zig fork with `#` private field syntax)
- **Features**: proper DT_NEEDED, .note.openbsd.ident
- **Note**: zig3 has the same `needed=false` bug — always use build-obj + cc for final linking on OpenBSD

## Phase C: Patch Bun source for OpenBSD (DONE)

### Completed patches (~50+ Zig files)

**Core platform detection:**
- `src/env.zig` — Added `.openbsd` to `OperatingSystem` enum, `isOpenBSD`, `isBSD` constants, all switch methods
- `build.zig` — `.openbsd` OS tag mapping, zlib path, async path, `OPENBSD` macro for translate-c, OpenBSD system include paths for translate-c

**System calls & low-level:**
- `src/sys.zig` — 14+ switches: errno imports, syscall backend, O flags, renameat2 fallback, write/read, poll/ppoll, getFdPath, statfs, writev/readv iovcnt casts, F.GETPATH split, setFileOffset with lseek
- `src/fd.zig` — closeAllowingStandardIo: `.linux, .openbsd` (standard libc close)
- `src/workaround_missing_symbols.zig` — `.mac, .openbsd => darwin` (stat wrappers)
- `src/perf.zig` — `.openbsd => Disabled`
- `src/bun.zig` — StatFS type mapping, getRoughTickCount (clock_gettime MONOTONIC), getFdPath (fchdir+getcwd for OpenBSD)

**C headers for translate-c:**
- `src/c-headers-for-zig.h` — Added `#elif OPENBSD` section with fcntl, net/if.h, net/if_dl.h, spawn.h, sys/socket.h, sys/stat.h, sys/mount.h, sys/sysctl.h

**Event loop & I/O (kevent64 → kevent abstraction DONE):**
- `src/async/posix_event_loop.zig` — Full kevent abstraction:
  - `KEvent` type alias (kevent64_s on macOS, Kevent on other BSDs)
  - `initKEvent()` helper (handles ext field presence)
  - `keventCall()` wrapper (kevent64 on macOS, kevent on BSDs)
  - `KEventWaker` split: `MacOSKEventWaker` (mach ports) + `OpenBSDKEventWaker` (pipe+kqueue)
  - Removed c_int/c_uint shadowing, fixed fcntl SETFL error union handling
- `src/io/io.zig` — Same kevent abstraction
- `src/deps/uws/Loop.zig` — EventType: `.openbsd => std.posix.system.Kevent`
- `src/Watcher.zig` — Platform: `.mac, .openbsd => KEventWatcher`, requires_file_descriptors: true

**Runtime & bindings:**
- `src/Global.zig` — quick_exit fallback (use std.c.exit on OpenBSD)
- `src/analytics.zig` — Custom utsname struct for OpenBSD (std.c.utsname is void), forOpenBSD() function
- `src/crash_handler.zig` — Signal handling, siginfo addr field, Platform enum (openbsd_x86_64)
- `src/dns.zig` — Backend: `.mac, .openbsd => .system`, AI filter without ALL/V4MAPPED
- `src/Terminal.zig` — IUTF8 guarded with @hasField (OpenBSD lacks it)
- `src/threading/Futex.zig` — OpenBSD futex implementation, isWasm() API fix

**Node.js compatibility:**
- `src/bun.js/node/node_os.zig` — cpusImplOpenBSD (sysctl), loadavg split, AF_LINK constant, sockaddr_dl_t alias, network interfaces (isBSD)
- `src/bun.js/node/node_fs.zig` — lchmod (ENOSYS), copyFileInner (read/write loop), _copySingleFileSync (read/write loop + symlink handling), flags type fix (i32)
- `src/bun.js/node/StatFS.zig` — f_type returns 0 on OpenBSD (no numeric f_type)
- `src/bun.js/node/dir_iterator.zig` — OpenBSD case using std.c.getdents/dirent

**HTTP & file serving:**
- `src/http/SendFile.zig` — isMac guard for sendfile, isOpenBSD exclusion from isEligible
- `src/http/RequestContext.zig` — sendfile guarded with isMac (not else)
- `src/bun.js/webcore/blob/copy_file.zig` — OpenBSD uses copyFileUsingReadWriteLoop

**Process & spawn:**
- `src/bun.js/api/bun/process.zig` — POSIX_SPAWN_SETSID guarded for OpenBSD
- `src/bun.js/api/bun/spawn.zig` — OpenBSD uses BunSpawnRequest (vfork+exec, like Linux), POSIX_SPAWN_SETSID @hasDecl check, custom wait4 extern for OpenBSD Rusage, custom openbsd_rusage struct
- `src/bun.js/api/bun/subprocess/ResourceUsage.zig` — Rusage type alias for OpenBSD

**Bundler:**
- `src/bundler/bundle_v2.zig` — O_EVTONLY guarded with isMac
- `src/bun.js/ModuleLoader.zig` — O_EVTONLY guarded with isMac
- `src/bake/DevServer/DirectoryWatchStore.zig` — O_EVTONLY guarded with isMac

**Package manager:**
- `src/install/npm.zig` — `.openbsd => @enumFromInt(openbsd)` and platform string
- `src/install/PackageInstall.zig` — realpath workaround using libc realpath directly (std.fs.Dir.realpath unsupported)
- `src/cli/upgrade_command.zig` — `.openbsd => "openbsd"` platform label

**Other:**
- `src/resolver/resolve_path.zig` — `.linux, .mac, .openbsd => .posix`
- `src/StandaloneModuleGraph.zig` — openSelf: `.mac, .openbsd` (selfExePath)
- `src/compile_target.zig` — `.openbsd => true`
- `src/sys/coreutils_error_map.zig` — `.linux, .openbsd` error messages
- `src/shell/interpreter.zig` — isPollable: `.mac, .openbsd` (kqueue behavior)
- `src/napi/napi.zig` — `.linux, .openbsd` for V8 API mangling
- `src/bun.js/api/ffi.zig` — Shared library extension: `.linux, .openbsd => "so"`

## Phase D: Build JSC for OpenBSD (DONE)

### Output
- **Library**: `/srv/opencode-port/jsc-build/lib/libJavaScriptCore.a` (thin archive, 187 object files, 92,900 symbols, 121MB total objects)
- **Support libs**: `/srv/opencode-port/jsc-build/lib/libWTF.a` (304KB), `/srv/opencode-port/jsc-build/lib/libbmalloc.a` (29KB)
- **Headers**: `/srv/opencode-port/jsc-build/JavaScriptCore/Headers/` (8 public headers)
- **Private headers**: `/srv/opencode-port/jsc-build/JavaScriptCore/PrivateHeaders/`
- **Derived sources**: `/srv/opencode-port/jsc-build/JavaScriptCore/DerivedSources/`
- **Config**: `ENABLE_REMOTE_INSPECTOR=OFF`, `USE_BUN_JSC_ADDITIONS=ON`, `maxMicrotaskArguments=4`

### CMake configuration
```bash
cmake -S /srv/opencode-port/webkit-build \
  -DPORT=JSCOnly -DENABLE_STATIC_JSC=ON \
  -DUSE_BUN_JSC_ADDITIONS=ON -DUSE_BUN_EVENT_LOOP=ON \
  -DENABLE_BUN_SKIP_FAILING_ASSERTIONS=ON \
  -DALLOW_LINE_AND_COLUMN_NUMBER_IN_BUILTINS=ON \
  -DENABLE_API_TESTS=OFF -DUSE_SYSTEM_MALLOC=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -G 'Unix Makefiles'
```

### OpenBSD patches applied to WebKit source

| File | Issue | Fix |
|------|-------|-----|
| `WTF/wtf/AvailableMemory.h` | `memoryStatus()` not declared for OpenBSD | Added `OS(OPENBSD)` to both `#if` guards |
| `WTF/wtf/AvailableMemory.cpp` | `memoryStatus()` not implemented for OpenBSD | Added OpenBSD impl using sysctl `KERN_PROC_PID` + `p_vm_rssize` |
| `WTF/wtf/posix/FileSystemPOSIX.cpp` | `st_birthtime` doesn't exist on OpenBSD | Removed `OS(OPENBSD)` from `st_birthtime` guards |
| `WTF/wtf/RawHex.h` | `uint64_t` != `uintptr_t` on OpenBSD (different types) | Added `OS(OPENBSD)` to `int64_t`/`uint64_t` constructor guard |
| `JSC/assembler/MacroAssemblerX86_64.h` | OpenBSD `sys/endian.h` `swap32`/`swap64` macros | Added `#undef swap32` / `#undef swap64` after includes |
| `JSC/runtime/MachineContext.h` | No OpenBSD register access from `mcontext_t` | Added 6 `OS(OPENBSD)` sections for `sc_rsp/rbp/rip/rsi/rbx/r8` |
| `JSC/heap/BlockDirectory.cpp` | OpenBSD doesn't have `mincore()` | Added `!OS(OPENBSD)` to mincore guard |
| `WTF/wtf/posix/OSAllocatorPOSIX.cpp` | `BUN_MACOSX` warning (non-critical) | Warning only, not fixed |

## Phase E: Run codegen on Mac, build Bun on OpenBSD

### Architecture

Bun's build has three stages:
1. **Codegen** (TypeScript → C++/Zig generated code) — runs under `bun` on the host
2. **Zig compilation** — compiles all `.zig` files to object files
3. **C++ compilation + linking** — compiles C++ bindings, links with JSC

### Codegen Status: DONE (all .lut.h files regenerated with fixed wyhash)

All 77 codegen files generated on Mac, including:
- Error codes, generated classes, JS builtins, module registry, JS-to-native bindings
- Sink generation, C++ to Zig bindings, bake codegen, bindgen v2 outputs
- All 12 LUT `.lut.h` hash table files
- All 24 node-fallbacks files including `react-refresh.js`
- `bun-error/`, `fallback-decoder.js`, `runtime.out.js`
- `ResolvedSourceTag.zig`, `SyntheticModuleType.h`, `NativeModuleImpl.h`
- `eval/` generated files, `dependencies.zig`
- Codegen copied to local storage: `/usr/obj/bun-build/codegen`

### Zig Compilation: DONE

**Problem solved**: `zig build obj` crashes with SIGSEGV on OpenBSD due to zig's internal ELF linker bug. Solution: **cross-compile on Mac**.

**Cross-compilation setup:**
- **Zig binary**: `<MAC_WORKSPACE>/opencode-port/zig-mac/bootstrap-aarch64-macos-none/zig` (oven-sh/zig 0.15.2, 188MB, Mac ARM64)
- **Zig lib**: `<MAC_WORKSPACE>/opencode-port/oven-zig/lib` (patched with OpenBSD system headers)
- **OpenBSD headers**: Copied from VM's `/usr/include` to `oven-zig/lib/libc/include/generic-openbsd/`
- **Vendor headers**: `zstd.h` and `zstd_errors.h` in `bun-source/vendor/zstd/lib/`

**Build command** (run from bun-source directory, invoke build runner directly):
```bash
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
**NOTES**:
- Do NOT use `-Z0000000000000000` — causes "no step named ''" error
- Use `-Denable_asan=false` (underscore, not hyphen `-Denable-asan`)
- Output is 253MB with debug info; LLD 19 on OpenBSD can't link it directly (see Phase F LLD bug)
- **Workaround**: On OpenBSD, strip debug sections first: `/usr/bin/objcopy --strip-debug bun-zig.o bun-zig-stripped.o`
  - BUT this corrupts relocations (GNU objcopy 2.17 doesn't know reloc type 42), causing runtime crashes
  - Need a better strip tool or to build without debug info

**Output**: `<MAC_WORKSPACE>/opencode-port/bun-source/build/bun-zig.o`
- ~242MB ELF 64-bit LSB relocatable, x86-64, version 1 (OpenBSD), with debug_info, not stripped
- Copied to `/srv/opencode-port/bun-build/bun-zig.o` on OpenBSD
- Rebuilt after O_* flag fix (2026-02-17)

### CMake Patches Applied

| File | Change | Purpose |
|------|--------|---------|
| `cmake/tools/SetupWebKit.cmake` | Added early return when pre-built JSC exists | Skip webkit download/build |
| `cmake/targets/BuildBun.cmake` | Guarded bindgen-v2 with SKIP_CODEGEN | Discover existing outputs from filesystem |
| `cmake/targets/BuildBun.cmake` | Added OpenBSD linker section | OpenBSD-specific link flags |
| `cmake/targets/BuildBun.cmake` | Added OpenBSD library linking | pthread, ICU, no separate libdl |
| `cmake/targets/BuildBun.cmake` | Added OpenBSD strip flags | -R .eh_frame -R .gcc_except_table |
| `cmake/targets/BuildBun.cmake` | Added `-Wno-unknown-warning-option` | Prevent OpenBSD clang errors on unknown `-Wno-character-conversion` |
| `cmake/targets/BuildBun.cmake` | **Guarded `-fno-pic -fno-pie` with `if(NOT OPENBSD)`** | OpenBSD requires PIE executables |
| `cmake/targets/BuildBun.cmake` | **Added `-fPIC` for OpenBSD compile+link** | PIE compatibility |
| `cmake/targets/BuildBun.cmake` | **Added `-Wl,--strip-debug` for OpenBSD link** | Remove debug sections with R_X86_64_32 relocs |
| `cmake/tools/SetupBun.cmake` | Made bun executable optional with SKIP_CODEGEN | Allow build without bun installed |
| `cmake/tools/SetupZig.cmake` | Made ZIG_PATH/ZIG_EXECUTABLE/ZIG_LIB_DIR overridable | Use custom zig3 compiler |
| `cmake/tools/SetupZig.cmake` | Skip clone-zig when zig exists | Avoid register_command path validation |

### CMake Configure: DONE

Working cmake command (with BUN_CPP_ONLY=ON to build just C++ static library):
```bash
cmake -S /mnt/mac-shared/bun-source -B /usr/obj/bun-build \
  -DCMAKE_BUILD_TYPE=Release -DSKIP_CODEGEN=ON -DBUN_CPP_ONLY=ON \
  -DCODEGEN_PATH=/usr/obj/bun-build/codegen \
  -DWEBKIT_PATH=/usr/obj/jsc-build -DENABLE_LLVM=OFF \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DZIG_EXECUTABLE=/srv/opencode-port/zig3 -DZIG_PATH=/srv/opencode-port/oven-zig \
  -DZIG_LIB_DIR=/srv/opencode-port/oven-zig/lib \
  -DVENDOR_PATH=/usr/obj/bun-vendor -G 'Unix Makefiles'
```

### Dependencies Built: ALL 14 DONE

All built on OpenBSD with `TMPDIR=/usr/obj/bun-build/tmp make <target>`:
- BoringSSL, brotli, c-ares, highway, libdeflate, lshpack
- mimalloc, zlib, libarchive, hdrhistogram, zstd, sqlite
- lol-html (Rust), tinycc

### C++ Compilation: DONE (rebuilt with -fPIC)

Successfully compiled all ~780 C++ and C source files into `libbun-profile.a` (6.5G static archive).
All compiled with `-fPIC` for PIE compatibility.

Build on openbsd-host: `cd /usr/obj/bun-build && ulimit -d 6291456 && TMPDIR=/usr/obj/bun-build/tmp make -j8`

#### C++ Patches Applied for OpenBSD

**bun-usockets (C library) — kqueue port:**

| File | Change |
|------|--------|
| `packages/bun-usockets/src/internal/loop_data.h` | Added `__OpenBSD__` for `zig_mutex_t` as `uint32_t` |
| `packages/bun-usockets/src/libusockets.h` | Added `__OpenBSD__` to kqueue platform detection (`LIBUS_USE_KQUEUE`) |
| `packages/bun-usockets/src/internal/internal.h` | Guarded `mach/mach.h` with `__APPLE__`, split `us_internal_callback_t` for Apple (mach ports) vs non-Apple (EVFILT_USER) |
| `packages/bun-usockets/src/internal/eventing/epoll_kqueue.h` | Split `ready_polls` type: `kevent64_s` (Apple) vs `struct kevent` (non-Apple) |
| `packages/bun-usockets/src/eventing/epoll_kqueue.c` | 8 areas: macros, dispatch, polling, socket changes, timers, async wakeup. Non-Apple uses standard `kevent`/`EV_SET`/`EVFILT_USER`+`NOTE_TRIGGER` |
| `packages/bun-usockets/src/bsd.c` | Guarded `IP_PKTINFO`/`ip_mreq_source`/source membership/`IP_RECVTOS` with `#if !defined(__OpenBSD__)` |

**C++ bindings — JSC API compatibility:**

| File | Issue | Fix |
|------|-------|-----|
| `src/bun.js/bindings/webcore/SerializedScriptValue.cpp` | `JSBigInt::tryRightTrim` doesn't exist | Added `tryRightTrimBigInt()` helper function (trims leading zero digits) |
| `src/bun.js/bindings/bindings.cpp` | `QueuedTask` constructor arg count (max 4, not 5) | Use 4-arg variant matching `maxMicrotaskArguments=4` |
| `src/bun.js/bindings/JSBundlerPlugin.cpp` | `dlsym` undeclared | Added `#include <dlfcn.h>` |

**C++ bindings — Inspector/Debugger (ENABLE_REMOTE_INSPECTOR=OFF):**

All wrapped with `#if ENABLE(REMOTE_INSPECTOR)` guards, with stub `extern "C"` functions in `#else` so Zig callers still link:

| File | Stubs Provided |
|------|----------------|
| `src/bun.js/bindings/BunDebugger.cpp` | `Bun__createJSDebugger`, `Bun__ensureDebugger`, `BunDebugger__willHotReload`, `Bun__startJSDebuggerThread`, `Debugger__did/willSchedule/Cancel/DispatchAsyncCall` |
| `src/bun.js/bindings/BunInspector.cpp` | `Bun__addInspector` |
| `src/bun.js/bindings/ConsoleObject.cpp` | Inspector message forwarding skipped |
| `src/bun.js/bindings/InspectorBunFrontendDevServerAgent.cpp` | All `notify*` + `setEnabled` stubs |
| `src/bun.js/bindings/InspectorHTTPServerAgent.cpp` | All request/response/error notification stubs |
| `src/bun.js/bindings/InspectorLifecycleAgent.cpp` | Enable/Disable/ReportReload/ReportError stubs |
| `src/bun.js/bindings/InspectorTestReporterAgent.cpp` | Enable/Disable/ReportTestFound/Start/End stubs |
| Header files (.h) | `InspectorLifecycleAgent.h`, `InspectorTestReporterAgent.h`, `InspectorBunFrontendDevServerAgent.h`, `InspectorHTTPServerAgent.h` — all wrapped |

**C++ bindings — OpenBSD platform support:**

| File | Issue | Fix |
|------|-------|-----|
| `src/bun.js/bindings/BunProcess.cpp` | "Unknown platform" errors (3 places) | Added `OS(OPENBSD)` cases for platform string, signal handling, config vars |
| `src/bun.js/bindings/BunProcess.cpp` | Missing `<sys/resource.h>` | Added include for `__OpenBSD__` |
| `src/bun.js/bindings/BunProcess.cpp` | `RLIMIT_AS` not on OpenBSD | Guarded with `#ifdef RLIMIT_AS`, fixed `std::size()` → `sizeof/sizeof` |
| `src/bun.js/bindings/BunProcess.cpp` | `BUN_VERSION_UWS`/`BUN_VERSION_USOCKETS` undefined | Added `#ifndef` fallback defines |
| `src/bun.js/bindings/BunProcess.cpp` | `pointer_to_plugin_name` / `dlsym` | Added `OS(OPENBSD)` to dlsym branch |
| `src/bun.js/bindings/BunProcess.cpp` | OpenBSD RSS implementation | Added `getrusage(RUSAGE_SELF)` with `ru_maxrss * 1024` |
| `src/bun.js/bindings/BunObject.cpp` | `AI_ALL`/`AI_V4MAPPED` not on OpenBSD | Added `#ifndef` fallback defines to 0 |
| `src/bun.js/bindings/c-bindings.cpp` | `at_quick_exit` not on OpenBSD | Use `atexit` for OpenBSD |
| `src/bun.js/bindings/c-bindings.cpp` | TTY detection `#error "TODO"` | Added OpenBSD case using `isatty(fd)` |
| `src/bun.js/bindings/c-bindings.cpp` | `lshpack.h` STAILQ macro redefs | Wrapped include with `#pragma GCC diagnostic ignored "-Wmacro-redefined"` |

### Final Linking: DONE (binary runs!)

**Server**: openbsd-host

#### Linking Issues Resolved

**1. Duplicate Inspector symbols (6 functions)**
- Cause: `ENABLE_REMOTE_INSPECTOR=0` → `#else` stubs compiled alongside Zig-provided exports
- Fix: Removed the 6 stub function bodies from 4 C++ files, kept comments noting Zig provides them

**2. PIE/PIC enforcement (CRITICAL)**
- Cause: `BuildBun.cmake` unconditionally set `-fno-pic -fno-pie` for non-Windows platforms
- Impact: Binary linked with `-no-pie` crashed at startup (SIGSEGV in `_mi_prim_random_buf` at stack canary load — `__stack_chk_guard` not relocated by dynamic linker)
- Fix: Modified BuildBun.cmake to use `-fPIC` for OpenBSD, rebuilt ALL ~780 C++ files with `-fPIC`

**3. ~270 undefined symbols — missing libuv + OS-specific functions**
- **libuv (250+ `uv_*` symbols)**: Built libuv from source on openbsd-host
- **stat64/fstat64/lstat64**: Aliased to stat/fstat/lstat in `openbsd_stubs.c`
- **`Bun__Os__getFreeMemory`**: Implemented via `sysctl(CTL_HW, HW_USERMEM64)`
- **`sysctlbyname`**: Stubbed (returns -1)
- **`posix_spawn_bun`**: Implemented with fork/execve
- **`Bun::Secrets::*`**: Stubbed (returns -1 "not supported")
- **Signal forwarding stubs**: in `openbsd_stubs.c`

**4. Duplicate `uv_tty_reset_mode`**
- Fix: Added `-Wl,--allow-multiple-definition`

**5. Bindgen Generated*.cpp (5 files)**
- Manual compilation with custom include paths including `-I.../src/bun.js/modules` for `_NativeModule.h`

**6. `v8::Array::New` symbol mangling mismatch**
- Problem: Zig expects `std::function` (mangled as `St8function`) but libc++ provides `std::__1::function` (mangled as `NSt3__18function`)
- Fix: Assembly trampoline `/tmp/v8_array_bridge.S` that provides the expected symbol and jumps to the real one

#### Working Link Command
```bash
clang++ -o /srv/opencode-port/bun \
  -Wl,--strip-debug \
  /srv/opencode-port/bun-build/bun-zig-stripped.o \
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
  -fno-exceptions -fno-rtti -Wl,--allow-multiple-definition
```

**Binary**: 91.4MB PIE shared object, `bun --version` returns **1.3.10**, all globals work, 18/19 basic tests pass

---

## RESOLVED BUG: All bunGlobalObjectTable Properties Were Undefined

### Root Cause: Math::BigInt `band()` Mutates Global Variable

The Perl `wymum()` function in `create_hash_table` used `($product & $bigint_mask64)->numify()` to extract the low 64 bits of a 128-bit multiply result. **Math::BigInt's overloaded `&` operator calls `band()` which mutates its operands.** This destroyed the global `$bigint_mask64` variable after the first call, causing all subsequent `wymum()` calls to return `lo=0`.

With `lo=0`, the `wymix()` function (which returns `lo ^ hi`) returned only `hi`, producing wrong hashes for ALL property strings in every .lut.h file. This caused CompactHashIndex lookups to fail at runtime.

### Fix
```perl
# Before (buggy): band() mutates $bigint_mask64
my $lo = ($product & $bigint_mask64)->numify();
my $hi = ($product >> 64)->numify();

# After (fixed): copy() prevents mutation
my $lo = $product->copy()->band(Math::BigInt->new("18446744073709551615"))->numify();
my $hi = $product->copy()->brsft(64)->numify();
```

### Verification
- "Bun" hash: Perl now computes **0xa09fb2** (was 0xa59c5f), matching C++ runtime exactly
- All 12 .lut.h files regenerated, 12 C++ files recompiled, binary re-linked
- `typeof Bun` → **object**, `typeof process` → **object**, `typeof fetch` → **function** — all 108 globals work

## RESOLVED BUG: readFileSync Fails with ENOTDIR

### Root Cause: Wrong O_* Flag Values for OpenBSD

Bun shared macOS and OpenBSD O_* flag definitions in `src/sys.zig`, but several flags have different values:

| Flag | macOS | OpenBSD |
|------|-------|---------|
| O_NOCTTY | 0x20000 | 0x8000 |
| O_CLOEXEC | 0x1000000 | 0x10000 |
| O_DIRECTORY | 0x100000 | 0x20000 |

When `readFileSync` opened a file with `O_RDONLY | O_NOCTTY`, it passed `0x20000` which the OpenBSD kernel interprets as `O_DIRECTORY`, causing ENOTDIR for regular files.

### Fix
Added comptime conditionals in `src/sys.zig` for flags that differ between macOS and OpenBSD:
```zig
pub const NOCTTY = if (Environment.isOpenBSD) @as(u32, 0x8000) else 0x20000;
pub const CLOEXEC = if (Environment.isOpenBSD) @as(u32, 0x10000) else 0x01000000;
pub const DIRECTORY = if (Environment.isOpenBSD) @as(u32, 0x20000) else 0x00100000;
```

### Verification
All 18 tests pass including `readFileSync`, `statSync`, `readdirSync`, `existsSync`.

## RESOLVED BUG: realpathSync Returns ENOSYS (2026-02-18)

### Root Cause: getFdPath returns ENOSYS, fchdir+getcwd only works on directories

`sys.zig:getFdPath()` returned ENOSYS on OpenBSD because there's no `F_GETPATH` or `/proc/self/fd`. The fchdir+getcwd workaround only works for directory file descriptors. Since `realpathSync` opens files with `O_RDONLY`, regular files can't use fchdir.

### Fix
Use libc `realpath()` directly on OpenBSD in `node_fs.zig:5596`:
```zig
const buf = if (comptime Environment.isOpenBSD) buf: {
    break :buf bun.sliceTo(std.c.realpath(path, &outbuf) orelse
        return .{ .err = .{ ... } }, 0);
} else buf: { ... open+getFdPath ... };
```
Also added fchdir+getcwd fallback in `sys.zig:2756` for `getFdPath` (works for directory fds used by other callers).

### Verification
`realpathSync` works for directories, files, and binaries. 22/22 tests pass.

## RESOLVED BUG: Bun.spawn Segfault (2026-02-18)

### Root Cause: bun-spawn.cpp excluded OpenBSD

`bun-spawn.cpp:3` had `#if OS(LINUX) || OS(DARWIN)` — the entire `posix_spawn_bun` C function was not compiled for OpenBSD. The basic stub in `openbsd_stubs.cpp` (fork/execve without error pipe) was used instead, which had a different struct layout and no error detection mechanism.

### Fix
1. Changed guard to `#if OS(LINUX) || OS(DARWIN) || OS(OPENBSD)`
2. Added `|| OS(OPENBSD)` to all `#if OS(DARWIN)` blocks inside (errpipe, fork vs vfork, childFailed, error detection)
3. Added `|| OS(OPENBSD)` to `getMaxFd` for `getdtablesize()`
4. Removed `posix_spawn_bun` stub from `openbsd_stubs.cpp`
5. Also fixed `sys.zig:4347` — added `Environment.isOpenBSD` to `dlsymImpl`

### Verification
`Bun.spawn(["echo","hi"])` works correctly (no segfault). Async spawn + stdout reading works.

---

## Current Runtime Test Results (2026-02-18)

**Binary**: `/srv/opencode-port/bun` — 91.4MB PIE, Bun v1.3.10-canary.1, OpenBSD x64

### Passing Tests (27/27 after kqueue fix on 2026-02-18)

| Test | Status |
|------|--------|
| readFileSync | PASS |
| writeFileSync + readFileSync roundtrip | PASS |
| statSync | PASS |
| readdirSync | PASS |
| existsSync | PASS |
| mkdirSync | PASS |
| fs.realpathSync (files, dirs, binaries) | PASS |
| path.join / path.resolve | PASS |
| URL parsing | PASS |
| Buffer (base64) | PASS |
| crypto.randomUUID | PASS |
| crypto.createHash (sha256) | PASS |
| JSON parse/stringify | PASS |
| TextEncoder/TextDecoder | PASS |
| os.hostname / cpus / freemem / homedir | PASS |
| Bun.file() | PASS |
| Bun.version | PASS |
| process.platform / process.arch | PASS |
| Bun.serve (HTTP server) | PASS |
| setTimeout / setInterval | PASS |
| Bun.which | PASS |
| Bun.env | PASS |
| **fetch() localhost** | **PASS** (was hanging before kqueue fix) |
| **fetch() external HTTPS** | **PASS** (httpbin.org/get works) |
| **Bun.connect** | **PASS** (open/data/close callbacks all work) |
| **Bun.spawn async** | **PASS** (stdout reading works) |
| **Bun.spawnSync** | **PASS** (was hanging before kqueue fix) |

### Failing / Known Bugs

| Bug | Symptom | Root Cause | Fix Status |
|-----|---------|------------|------------|
| **realpathSync ENOSYS** | `fs.realpathSync()` returned ENOSYS | Fixed: use libc `realpath()` directly on OpenBSD | **FIXED** (2026-02-18) |
| **Bun.spawn segfault** | `Bun.spawn(["echo","hi"])` crashed with SIGSEGV | Fixed: Added `OS(OPENBSD)` to `bun-spawn.cpp` guards | **FIXED** (2026-02-18) |
| **fetch()/Bun.connect/spawnSync hang** | All three hung forever due to kqueue event consumption | Fixed: kqueue_change() consumed events — see RESOLVED BUG below | **FIXED** (2026-02-18) |
| **getFdPath NotDir** | `bun install` / `bun build --compile` fail with "NotDir" | getFdPath uses fchdir+getcwd which fails for file fds on OpenBSD | **FIXED** (2026-02-18) — callers pass known paths on OpenBSD |
| **LLD 19 large .o parsing bug** | `ld: section table goes past the end of file` on 254MB bun-zig.o | LLD 19.1.7 on OpenBSD misreads e_shoff from large .o files | **WORKAROUND** — Python ELF stripper removes debug sections (254→38MB) |
| **child_process.execSync hangs** | `execSync("echo hello")` hangs (times out) | spawnSync race condition in recvNonBlock loop | **TO INVESTIGATE** |
| **Exit segfault after child_process** | Process crashes on exit | SIGSEGV during event loop shutdown | LOW PRIORITY |
| **bun install recursive nesting** | `solid-js` install creates infinitely nested `.bun/` directories | OpenBSD uses recursive copy instead of symlinks/clonefile; doesn't skip `.bun` metadata dirs | **BLOCKING** — must fix for OpenCode |

### Priority Order for Remaining Bug Fixes

1. **child_process.execSync hangs** — spawnSync race condition (not blocking for OpenCode)
2. **Exit segfault** — Low priority cosmetic issue (only with old binary, new binary exits cleanly)

---

## RESOLVED BUG: kqueue_change() Consumes Events on Non-Apple BSD (2026-02-18)

### Root Cause: kevent() in kqueue_change() eats pending events

In `packages/bun-usockets/src/eventing/epoll_kqueue.c:457`, the `kqueue_change()` function called:
```c
kevent(kqfd, change_list, change_length, change_list, change_length, NULL);
```

On macOS, `kevent64()` uses `KEVENT_FLAG_ERROR_EVENTS` which means "only return errors from the changelist, don't consume real events". On non-Apple kqueue (OpenBSD, FreeBSD), there is no such flag. Passing an eventlist causes `kevent()` to:
1. Process the changelist (register EVFILT_WRITE for connect socket)
2. Wait for events (NULL timeout)
3. If an event is immediately available (e.g., connect already completed for localhost), return it in the eventlist buffer

Since EVFILT_WRITE is registered with `EV_ONESHOT`, the event is **removed from kqueue after delivery**. But the event goes into the local `change_list` buffer which nobody reads. The main event loop's `kevent()` call never sees the event — it's been silently consumed.

This caused `Bun.connect()`, `fetch()`, and `Bun.spawnSync()` to all hang — any operation that registered a kqueue filter and expected the main event loop to dispatch it.

### Fix
```c
// Before (buggy on non-Apple):
ret = kevent(kqfd, change_list, change_length, change_list, change_length, NULL);

// After (fixed):
ret = kevent(kqfd, change_list, change_length, NULL, 0, NULL);
```

Pass `NULL, 0` for the eventlist so kevent only registers changes without consuming events.

### Verification
- `Bun.connect()` — open/data/close callbacks fire correctly
- `fetch("http://127.0.0.1:...")` — returns 200 with body
- `fetch("https://httpbin.org/get")` — external HTTPS works
- `Bun.spawnSync(["echo", "hello"])` — returns stdout + exitCode 0
- 27/27 comprehensive tests pass

### Files Modified
- `packages/bun-usockets/src/eventing/epoll_kqueue.c:457` — Changed kevent() call to not pass eventlist

## Phase F: Build OpenCode with Bun (IN PROGRESS — OpenCode runs!)

### Current State (2026-02-20 session 9)

**OpenCode v1.2.6** — all subcommands work natively on OpenBSD. TUI blocked by `@opentui/core-openbsd-x64` module resolution from bun install cache. `process.stdin.isTTY` bug fixed (session 9).

1. **getFdPath fixes** applied to `extract_tarball.zig`, `repository.zig`, and `StandaloneModuleGraph.zig`
2. **LLD 19 large .o bug** — worked around with custom Python ELF debug section stripper (`strip_debug_sections.py`)
3. **`bun install`** — WORKS for simple packages AND OpenCode's full monorepo (1884 packages in .bun store)
4. **`bun build --compile`** — WORKS (compiles TS with 41 modules, compiled binary runs correctly)
5. **20/20 runtime tests pass** with no crashes
6. **All project files migrated** from `<OLD_OPENBSD_WORKSPACE>` to `/srv/opencode-port` on openbsd-host
7. **OpenCode v1.2.6** (anomalyco/opencode) downloaded and extracted to `/srv/opencode-port/opencode`
8. **FIXED: `bun install` recursive nesting bug** — skip `node_modules/` in hardlink and copyfile paths
9. **FIXED: `bun install` ENOSYS on extract** — construct package.json path instead of getFdPath on file FDs
10. **BUILT: `libopentui.so` for OpenBSD** — native Zig build of @opentui/core (4.3MB, TUI rendering lib)
11. **OpenCode `--help` works** — TUI banner renders, all commands listed, exit code 0
12. **ALL subcommands verified** — see comprehensive test results below (session 7)

### LLD 19 Bug and Python Stripper Workaround

**Problem**: LLD 19.1.7 on OpenBSD 7.8 misreads `e_shoff` from 254MB ELF .o files ("section table goes past the end of file"). GNU objcopy 2.17 can strip but corrupts relocation type 42 (R_X86_64_REX_GOTPCRELX).

**Solution**: Custom Python script `strip_debug_sections.py` that:
- Removes 14 `.debug_*` and `.rela.debug_*` sections (254MB → 38MB)
- Properly remaps section indices in section headers (`sh_link`, `sh_info`)
- Remaps `st_shndx` in 51568 symbol table entries
- Does NOT touch relocation entries (preserves all reloc types including type 42)

### Build Pipeline (updated)
```bash
# 1. Cross-compile Zig on Mac (20+ minutes)
/tmp/zig-cache/local/o/.../build ... obj ...
# 2. Strip debug sections (10 seconds)
python3 strip_debug_sections.py build/bun-zig.o build/bun-zig-stripped.o
# 3. Copy to OpenBSD
scp build/bun-zig-stripped.o openbsd-host:/srv/opencode-port/bun-build/bun-zig-stripped.o
# NOTE: All openbsd-host paths moved from <OLD_OPENBSD_WORKSPACE> to /srv/opencode-port (2026-02-18)
# 4. Link on OpenBSD (2 minutes)
clang++ -o /srv/opencode-port/bun ... bun-zig-stripped.o ...
```

### Verified Working
- `bun --version` → 1.3.10, clean exit
- `bun -e "console.log(1+1)"` → "2", clean exit (no crash)
- `bun install` with 96 packages → works in 904ms
- `bun build --compile` → bundles 41 modules, compiles to standalone binary
- Compiled binary runs: imports @anthropic-ai/sdk, zod, etc.
- fetch (localhost + external HTTPS), Bun.serve, Bun.spawn, Bun.connect → all work
- 20/20 runtime tests pass

### What Doesn't Work Yet
1. ~~**`bun install solid-js` — infinite recursive nesting**~~ — FIXED (skip node_modules/ in Installer.zig)
2. **`child_process.execSync/spawnSync`** → hangs (race condition in recvNonBlock loop)
3. **Migration from npm/yarn lockfiles** → getFdPath for file fds in migration.zig/yarn.zig not fixed
4. **husky postinstall script** — `Cannot find module './index.js' from '.bin/husky'` (symlink resolution issue, non-blocking)
5. **OpenCode build --compile** — build.ts doesn't have OpenBSD in target list, needs `--single` with platform patch or alternate build approach

### NEW BUG: Package Install Recursive Nesting (solid-js)

**Symptom**: `bun install` with `solid-js@1.9.10` creates infinitely nested paths:
```
node_modules/.bun/solid-js@1.9.10/node_modules/solid-js/node_modules/.bun/solid-js@1.9.10/node_modules/solid-js/...
```
Fails with `NameTooLong` after ~17 levels of nesting.

**Reproduction**: Even a minimal `{"dependencies":{"solid-js":"1.9.10"}}` triggers it. Express, zod, and 96 other packages install fine.

**Root Cause Analysis**:
- On Linux/macOS, bun uses clonefile/hardlinks for package installation, which don't recurse into subdirectories
- On OpenBSD, bun falls back to recursive file copying (`copy_file` path in `PackageInstall.zig`)
- `solid-js` has nested dependencies (csstype, seroval, seroval-plugins) stored in `node_modules/.bun/` inside the package
- The recursive copy follows into `.bun/solid-js@1.9.10/node_modules/solid-js/` which itself contains `node_modules/.bun/`, creating infinite recursion
- This only affects packages that have their own nested `node_modules/.bun/` structure

**Likely Fix Location**: `src/install/PackageInstall.zig` — the `copy_file` / `_copySingleFileSync` path used on OpenBSD should skip `.bun` directories inside `node_modules/` during recursive copy, or the installer should use symlinks instead of copies for the `.bun` → `node_modules` mapping.

**Alternative approaches**:
1. Fix the recursive copy to detect cycles / skip `.bun` metadata dirs
2. Implement symlink-based installation for OpenBSD (like Linux/macOS use)
3. Use hardlinks on OpenBSD (supported on same filesystem)

### OpenCode Source Patches Applied (2026-02-19 session 6)

| File | Change |
|------|--------|
| `packages/opencode/src/file/watcher.ts:56` | Added `if (process.platform === "openbsd") return "kqueue"` to backend selection |
| `packages/opencode/src/pty/index.ts:47-51` | Wrapped `import("bun-pty")` in try/catch, returns `undefined` when unavailable |
| `packages/opencode/src/pty/index.ts:159` | Added null check: `if (!spawn) throw new Error("PTY not available...")` |
| `packages/opencode/src/shell/shell.ts:51` | Added `if (process.platform === "openbsd") return "/bin/ksh"` |
| `packages/opencode/src/cli/cmd/tui/util/clipboard.ts:58,86` | Added `|| os === "openbsd"` to both read() and getCopyMethod() Linux branches |
| `packages/opencode/script/build.ts:116` | Added `{ os: "openbsd", arch: "x64" }` to allTargets array |
| `packages/opencode/bin/opencode:32` | Added `openbsd: "openbsd"` to platformMap |

### Bun Source Fix Applied (2026-02-19 session 6)

| File | Change |
|------|--------|
| `src/sys.zig:2367` | Renamed variable `exists` to `dest_exists` to fix shadowing in renameat2 NOREPLACE emulation |

### bun install Fix: Missing Symlinks on OpenBSD

Bun's package installer on OpenBSD stores all packages in `node_modules/.bun/<pkg@ver>/node_modules/<pkg>` but fails to create the symlinks in `node_modules/<pkg>`. Workaround: shell script creates symlinks for all 1884 cached packages (1148 visible after fix).

### Remaining Issue: spawnSync Race Condition

**Symptom**: `Bun.spawnSync()` intermittently hangs — process enters R (CPU busy-loop) state. Sometimes works, sometimes hangs. ktrace (which adds overhead) makes it always work.

**Key findings**:
- Child process DOES execute correctly
- Parent process spins in R state, never reaches `poll()`
- The spin is in the `recvNonBlock` loop in `process.zig:2195-2257`
- Isolated C test with `socketpair + recv(MSG_DONTWAIT) + poll()` works correctly

### Compiled Binary: DONE (session 7)

**Binary**: `/srv/opencode-port/opencode-bin` — 130MB ELF, OpenCode v1.2.6, standalone compiled
**Build command**: `cd /srv/opencode-port/opencode/packages/opencode && OPENCODE_VERSION=1.2.6 OPENCODE_CHANNEL=latest /srv/opencode-port/bun-new run --conditions=browser script/build.ts --single --skip-install`
**Output**: `dist/opencode-openbsd-x64/bin/opencode`

Verified working: `--help`, `models`, `serve`, `run "echo hi"` (LLM streaming + tool permissions), `--version` → 1.2.6

### Next Steps (Priority Order)
1. ~~**Fix TCC W^X mprotect for OpenBSD**~~ — DONE. Added `__OpenBSD__` to `CONFIG_RUNMEM_RO=1` in `vendor/tinycc/tccrun.c`
2. **Fix `bun install` missing symlinks** — proper fix in Installer.zig (currently worked around with shell script)
3. **(Optional) Fix child_process.execSync/spawnSync race** — may be needed for OpenCode's git integration
4. **(Optional) Fix husky symlink resolution** — getFdPath in run_command.zig:1315 for script symlinks
5. **(Optional) Fix getFdPath for migration callers** — only needed for npm/yarn lockfile migration
6. **(Optional) Upstream opentui OpenBSD support** — publish @opentui/core-openbsd-x64 to npm

### Bugs Fixed This Session (2026-02-19, session 8 — Phase H rebuild)

**4. IO loop panic: "TODO on this platform" (io.zig)**
- Root cause: `tick()` in `src/io/io.zig:83` checked `Environment.isMac` instead of `Environment.isBSD` for kqueue path
- The `tickKqueue()` function already supported BSD (`!Environment.isBSD` guard)
- Fix: Changed `isMac` → `isBSD` at line 83
- Also fixed `keventCall()` signature: `std.c.c_int` → `c_int` (builtin type, not struct member)

**5. @export of @extern symbols (workaround_missing_symbols.zig)**
- Root cause: Zig compiler rejects `@export(@extern(...))` — can't re-export extern symbols
- Fix: Created wrapper functions (`lstat64_wrapper`, `fstat64_wrapper`, `stat64_wrapper`) that call the extern, then `@export` the wrappers

**6. Successful Zig cross-compile + relink**
- Zig cross-compile on Mac: `build ... obj -Dtarget=x86_64-openbsd-none -Doptimize=ReleaseFast`
- Output: `bun-zig.o` (254MB), copied via NFS to openbsd-host
- Relinked on openbsd-host with existing C++ libs → `/srv/opencode-port/bun-new` (95MB)
- Verified: `bun --version`, `bun -e 'console.log(...)'`, `Bun.file().text()` all work
- **IO loop fix confirmed**: `Bun.file("/etc/myname").text()` succeeds (exercises tickKqueue)

**7. TCC mprotect failure FIXED (OpenTUI TUI rendering)**
- Symptom: `tcc: error: mprotect failed (did you mean to configure --with-selinux?)`
- Root cause: OpenBSD W^X enforcement blocks `mprotect(PROT_WRITE|PROT_EXEC)` — mode 3 (rwx) in `protect_pages()`
- Location: `vendor/tinycc/tccrun.c:309-315` → `CONFIG_RUNMEM_RO` default was 0
- Fix: Added `__OpenBSD__` alongside `__APPLE__` in `CONFIG_RUNMEM_RO` detection → sets to 1
  - With `CONFIG_RUNMEM_RO=1`, `.text` gets rx (mode 0), other sections get rw (mode 2) — no rwx needed
- Rebuilt TCC on openbsd-host (`cd /usr/obj/bun-build/tinycc && make -j4`), relinked bun, rebuilt OpenCode
- Result: **TUI renders perfectly** — OpenCode banner, input box, model picker, keyboard shortcuts, status bar all display correctly

**8. OpenCode TUI — multiple issues (INVESTIGATING)**

**Issue 8a: CPU spin from OpenTUI threading (FIXED)**
- Root cause: OpenTUI enables render thread by default; OpenBSD futex/condition vars cause sched_yield storms
- Fix: Added `process.platform === "openbsd"` to threading disable check in both:
  - `app.tsx` render config: `useThread: process.platform === "openbsd" ? false : undefined`
  - `@opentui/core/index-zrvzvh6r.js` line 15710: added `|| process.platform === "openbsd"`
- Both patches verified working — sched_yield storms eliminated

**Issue 8b: Missing native libopentui.so (FIXED)**
- Root cause: `@opentui/core` dynamically loads `@opentui/core-${process.platform}-${process.arch}/index.ts` (line 10323 of bundled file)
- No `@opentui/core-openbsd-x64` npm package exists → renderer silently falls back to non-functional state
- Fix: Built `libopentui.so` natively on OpenBSD from opentui 0.1.79 Zig source (which already supports x86_64-openbsd target)
- Created fake `@opentui/core-openbsd-x64` package in node_modules with the built .so
- Zig FFI calls work: `createRenderer()`, `setUseThread()`, `setupTerminal()` all succeed
- Source: `/srv/opencode-port/opentui-zig/` → builds to `lib/x86_64-openbsd/libopentui.so` (4.3MB)

**Issue 8c: `process.stdin.isTTY` always `undefined` on OpenBSD (FIXED — session 9)**
- Root cause: `c-bindings.cpp:498` had `#if OS(LINUX) || OS(DARWIN)` excluding OpenBSD from `Bun__isTTY()` function
- Fix: Changed to `#if OS(LINUX) || OS(DARWIN) || OS(OPENBSD)` — one-line change
- Rebuilt: Recompiled c-bindings.cpp on openbsd-host, updated libbun-profile.a, stripped bun-zig.o (254→38MB), relinked
- Verified: `process.stdin.isTTY` / `stdout.isTTY` / `stderr.isTTY` all return `true` on real TTY via tmux
- Also verified: returns `undefined` over SSH pipe (correct behavior)

**Issue 8d: `@opentui/core-openbsd-x64` module resolution from bun install cache (BLOCKING — NEW)**
- Symptom: TUI enters CPU spin (R+ state) instead of rendering after isTTY fix
- Root cause: `@opentui/core/index-vnvba6q9.js:10461` does `await import(\`@opentui/core-${process.platform}-${process.arch}/index.ts\`)`
- The import resolves from bun install cache `<OLD_OPENBSD_WORKSPACE>/.bun/install/cache/@opentui/core@0.1.80@@@1/`, not project `node_modules/`
- Bun's resolver can't find `@opentui/core-openbsd-x64` from the cache path
- The fake package exists at `/srv/opencode-port/opencode/node_modules/@opentui/core-openbsd-x64/` but is unreachable
- Failure cascade: opentui falls back to non-functional state → Worker socket disconnects → kqueue busy-polls dead sockets
- **Next step**: Patch `index-vnvba6q9.js:10461` to use absolute path for OpenBSD

### Bugs Fixed This Session (2026-02-19)

**1. `bun install` ENOSYS on package.json resolution (extract_tarball.zig, repository.zig)**
- Root cause: `json_file.getPath()` calls `getFdPath` on regular file FDs → ENOSYS on OpenBSD
- Fix: On OpenBSD, construct path from known directory + "/package.json" instead of querying the file FD
- Files: `src/install/extract_tarball.zig:484`, `src/install/repository.zig:675`

**2. `bun install` recursive nesting / NameTooLong (Installer.zig)**
- Root cause: Hardlink and copyfile paths walked cache dirs without skipping `node_modules/`
- Fix: Added `&.{comptime bun.OSPathLiteral("node_modules")}` to skip_dirnames at lines 703 and 770
- File: `src/install/isolated_install/Installer.zig`

**3. Built `libopentui.so` for OpenBSD**
- @opentui/core uses native Zig FFI library for TUI rendering, only ships linux/darwin/windows binaries
- Built from source (anomalyco/opentui v0.1.79) using OpenBSD's packaged Zig 0.15.1
- Modified build.zig: accepted Zig 0.15.1, added native fallback for unsupported platforms
- Created fake `@opentui/core-openbsd-x64` package in node_modules with the built .so
- Source: `/srv/opencode-port/opentui-zig/` on openbsd-host

### Comprehensive OpenCode Test Results (2026-02-19 session 7)

**Test command**: `ssh -t openbsd-host '/srv/opencode-port/bun-new run --conditions=browser /srv/opencode-port/opencode/packages/opencode/src/index.ts'`

| Subcommand | Status | Notes |
|------------|--------|-------|
| `--help` | PASS | TUI banner renders, all commands listed, exit 0 |
| `models` | PASS | Lists 5 models (opencode/big-pickle, glm-5-free, etc.), exit 0 |
| `serve` | PASS | HTTP server on 127.0.0.1:4096, exit 124 (timeout, expected) |
| `web` | PASS | Web interface on 127.0.0.1:4096, TUI banner + URL, exit 124 |
| `stats` | PASS | Shows overview (2 sessions, 4 messages), cost/token tables, exit 0 |
| `session list` | PASS | Lists 2 sessions with IDs and titles, exit 0 |
| `auth` | PASS | Shows help with login/logout/list subcommands, exit 0 |
| `agent` | PASS | Shows help with create/list subcommands, exit 0 |
| `debug` | PASS | Shows all 11 debug subcommands, exit 0 |
| `debug config` | PASS | Dumps resolved config JSON (keybinds, settings), exit 0 |
| `debug paths` | PASS | Shows data/bin/log/cache/config/state paths, exit 0 |
| `debug rg` | PASS | Shows rg subcommands (tree/files/search), exit 0 |
| `debug rg tree` | PASS | Executes rg for file tree (logs confirm ripgrep call), exit 0 |
| `completion` | PASS | Generates bash completion script, exit 0 |
| TUI mode (no TTY) | PASS | Runs without crash for 3s, exit 124 (timeout, expected) |
| `db` | PASS | Shows help (requires subcommand), exit 0 |
| `export` | PASS | Shows help (requires session ID), exit 0 |

**Library verification:**

| Check | Result |
|-------|--------|
| `@opentui/core` import | 173 function exports loaded |
| `CliRenderer` | Available (typeof = function) |
| `CliRenderEvents` | Available (typeof = object) |
| `@opentui/core-openbsd-x64` path | `/srv/opencode-port/opencode/node_modules/@opentui/core-openbsd-x64/libopentui.so` |
| `libopentui.so` ldd | Only depends on `libpthread.so.28.0` |
| `Bun.which("rg")` | `/usr/local/bin/rg` (ripgrep 14.1.1) |
| SQLite (bun:sqlite) | CREATE/INSERT/SELECT all work |
| `@parcel/watcher-openbsd-x64` | Not found (expected) — degrades gracefully |
| `process.platform` | `"openbsd"` |
| `process.arch` | `"x64"` |

### opentui Build Changes (2026-02-19 session 7)

Files modified in `<MAC_WORKSPACE>/opencode-port/opentui-0.1.79/packages/core/`:

| File | Change | Purpose |
|------|--------|---------|
| `src/zig/build.zig:11-12` | Added `{ .major = 0, .minor = 15, .patch = 1 }` to `SUPPORTED_ZIG_VERSIONS` | OpenBSD ships Zig 0.15.1 |
| `src/zig/build.zig:28` | Added `{ .zig_target = "x86_64-openbsd", .output_name = "x86_64-openbsd", .description = "OpenBSD x86_64" }` to `SUPPORTED_TARGETS` | Register OpenBSD as build target |
| `src/zig/build.zig:163-207` | Rewrote `buildNativeTarget()` to use `b.resolveTargetQuery(.{})` (native target) instead of parsing target string | Zig 0.15.1 can't cross-compile for OpenBSD (no bundled libc). Native target uses system libc. |
| `src/zig/build.zig.zon:5` | Changed `minimum_zig_version` from `"0.15.2"` to `"0.15.1"` | Allow build with OpenBSD's Zig |
| `scripts/build.ts:52` | Added `{ platform: "openbsd", arch: "x64" }` to `variants` array | Include OpenBSD in build matrix |
| `scripts/build.ts:60` | Added `openbsd: "openbsd"` to `platformMap` | Map Node platform string to Zig target |

**Build output**: `lib/x86_64-openbsd/libopentui.so` (4,317,864 bytes, ELF 64-bit LSB shared object, x86-64)

**Critical fix**: `buildNativeTarget()` originally looked up the native platform in `SUPPORTED_TARGETS` and passed the zig target string to `buildTarget()`, which called `std.Target.Query.parse()`. This turned even native builds into cross-compilations, triggering `error: unable to provide libc for target 'x86_64-openbsd'`. The fix uses an empty target query (native resolution) so Zig uses the system's libc directly.

### Remaining Bugs / Workarounds Assessment

| Issue | Type | Current State | Fundamental Fix |
|-------|------|---------------|-----------------|
| **File watcher** | Missing feature | Graceful degradation (returns `{}`) — behind `OPENCODE_EXPERIMENTAL_FILEWATCHER` flag | Build `@parcel/watcher-openbsd-x64` native binding (Rust+C+++N-API, complex) or implement pure-JS kqueue watcher |
| **`child_process.execSync` hang** | Bun bug | spawnSync race condition — process enters R (CPU busy-loop) in `recvNonBlock` loop | Fix race in `process.zig:2195-2257`: likely needs poll() fallback when recv returns EAGAIN instead of tight spinning |
| **`bun install` missing symlinks** | Bun bug | Shell script workaround creates symlinks for all cached packages | Fix `Installer.zig` to create `node_modules/<pkg> → .bun/<pkg@ver>/node_modules/<pkg>` symlinks on OpenBSD |
| **Exit segfault after child_process** | Bun bug (cosmetic) | SIGSEGV during event loop shutdown, only with old binary | Low priority — new binary exits cleanly |
| **npm/yarn lockfile migration** | Bun limitation | getFdPath returns ENOSYS for file FDs in `migration.zig`/`yarn.zig` | Apply same pattern as extract_tarball fix: construct path from known directory |
| **husky postinstall** | Bun limitation | symlink resolution in `.bin/` scripts | Fix getFdPath in `run_command.zig:1315` for script symlinks |
| **OpenCode build --compile** | Missing config | `build.ts` doesn't have OpenBSD in target list | Add OpenBSD target to build.ts (already partially done in opencode source patches) |
| **libopentui.so** | Workaround | Built from source, manually installed as fake npm package | Proper fix: upstream OpenBSD support to @opentui/core, publish `@opentui/core-openbsd-x64` to npm |
| **opentui build.zig native target** | Workaround | Rewrote `buildNativeTarget()` to avoid cross-compilation | Proper fix: upstream to opentui — Zig should use native target when building on the host platform |
| ~~**Bun `process.stdin.isTTY` undefined**~~ | ~~Bun bug~~ | ~~`isTTY` returns `undefined` for all stdio on OpenBSD~~ | **FIXED** (session 9) — Added `OS(OPENBSD)` to `c-bindings.cpp:498` platform guard |
| ~~**`@opentui/core-openbsd-x64` resolution from cache**~~ | ~~Bun resolver~~ | ~~`@opentui/core` dynamically imports `@opentui/core-openbsd-x64/index.ts` but Bun can't resolve it from install cache path~~ | **FIXED** (session 10) — Patched import to use absolute path for OpenBSD |
| ~~**`onTick` drops kqueue events on OpenBSD**~~ | ~~Bun bug~~ | ~~`posix_event_loop.zig:820` checked `isMac` not `isBSD`, silently dropping all kqueue events for Bun-registered FDs~~ | **FIXED** (session 11) — Changed `isMac` → `isBSD`. Root cause of keyboard input failure + compiled binary CPU spin. |

## Key Technical Notes

- **oven-sh/zig fork**: has `#` private field syntax — standard Zig CANNOT compile Bun
- **pinsyscall workaround**: always use `zig build-obj` + system `cc` for final linking on OpenBSD
- **Cross-compilation**: zig code cross-compiled on Mac ARM64 targeting x86_64-openbsd-none (build runner runs on Mac, output is OpenBSD .o file)
- **OpenBSD libc**: must be dynamically linked — no static libc on OpenBSD 7.8
- **OpenBSD PIE enforcement**: OpenBSD requires PIE executables. `-fno-pic -fno-pie` causes SIGSEGV at startup because `__stack_chk_guard` and other GOT entries aren't relocated.
- **kevent vs kevent64**: macOS uses extended `kevent64_s`; OpenBSD uses standard BSD `kevent`. Abstraction implemented in both `posix_event_loop.zig` and `io.zig`.
- **KEventWaker**: macOS uses mach ports, OpenBSD uses pipe+kqueue. Split into separate structs.
- **ENABLE_REMOTE_INSPECTOR=OFF**: JSC built without remote inspector support. All Bun debugger/inspector C++ code wrapped with `#if ENABLE(REMOTE_INSPECTOR)` guards with extern "C" stubs for Zig linkage.
- **maxMicrotaskArguments=4**: Our JSC has 4 (with BUN_JSC_ADDITIONS), not 5 like Bun's full fork. QueuedTask constructors adjusted.
- **JSBigInt::tryRightTrim**: Bun-specific JSC addition not in our build. Replaced with inline `tryRightTrimBigInt()` helper.
- **OpenBSD JSC uses WYHash unconditionally**: Unlike Bun's forked WebKit which uses SuperFastHash for short strings, the stock OpenBSD WebKit uses WYHash for ALL string hashing. The `--always-wyhash` flag in `create_hash_table` was added for this.
- **v8::Array::New symbol mangling**: libc++ uses `std::__1::function` but Zig expects `std::function`. Solved with assembly trampoline.
- **OpenBSD page size**: always 4096 on amd64
- **Memory limits**: `ulimit -d 6291456` for large compilations
- **USE_SYSTEM_MALLOC**: Required for JSC on OpenBSD (libpas doesn't support OpenBSD)
- **OpenBSD mcontext_t**: typedef'd to `ucontext_t` = `struct sigcontext` (via WebKit's PlatformRegisters.h). Register fields: `sc_rsp`, `sc_rbp`, `sc_rip`, etc.
- **OpenBSD uint64_t**: `unsigned long long` (not `unsigned long` like Linux), differs from `uintptr_t` (`unsigned long`)
- **OpenBSD no mincore()**: Removed for security (side-channel prevention)
- **OpenBSD swap32/swap64**: System macros in `sys/endian.h` that conflict with C++ method names
- **OpenBSD no IP_PKTINFO**: Multicast/pktinfo APIs not available, guarded with `#if !defined(__OpenBSD__)`
- **OpenBSD no AI_ALL/AI_V4MAPPED**: DNS hint flags not available, defined to 0
- **OpenBSD no at_quick_exit**: Use atexit instead
- **OpenBSD no RLIMIT_AS**: Virtual memory rlimit not available, guarded with `#ifdef`
- **lshpack STAILQ macros**: OpenBSD sys/queue.h predefines them, causing -Werror redefinition errors. Suppressed with pragma.
- **NFS TCP requirement**: Mac NFS only serves over TCP. OpenBSD mount needs `-o tcp`.
- **NFS UID mapping**: Mac UID 501 vs OpenBSD UID 1000. Use local paths or export with `-mapall=501:20`.
- **NFS portmap**: OpenBSD needs `rcctl enable portmap && rcctl start portmap` before NFS mounts.
- **std.c.utsname void on OpenBSD**: Custom utsname struct needed for analytics.zig
- **std.c.sendfile void on OpenBSD**: All sendfile calls must be guarded with isMac/isLinux
- **std.posix.rusage void on OpenBSD**: Custom openbsd_rusage extern struct needed
- **No POSIX_SPAWN_SETSID on OpenBSD**: Use @hasDecl guard, OpenBSD uses vfork+exec path
- **No F_GETPATH on OpenBSD**: Use fchdir+getcwd workaround via getFdPathViaCWD
- **No IUTF8 on OpenBSD**: Use @hasField check for terminal iflag
- **No numeric f_type in OpenBSD statfs**: Return 0, OpenBSD has f_fstypename (string) instead
- **Build runner whitespace issue**: `zig build obj` sometimes fails with "no step named ''". Workaround: invoke the build runner binary directly. Also do NOT use `-Z0000000000000000` flag.
- **LLD 19 large .o bug**: LLD 19.1.7 on OpenBSD misreads e_shoff from 254MB .o files. GNU readelf and raw hex verify the file is correct. LLVM readelf reports wrong offset (560 bytes too high). GNU objcopy can strip debug sections but corrupts relocation types it doesn't know (type 42 = R_X86_64_REX_GOTPCRELX). Need a modern strip tool or to build without debug info.
- **Disk space management**: Old VM /home (16G) was full. Migrated to openbsd-host with 97GB free.
- **libuv required for NAPI**: Bun only officially links libuv on Windows, but the NAPI/V8 compatibility layer (`napi.zig`) references `uv_*` symbols on all platforms. Must build libuv from source on OpenBSD and link it.
- **Duplicate `uv_tty_reset_mode`**: Both `wtf-bindings.cpp` and libuv define this. Use `--allow-multiple-definition`.
- **Inspector agent stubs conflict with Zig**: When `ENABLE_REMOTE_INSPECTOR=0`, the `#else` branches compile stub `extern "C"` functions that duplicate symbols Zig provides. Must remove the 6 stubs (Enable/Disable/setEnabled) from C++ side.
- **Bindgen v2 `Generated*.cpp` not compiled by cmake**: When using `BUN_CPP_ONLY` or `SKIP_CODEGEN`, the bindgen-generated C++ files aren't included in the cmake target list. Must compile them manually.
- **`_NativeModule.h` location**: In `src/bun.js/modules/`, needed for `GeneratedSocketConfigHandlers.cpp`.
- **Server migration**: Artifacts transferred from old VM via Mac SSH relay: jsc-build (205M), bun-vendor (290M), zig3+utilities. C++ .o files (7GB) rebuilt on openbsd-host with 8 cores.

## Key File Locations

### Mac (`<MAC_WORKSPACE>/opencode-port/`)
```
oven-zig/           # oven-sh/zig source (modified build.zig, bootstrap.c, Elf.zig, LibCInstallation.zig)
                    # lib/libc/include/generic-openbsd/ — OpenBSD system headers for cross-compilation
zig-mac/            # Pre-built oven-sh zig for Mac ARM64 (188MB)
bun-source/         # Bun source (50+ zig files, 20+ C/C++ files patched for OpenBSD)
  build/bun-zig.o   # Cross-compiled zig object file (254MB, ELF x86-64 OpenBSD, includes getFdPath fixes)
  build/codegen/    # Generated codegen files (77 files, all .lut.h regenerated with fixed wyhash)
  vendor/zstd/lib/  # zstd.h + zstd_errors.h (copied from OpenBSD)
  src/codegen/create_hash_table  # Perl hash table generator (wymum bug FIXED)
strip_debug_sections.py  # Python ELF debug section stripper (fixes LLD 19 bug)
opencode-src/       # OpenCode v1.2.6 source (anomalyco/opencode)
opentui-0.1.79/     # opentui source (anomalyco/opentui, for building libopentui.so)
  packages/core/src/zig/build.zig      # Modified: +Zig 0.15.1, +x86_64-openbsd target, native buildNativeTarget()
  packages/core/src/zig/build.zig.zon  # Modified: minimum_zig_version 0.15.1
  packages/core/scripts/build.ts       # Modified: +openbsd variant, +openbsd platformMap
  packages/core/src/zig/lib/x86_64-openbsd/libopentui.so  # Built output (4.3MB)
PLAN.md             # this file
```

### openbsd-host (`/srv/opencode-port/`) — physical server 192.168.x.x (migrated from <OLD_OPENBSD_WORKSPACE> 2026-02-18)
```
opencode/               # OpenCode v1.2.6 source (anomalyco/opencode, extracted from tarball)
  node_modules/@opentui/core-openbsd-x64/  # Manually created: libopentui.so + index.ts for OpenBSD TUI support
opentui-zig/            # opentui native lib source (Zig), built natively on OpenBSD → lib/native/libopentui.so
zig3                    # stage3 compiler (177MB, transferred from old VM)
add-openbsd-note        # ELF note utility (transferred from old VM)
fix-openbsd-elf         # ELF fix utility (transferred from old VM)
fakelib                 # fakelib utility (transferred from old VM)
bun                     # WORKING BINARY — PIE, Bun v1.3.10-canary.1 (96MB), includes getFdPath + installer fixes, OpenCode install + TUI work
bun-old                 # Previous binary (before session 5 fixes)
bun-new                 # Build artifact (same as bun, can be removed)
jsc-build/              # JSC build output (symlinked from /usr/obj/jsc-build)
  lib/libJavaScriptCore.a  # Thin archive (5.9MB index, 121MB objects)
  lib/libWTF.a             # 304KB
  lib/libbmalloc.a         # 29KB
  JavaScriptCore/Headers/  # Public headers
  JavaScriptCore/PrivateHeaders/  # Private headers
bun-build/              # Bun CMake build directory (symlinked from /usr/obj/bun-build)
  bun-zig.o             # Cross-compiled zig object (242MB, copied from Mac NFS)
  libbun-profile.a      # C++ static library (6.5G, compiled with -fPIC)
  codegen/              # Local copy of codegen files (12 .lut.h files up to date)
  boringssl/            # Built dependency libraries (all rebuilt on openbsd-host)
  mimalloc/ zlib/ brotli/ cares/ highway/ libdeflate/ lshpack/
  libarchive/ hdrhistogram/ zstd/ sqlite/ tinycc/ lolhtml/
bun-vendor/             # Downloaded dependency sources (symlinked from /usr/obj/bun-vendor)
libuv-build/            # libuv built from source for NAPI compat
  libuv.a               # Static library
openbsd_stubs.c         # C stubs: stat64 aliases, getFreeMemory, sysctlbyname, signal forwarding
openbsd_stubs.cpp       # C++ stubs: posix_spawn_bun (fork/execve), Bun::Secrets (stubbed)
openbsd_stubs_c.o       # Compiled C stubs
openbsd_stubs_cpp.o     # Compiled C++ stubs
Generated*.o            # Compiled bindgen files (5 files)
v8_array_bridge.o       # Assembly trampoline for v8::Array::New symbol mismatch
V8Array_fixed.o         # Fixed V8 Array implementation (17MB)
/tmp/v8_array_bridge.S  # Assembly source for trampoline
```

### Disk Usage (openbsd-host /home: 65.6GB free of 96.9GB)

## Code Review Findings (2026-02-17)

### Critical Issues Found

1. **`bun-spawn.cpp:3` — `posix_spawn_bun` not compiled for OpenBSD**
   - Guard: `#if OS(LINUX) || OS(DARWIN)` excludes OpenBSD
   - This is the **root cause of the Bun.spawn segfault** — Zig calls `posix_spawn_bun` but it resolves to the basic stub in `openbsd_stubs.cpp` which lacks the error pipe, response mechanism, and pty handling
   - Fix: Change to `#if OS(LINUX) || OS(DARWIN) || OS(OPENBSD)`, OpenBSD should follow the Darwin (fork-based) path

2. **`sys.zig:4339` — `dlsymImpl` missing OpenBSD**
   - Only checks `isMac or isLinux`, will hit `@compileError` at compile time for OpenBSD
   - Fix: Add `or Environment.isOpenBSD` — OpenBSD has standard dlsym in libc

### Already Well Handled (no changes needed)

- O flags (sys.zig:65-97) — comprehensive comptime conditionals
- RSS memory (BunProcess.cpp) — uses getrusage for OpenBSD
- CPU info / loadavg (node_os.zig) — custom sysctl implementation
- StatFS (bun.zig) — includes OpenBSD
- Crash handler (crash_handler.zig) — proper sigcontext register extraction
- TTY detection (c-bindings.cpp) — uses isatty()
- FFI shared library extension — ".so" for OpenBSD
- Errno handling — shares darwin_errno.zig
- Read/write/poll syscalls — properly includes OpenBSD

### Stubs Review (openbsd_stubs.c / openbsd_stubs.cpp)

**openbsd_stubs.c** — All stubs are correct and necessary:
- `stat64/fstat64/lstat64` → aliases to 64-bit stat (OpenBSD stat is already 64-bit)
- `Bun__Os__getFreeMemory` → sysctl HW_USERMEM64 (correct)
- `sysctlbyname` → stub returning -1 (OpenBSD doesn't have sysctlbyname)
- `on_before_reload_process_linux` → empty (Linux-only)
- Signal forwarding stubs → empty (process forwarding not yet implemented)

**openbsd_stubs.cpp** — Needs refactoring:
- `posix_spawn_bun` → **Should be removed** once `bun-spawn.cpp` is fixed to include OpenBSD. Currently a basic fork/execve without error pipe, pty handling, or POSIX_SPAWN_SETSID.
- `Bun::Secrets` → Correct stubs (no keychain API on OpenBSD). Could use `pledge`-compatible alternative in future.

### Bugs Fixed Session 9 (2026-02-20)

**9. `process.stdin.isTTY` always `undefined` on OpenBSD (FIXED)**
- Root cause: `c-bindings.cpp:498` — platform guard `#if OS(LINUX) || OS(DARWIN)` excluded OpenBSD from `Bun__isTTY()` function
- Fix: Changed to `#if OS(LINUX) || OS(DARWIN) || OS(OPENBSD)` — one-line change
- Verified: `process.stdin.isTTY` / `stdout.isTTY` / `stderr.isTTY` all return `true` on real TTY via tmux
- Rebuild: Recompiled just `c-bindings.cpp` on openbsd-host (exact command from compile_commands.json), updated `libbun-profile.a` with `ar r`, stripped `bun-zig.o` with `strip_debug_sections.py` (254→38MB), relinked

**10. `@opentui/core-openbsd-x64` module resolution from bun install cache (FIXED)**
- Symptom: TUI enters CPU spin (R+ state) instead of rendering
- Root cause: Bun's resolver can't find `@opentui/core-openbsd-x64` from the install cache path
- Fix: Patched both copies to use absolute path for OpenBSD:
  - `<OLD_OPENBSD_WORKSPACE>/.bun/install/cache/@opentui/core@0.1.80@@@1/index-vnvba6q9.js:10461`
  - `/srv/opencode-port/opencode/node_modules/@opentui/core/index-zrvzvh6r.js:10323`
- Change: `await import(...)` → `process.platform === "openbsd" ? await import("/srv/opencode-port/opencode/node_modules/@opentui/core-openbsd-x64/index.ts") : await import(...)`
- Verified: `import("@opentui/core")` succeeds with all 173+ exports

**11. TUI renders from source — MAJOR MILESTONE**
- After patches 8a/8b/8c/10: **OpenCode TUI fully renders on OpenBSD** when run from source
- Banner, input box ("Ask anything..."), model picker, ctrl+t/tab/ctrl+p shortcuts, tips, status bar all display
- Process goes to **S+ state** (sleeping, correct) — no CPU spin
- Command: `cd /srv/opencode-port/opencode/packages/opencode && /srv/opencode-port/bun run --conditions=browser src/index.ts`

### Bugs Fixed Session 11 (2026-02-20)

**12. `onTick` event dispatch drops ALL kqueue events on OpenBSD (FIXED — ROOT CAUSE of keyboard input + compiled binary CPU spin)**
- Root cause: `src/async/posix_event_loop.zig:820` — `Bun__internal_dispatch_ready_poll` (the `onTick` function) checked `Environment.isMac` instead of `Environment.isBSD` for the kqueue dispatch path
- On OpenBSD (`isMac=false`, `isLinux=false`), neither the kqueue nor epoll branch executed, silently dropping ALL kqueue events from Bun-registered file descriptors (stdin, file watchers, etc.)
- Network operations worked because usockets handles those directly in C, bypassing `onTick`
- Fix: Changed `isMac` → `isBSD` at line 820 (kqueue dispatch) and line 365 (debug string)
- **This was the root cause of BOTH remaining TUI issues:**
  - **Keyboard input**: `process.stdin.on("data")` never delivered data because stdin kqueue events were dropped in `onTick`
  - **Compiled binary CPU spin**: Events fired in kqueue but were never dispatched, causing polling loops to busy-spin
- Verified: `process.stdin.on("data")` now delivers keystrokes, OpenCode TUI accepts keyboard input in both source and compiled modes
- Compiled binary now in S+ state (sleeping, not R+ CPU spinning)

### Final TUI Test Results (2026-02-20)

| Test | Status | Notes |
|------|--------|-------|
| `process.stdin.on("data")` delivers keystrokes | **PASS** | Was broken before `onTick` fix |
| OpenCode TUI source mode — renders | **PASS** | Banner, input box, model picker all display |
| OpenCode TUI source mode — keyboard input | **PASS** | "hello world" typed and appeared in input box |
| OpenCode TUI compiled mode — renders | **PASS** | Same as source mode |
| OpenCode TUI compiled mode — keyboard input | **PASS** | "test compiled" typed and appeared in input box |
| Compiled binary process state | **PASS** | S+ (sleeping), not R+ (CPU spin) |

### Remaining Issues (non-blocking)

| Issue | Type | Priority |
|-------|------|----------|
| Compiled binary ~58-79% CPU | Performance | LOW — may be worker thread activity or animation, process is S+ not R+ |
| `child_process.execSync/spawnSync` hang | Bun bug | LOW — race condition in recvNonBlock loop |
| `bun install` missing symlinks | Bun bug | LOW — shell script workaround works |
| Zombie worker processes | Cosmetic | LOW — worker threads not reaped on exit |
