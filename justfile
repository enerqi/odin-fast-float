# `cmd.exe` for one reason: it starts in ~9ms. just launches a shell per recipe LINE, so shell startup
# is a fixed tax on every recipe. Bare `<shell> exit` under hyperfine: cmd ~9ms, `nu -c` ~41ms (what
# this file used to set), `powershell -NoLogo -NoProfile -Command` ~143ms. cmd is also more portable
# than either: on every Windows and on GitHub's windows runners, no install, and no profile to make a
# recipe unreproducible. The cost is that it is a poor language for a multi-line recipe - which does
# not bite, because every Windows body below is a single command; anything with logic would use
# `[script("python")]` instead.
set windows-shell := ["cmd.exe", "/c"]
set shell := ["bash", "-c"]
set unstable  # user-defined functions (`target_path` below) are still gated
set lazy

# Set by the newest just feature used below - user-defined functions (1.49), for `target_path`.
# Older features also needed: `join()` 1.37, `set lazy` 1.47. Without this an old just reports a plain
# syntax error at the offending line, which reads like a corrupt justfile rather than an old tool.
set minimum-version := "1.49.0"

example_name := "example.exe"
bench_name := "bench.exe"
test_main_name := "test-main.exe"

# `join`, not the `/` operator: `/` always emits a forward slash, and cmd.exe rejects a forward-slash
# path in *command* position ("'target' is not recognized") even quoted. Odin takes either in an
# `-out:` argument, but the `rerun_*` recipes invoke the binary directly, so they need the native
# separator `join` gives. bash needs no `./` prefix - a path containing a slash is already a path.
target_path(dir, name) := join("target", dir, name)

# Which linker Odin hands the object files to. `-linker:` takes exactly four values: `default` (Odin
# picks - MSVC `link.exe` on Windows), `lld` (Windows and Linux; NOT on a stock macOS, where Odin
# links through Apple's clang and clang ships no lld), `radlink` (Windows only, and bundled with the
# Odin toolchain so it needs no install - which is why it is the Windows default here) and `mold`
# (Linux only, and not bundled - `apt install mold` first). Odin has no build cache and relinks on
# every `just bench`, so the link step is a cost paid on each iteration.
#
# Override for a single command without editing this file. It is an env var rather than a recipe
# argument because `odin` errors on a repeated flag, so a `-linker:` passed through a recipe's *args
# would collide with the one the recipe already adds:
#
#     ODIN_LINKER=lld just bench -lto:thin   # -lto on Windows *requires* -linker:lld
#
# Caution for a bindings project that statically links a C library, which is exactly what this one is:
# radlink has been seen to link a binary cleanly and then have it die at startup with `0xc000001d`
# (STATUS_ILLEGAL_INSTRUCTION) - see odin-num-format's justfile (Rust staticlib + `+crt-static`) and
# odin-sims (the DDS static lib), both of which had to pin `default`. If a fast-float binary ever fails
# that way, try `ODIN_LINKER=default` first; a successful link proves nothing, only running it does.
#
# See the odin-lang-skeleton justfile for the full per-value notes.
linker := env_var_or_default("ODIN_LINKER", if os() == "windows" { "radlink" } else { "default" })

# odinfmt every odin file under this directory or subdirectories
format:
	odinfmt -w .

# lint checks for style and potential bugs. Accepts extra args like `--show-timings` as needed
lint *args:
	odin check . -vet -vet-cast -strict-style -vet-tabs -no-entry-point {{args}}
	odin check bench -vet -vet-cast -strict-style -vet-tabs {{args}}
	odin check examples -vet -vet-cast -strict-style -vet-tabs {{args}}

# The build recipes below now write into target/ rather than the repo root, so they need the directories
# to exist first - odin does not create them (the linker fails with LNK1104). Created all at once rather
# than one per line because just starts a new shell per recipe line and on Windows the shell launch
# dwarfs the work.
# ---
# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	mkdir -p target/debug target/release

# `if not exist` rather than swallowing md's "already exists" with `2>nul`, so a genuine failure still
# sets a non-zero exit. The loop variable is a single `%d`, NOT the `%%d` a .bat file would use:
# doubling is escaping for batch *files*, and `cmd /c` takes a command *line*.
# ---
# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
	for %d in (debug release) do @if not exist target\%d md target\%d || exit /b 1

# (re)build the fast_float static library from src/ffc.h.
# Windows -> lib/fast-float.lib via MSVC (build.bat self-loads vcvars64 if cl is absent).
[windows]
lib:
	src\build.bat

# (re)build the fast_float static library from src/ffc.h.
# Unix/macOS -> lib/libfast-float.a via cc/make (UNTESTED).
[unix]
lib:
	make -C src

# `-out:` and `-keep-executable` are new here: these recipes used to let odin pick the output name,
# which dropped the exe/pdb/obj in the repo root (which is why `clean` had to sweep `*.exe *.pdb
# *.obj`). Now everything lands under target/, and the binary survives the run so `rerun_*` can skip
# the recompile Odin has no build cache to avoid.
# ---
# run the fast_float bindings demo (examples/)
example *args: mktarget_dirs
	odin run examples -keep-executable -linker:{{linker}} -out:{{ target_path("debug", example_name) }} {{args}}

# re-run the last built demo WITHOUT recompiling. Requires a prior `just example`.
rerun_example *args:
	{{ target_path("debug", example_name) }} {{args}}

# run the strconv vs fast_float parse benchmarks, optimized (bench/)
bench *args: mktarget_dirs
	odin run bench -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release", bench_name) }} {{args}}

# re-run the last built benchmark WITHOUT recompiling - the point of a benchmark recipe is the run, and
# under `just bench` most of the wall clock is the rebuild. Requires a prior `just bench`.
rerun_bench *args:
	{{ target_path("release", bench_name) }} {{args}}

# run all tests in the root package
test *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# Filtering is a `core:testing` define rather than a compiler flag - there is no `-test-name:` (a stale
# spelling fails with `Unknown flag: 'test-name'` before anything builds). NAME takes a comma-separated
# list and the package prefix is optional, so `my_test` and `one,two` both work.
# ---
# run one named test (comma-separated for several)
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -define:ODIN_TEST_NAMES={{name}} -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# Everything now builds into target/, so this is a single directory delete. The old recipe also swept
# `*.exe *.pdb *.obj` from the repo root, which is where the untargeted builds used to land; those two
# lines stay for one more release to clear a tree built by the previous justfile.
# ---
# delete build artifacts
[unix]
clean:
	rm -rf target *.exe *.pdb *.obj
	just mktarget_dirs

# cmd's equivalent of `rm -rf` is `rmdir /s /q`. Guarded by `if exist` because rmdir exits non-zero on
# a missing path, which would fail the recipe on an already-clean tree. `del` is given `2>nul` and a
# trailing `|| exit /b 0` instead, because it has no `if exist` form that covers three wildcards.
# (The old recipe used nu's `rm --force --recursive`, which cmd has no equivalent of at all.)
# ---
# delete build artifacts
[windows]
clean:
	if exist target rmdir /s /q target
	del /q *.exe *.pdb *.obj 2>nul || exit /b 0
	just mktarget_dirs
