set windows-shell := ["nu", "-c"]
set shell := ["bash", "-c"]

test_main_name := "test-main.exe"

# odinfmt every odin file under this directory or subdirectories
format:
	odinfmt -w .

# lint checks for style and potential bugs. Accepts extra args like `--show-timings` as needed
lint *args:
	odin check . -vet -vet-cast -strict-style -no-entry-point {{args}}
	odin check bench -vet -strict-style {{args}}
	odin check examples -vet -strict-style {{args}}

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
	odin run examples {{args}}

# run the strconv vs fast_float parse benchmarks, optimized (bench/)
bench *args:
	odin run bench -o:speed -microarch:native {{args}}

# run all tests in the root package
test *args:
	odin test . -debug -file -microarch:native -show-timings -out:{{test_main_name}} {{args}}

# delete build artifacts (executables, objects, the test binary)
[windows]
clean:
	rm --force --recursive target
	-rm *.exe *.pdb *.obj

[unix]
clean:
	rm -rf target *.exe *.pdb *.obj
