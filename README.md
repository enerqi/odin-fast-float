# odin-fast-float

[Odin](https://odin-lang.org/) bindings to [**fast_float**](https://github.com/fastfloat/fast_float),
Daniel Lemire's exact, high-throughput number parser, via the single-header C port
[`ffc.h`](https://github.com/kolemannix/ffc.h).

`core:strconv` is fine for short, well-formed input but degrades badly on long mantissas and
large exponents (parsing `1.7976931348623157e308` is ~9.7 µs/call). fast_float stays flat at
~10–45 ns/call across the same inputs because it parses 8 digits at a time with SWAR and does
the float conversion with integer math, while still producing the correctly-rounded IEEE-754
result. See [Benchmarks](#benchmarks).

```odin
import ff "path/to/odin-fast-float"

v, ok := ff.parse_f64("1.7976931348623157e308")   // v = 1.797…e308, ok = true
n, ok := ff.parse_i64("9223372036854775807")      // n = i64 max,    ok = true
```

## Status & platform

**Windows / x86-64 is the only tested target.** The binding links a static `lib/fast-float.lib`
produced by MSVC `cl` (`src/build.bat`). A `src/Makefile` builds `lib/libfast-float.a` with
`cc`/`make` for Linux/BSD/macOS and the `foreign import` already points at it on non-Windows — but
**that path is UNTESTED**; the parser is portable C, so it is expected to work, not verified.

> ⚠️ **The x86-64 libs assume AVX2** (Intel Haswell / 2013+, AMD Excavator+): the Windows `.lib`
> via `-arch:AVX2`, the Unix/macOS `.a` via `-mavx2`. fast_float has no runtime SIMD dispatch, so on
> an older CPU it faults with an illegal instruction (`#UD`). Drop `-arch:AVX2` from `src/build.bat`
> (or `-mavx2` from `src/Makefile`) and rebuild for pre-AVX2 hardware. arm64/aarch64 is unaffected
> (NEON baseline).

## Version

| odin-fast-float tag | ffc version | notes              |
| ------------------- | ----------- | ------------------ |
| 2026-06             | 26.04.01    | Initial bindings   |

## Layout

| Path | What |
|------|------|
| `fast_float.odin`                  | The Odin package: `foreign import` + `parse_*` wrappers (root, `package fast_float`) |
| `src/ffc.h`                        | Vendored single-header C port of fast_float ([upstream](https://github.com/kolemannix/ffc.h)) |
| `src/ffc_impl.c`                   | One-line TU that `#define FFC_IMPL`s the header to emit the bodies |
| `src/build.bat`                    | Compiles `ffc_impl.c` → `lib/fast-float.lib` (self-loads MSVC via vcvars64) |
| `lib/fast-float.lib`               | Prebuilt static library, committed (rebuild with `just lib`) |
| `examples/example_fast_float.odin` | Runnable demo |
| `bench/bench.odin`                 | `core:strconv` vs fast_float benchmark |

> `ffc.h` is vendored under `src/`. Pulling it in as a git submodule under `external/` instead is a
> possible future change; the `build.bat` / `foreign import` paths would move accordingly.

## Build the library

The prebuilt `lib/fast-float.lib` is committed, so cloning and importing the package works without
a C toolchain. Rebuild it after editing `ffc.h`, or to produce the Unix `.a`:

```sh
just lib            # Windows: cd src && .\build.bat   |   Unix/macOS: make -C src
```

On Windows `build.bat` finds the x64 MSVC toolchain via `vswhere`/`vcvars64` if `cl` is not already
on PATH, so it runs from a plain shell — no "x64 Native Tools" prompt required. On Unix/macOS the
`Makefile` builds `lib/libfast-float.a` with the system `cc` (untested — see Status). Rebuild after
editing `ffc.h`.

## Usage

Import the package by path and call the string-taking wrappers. Each returns `(value, ok)`; on a
parse failure the value is the library's `0`/`0.0` default and `ok` is `false`.

```odin
import ff "path/to/odin-fast-float"

f64v, ok := ff.parse_f64("3.14")
f32v, ok := ff.parse_f32("3.40282347e38")

i64v, ok := ff.parse_i64("-42")          // base 10 by default
u64v, ok := ff.parse_u64("18446744073709551615")
i32v, ok := ff.parse_i32("2147483647")
u32v, ok := ff.parse_u32("4294967295")

hexv, ok := ff.parse_i64("ff", 16)       // integer parsers take an optional base
```

Notes:

- Inputs are `string` (a length + pointer); they need **not** be NUL-terminated.
- The wrappers are `#force_inline` — the only Odin-side cost is setting up the length/pointer pair;
  the actual work happens across the `foreign` boundary in the C library.
- The parsers consume the valid numeric **prefix** and stop. `parse_i64("12.5")` returns `12, true`
  — unlike `strconv.parse_int`, which rejects trailing junk. For strict end-of-input or to parse a
  stream of numbers, use the `*_prefix` wrappers below, which also return the byte count consumed.

The **whole** public `ffc` API is bound — value-returning, stop-pointer, options, and JSON:

```odin
// stop-pointer: value, bytes consumed, ok. rest of input is s[n:].
v, n, ok := ff.parse_f64_prefix("3.14abc")       // 3.14, 4, true   -> rest "abc"
v, n, ok  = ff.parse_i64_prefix("42, 7")         // 42,   2, true
_, n, ok := ff.parse_f64_prefix("1.5x")          // strict: ok && n == len(s) is false

// format options: locale decimal point + JSON / Fortran / hex / leading-'+' / skip-ws.
opts := ff.Parse_Options{ format = ff.PRESET_JSON, decimal_point = '.' }
v, n, ok := ff.parse_f64_opts("inf", opts)        // ok = false (JSON preset rejects inf/nan)

// JSON number: tagged int-or-double union.
num, n, ok := ff.parse_json_number("-45.6e2")     // num.kind == .Double, num.value.f64 == -4560
```

Also available: the raw 1:1 `ffc_*` foreign procs (`ffc_from_chars_*`, `ffc_parse_*`,
`ffc_parse_options_default`, …) for full pointer-range control. See `fast_float.odin`.

Run the demo:

```sh
just example
```

## Benchmarks

```sh
just bench                                    # 1,000,000 iterations/case, -o:speed
just bench -- -define:COUNT_ITERATIONS=5000000
```

Parsing throughput, ns/call (Windows x86-64, representative — your numbers will differ):

| input                          | `strconv` | fast_float |
|--------------------------------|----------:|-----------:|
| `i64` `7`                       |    5.2 |  8.6 |
| `i64` `123456`                  |   17.7 |  9.0 |
| `i64` `9223372036854775807`     |   49.2 | 10.3 |
| `f64` `3.14`                    |   10.3 | 28.3 |
| `f64` `3.14159265358979311600`  |  162.4 | 44.5 |
| `f64` `1.7976931348623157e308`  | 9731.0 | 32.8 |

Takeaways:

- fast_float is roughly **flat** in input length; `strconv` cost grows with digits and explodes on
  the big-exponent path (~**300×** slower there).
- For short, easy inputs `strconv` wins: it inlines into the caller, whereas every fast_float call
  pays a fixed ~28 ns `foreign`-call floor (see below). Use fast_float when inputs are long, varied,
  or adversarial; `strconv` when they are short and you parse them in tight Odin code.

## Build / link notes

- **`/MT` is mandatory.** The lib is built with the static CRT (`/MT` → `libcmt`) because Odin's
  Windows backend links `/defaultlib:libcmt` for every non-static-library build. A `/MD` lib would
  mismatch Odin's CRT (LNK4098, two heaps). Both sides must resolve to the one static `libcmt`.
- **`/Gy /Gw` + `/opt:ref`.** The lib puts each function/global in its own COMDAT; Odin's link
  passes `/opt:ref`, which dead-strips the hundreds of `ffc` functions a given program never calls.
  Pure size win. (Odin does **not** pass `/opt:icf` — add `-extra-linker-flags:"/opt:icf"` if you
  want identical-function folding.)
- **No cross-language inlining.** `build.bat` deliberately omits `/GL` (its IL is MSVC-proprietary,
  unreadable by `lld-link`/`rad-link`) and Odin emits no `/LTCG`, so the linker treats the `.lib` as
  opaque COFF. The Odin→`ffc` call stays a real call — that is the ~28 ns floor above; it is
  structural, not something `#force_inline` or link flags remove.
- **`/fp:fast` is off, `/GS` on** — correct float round-tripping needs exact arithmetic, and the
  parser eats untrusted input.

## Tasks

| `just` recipe | Does |
|---------------|------|
| `just lib`     | (re)build `lib/fast-float.lib` from `src/` (Windows/MSVC) |
| `just example` | run the bindings demo |
| `just bench`   | run the strconv-vs-fast_float benchmark (optimized) |
| `just lint`    | type-check + vet root, `bench`, `examples` |
| `just format`  | `odinfmt -w .` over the tree |
| `just test`    | run root-package tests |
| `just clean`   | remove build artifacts |

All recipes take optional trailing args; put `--` before flags meant for the Odin program (e.g.
`just bench -- -define:COUNT_ITERATIONS=...`). Requires [Just](https://just.systems/) and `odinfmt`
(from [OLS](https://github.com/DanielGavin/ols)) on PATH.

## License

The `ffc.h` / fast_float source is tri-licensed Apache-2.0 / MIT / Boost by its authors (notices
retained in the header). See [`LICENSE`](LICENSE) for this project's terms (Zlib).
