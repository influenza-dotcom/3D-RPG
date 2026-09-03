# Windows DLL: fixed rebuild (2026-09-01)

`lib/win/libgodot_text_to_speech.dll` is a **patched rebuild** of upstream
[kdik/godot-text-to-speech](https://github.com/kdik/godot-text-to-speech), replacing the
shipped binary (which lives in git history if you ever need it back).

## The bug it fixes — the playtest "hard crash"

Every quit of the RELEASE EXPORT crashed with `0xc0000374` (heap corruption fail-fast).
Minidump forensics on all eight 2026-08-28/29 playtest dumps showed the identical
deterministic failure: `ntdll` reports `heap_failure_block_not_busy` (an **invalid free**,
not a memory smash) on the msvcrt CRT heap, fired from
`GDExtension::deinitialize_library → godot-cpp ClassDB::deinitialize →
memdelete(MethodBind) → MethodBind::~MethodBind() → free(argument_types)` at process
exit. Reproduced on demand: `CYBERSUNDAY.exe --headless --quit` exited `0xC0000374`
with the old DLL, `0` with this one — three for three each way.

**Root cause: godot-cpp build-flavor mismatch.** The upstream CMake builds godot-cpp as
`template_debug` (its default) even for Release. Under `DEBUG_ENABLED`, godot-cpp's
`Memory::alloc_static/free_static` skip their own 16-byte pad bookkeeping on the
assumption that a DEBUG engine pre-pads every allocation. That contract holds in the
EDITOR (debug engine — which is why the bug never showed in development) and breaks
against the RELEASE export engine (which pads nothing): every padded alloc/free pair in
the extension is off by 16 bytes, and the first dense free site — extension teardown at
quit — trips the heap validator. Fix: build godot-cpp (and the extension TU, which
inherits the define) as **`template_release`**: `-DGODOTCPP_TARGET=template_release`.
A template_release extension is symmetric against BOTH editor and export engines.
This likely bites every consumer of the upstream prebuilt DLLs in release exports —
worth reporting upstream.

## Also in this rebuild (see `windows-privheap-rebuild.patch`)

1. **`src/cst_private_heap.c` (new)** — flite compiled with `-DCST_USER_MALLOC`, all
   flite allocation backed by a dedicated `HeapCreate` heap: TTS voice/synth memory is
   isolated from the CRT heap the engine shares, in both directions.
2. **`src/text_to_speech.cpp`** — voices cached process-wide by path and never
   `delete_voice`d (flite's cg_db teardown trusts count fields read independently of the
   arrays they free — not worth exercising mid-game), so a voice switch is instant
   instead of a 6–12 MB reload; `flite_init`/`flite_add_lang` run once per process
   (flite's lang list is a fixed-capacity global).
3. **`CMakeLists.txt`** — optional `FLITE_PREBUILT_LIB_DIR` to build against
   already-built flite static libs (the in-tree ExternalProject copy-build miscomputes
   archive paths under some MSYS2 layouts).

## Verification done for this rebuild

- Export exit: old DLL `0xC0000374` on every `--headless --quit`; this DLL `0` ×3 plus
  a 300-frame `--quit-after` session, also `0`.
- PCM parity: byte-identical synth output vs. the shipped DLL — 420 (voice × line)
  checksums standalone AND the in-engine probe (`scripts/tools/__tts_dll_probe.gd`,
  22/22 lines incl. a 60-switch voice churn).
- flite itself cleared by a 72M-allocation guarded stress (canaries + quarantine + full
  heap sweeps; all 7 voices; the game's real spoken-text corpus; the game's usage
  patterns incl. delete/reload churn and teardown) — plus a second clean pass on the
  private-heap build.
- GUT: the five `test_dialogue*` files, 100/100 with this DLL loaded.

## Reproducing the build (MSYS2 MINGW64: gcc, cmake, ninja, mingw32-make)

```bash
git clone https://github.com/kdik/godot-text-to-speech && cd godot-text-to-speech
git checkout 42414c47df529c405c61b148008c188cc8768ffe
git submodule update --init --depth 1 extern/godot-cpp flite
# (pinned: godot-cpp d502d8e8aae3 [branch 4.4], flite 6c9f20dc915b)
git apply /path/to/windows-privheap-rebuild.patch
cp -r flite flite-build && cd flite-build
CC=gcc CFLAGS="-O2 -g -DCST_USER_MALLOC" ./configure --disable-shared --with-audio=none
make -j1   # tool binaries under main/ fail to link without the CRT allocator — the
cd ..      # static libs under build/*/lib are complete before that and are all we need
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGODOTCPP_TARGET=template_release \
  -DFLITE_PREBUILT_LIB_DIR=$PWD/flite-build/build/x86_64-mingw64/lib
cmake --build build --parallel 8
# output: addons/text_to_speech/lib/win/libgodot_text_to_speech.dll
```

`-DGODOTCPP_TARGET=template_release` is the load-bearing flag — never ship a
`template_debug` build of this (or any) extension inside a release export.

Note: with the private heap + voice cache, the GDScript-side voice pinning in
`managers/SpeechTts.gd` is belt-and-braces rather than load-bearing — keep it anyway
(it also avoids redundant native calls).
