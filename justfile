set windows-shell := ["nu", "-c"]
set shell := ["bash", "-c"]

test_main_name := "test-main.exe"

# Which linker Odin hands the object files to. `-linker:` takes exactly four values: `default` (Odin
# picks - MSVC `link.exe` on Windows), `lld` (Windows and Linux; NOT on a stock macOS, where Odin
# links through Apple's clang and clang ships no lld), `radlink` (Windows only, and bundled with the
# Odin toolchain so it needs no install - which is why it is the Windows default here) and `mold`
# (Linux only, and not bundled - `apt install mold` first). Odin has no build cache and relinks on
# every `just run`, so the link step is a cost paid on each iteration.
#
# Override for a single command without editing this file. It is an env var rather than a recipe
# argument because `odin` errors on a repeated flag, so a `-linker:` passed through a recipe's *args
# would collide with the one the recipe already adds:
#
#     ODIN_LINKER=lld just run -lto:thin   # -lto on Windows *requires* -linker:lld
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

# (re)build the fast_float static library from src/ffc.h.
# Windows -> lib/fast-float.lib via MSVC (build.bat self-loads vcvars64 if cl is absent).
[windows]
lib:
	cmd /c src\build.bat

# (re)build the fast_float static library from src/ffc.h.
# Unix/macOS -> lib/libfast-float.a via cc/make (UNTESTED).
[unix]
lib:
	make -C src

# run the fast_float bindings demo (examples/)
example *args:
	odin run examples -linker:{{linker}} {{args}}

# run the strconv vs fast_float parse benchmarks, optimized (bench/)
bench *args:
	odin run bench -o:speed -microarch:native -linker:{{linker}} {{args}}

# run all tests in the root package
test *args:
	odin test . -debug -file -microarch:native -show-timings -linker:{{linker}} -out:{{test_main_name}} {{args}}

# delete build artifacts (executables, objects, the test binary)
[windows]
clean:
	rm --force --recursive target
	-rm *.exe *.pdb *.obj

[unix]
clean:
	rm -rf target *.exe *.pdb *.obj
