# Build the static fast_float (ffc) library for the Odin bindings (Unix / macOS).
# Windows is built separately with build.bat (MSVC). Run via `make -C src`.
#
# UNTESTED: the Windows build (build.bat) is the only one exercised so far. This
# Makefile mirrors its flag choices for Linux/BSD/macOS but has not been run yet.
#
# --- flag rationale (kept in sync with build.bat where it makes sense) -------
#
# Translation unit: ffc_impl.c is the single .c that `#define FFC_IMPL` + includes
# ffc.h to emit the out-of-line bodies. The macro lives in the .c, so unlike yyjson
# there is no -D to pass here.
#
# -O2            Optimize for speed (matches build.bat /O2). Use -O2 alone; with
#                GCC/Clang the LAST -O wins, so never pair it with -Os.
#
# -fPIC          Position-independent code: required for the .a to fold into a
#                modern PIE executable (Odin default) or a future shared object.
#
# -ffunction-sections -fdata-sections
#                Put each function and global in its own section -- the GCC/Clang
#                analog of build.bat's /Gy /Gw. Lets the CONSUMER's linker dead-strip
#                unused ffc symbols with --gc-sections (Odin's lld honors it) instead
#                of pulling whole objects. Pure link-time/size win; no runtime effect.
#
# CRT: nothing to do. Unlike Windows (static libcmt vs dynamic msvcrt, which MUST
# match the Odin host - see build.bat), Linux/BSD/macOS have no static/dynamic CRT
# split: Odin and the .a both link the system libc dynamically. Do not statically
# link the C library; it gains nothing here and breaks dlopen/NSS.
#
# -mavx2 (x86_64 only): matches the Windows prebuilt (build.bat /arch:AVX2) so both
# shipped libs assume the same AVX2 baseline (Intel Haswell 2013+ / AMD Excavator+).
# fast_float has NO runtime SIMD dispatch, so the resulting .a will fault with an
# illegal instruction (#UD) on an older CPU. Drop AVX2 (or use -march=native) if you
# need to run on pre-AVX2 hardware. Not applied on aarch64, which uses NEON baseline.
#
# No -flto: same trap as MSVC /GL. An LTO .a carries GIMPLE/bitcode needing the
# matching compiler's LTO plugin at final link; a foreign linker (Odin's lld) may
# not invoke it -> link breakage. ffc is a single TU, so LTO buys ~nothing here.
#
# No -ffast-math: correct float round-tripping needs exact arithmetic (build.bat
# likewise omits /fp:fast).

CFLAGS_COMMON = -O2 -fPIC -ffunction-sections -fdata-sections
MACOS_MIN     = -mmacosx-version-min=10.12

OS   = $(shell uname)
ARCH = $(shell uname -m)

# AVX2 only on x86_64 (see note above); aarch64/arm64 use their NEON baseline.
ifeq ($(ARCH), x86_64)
ARCH_FLAGS = -mavx2
endif

ifeq ($(OS), Darwin)
all: darwin
else
all: unix
endif

unix:
	mkdir -p ../lib
	$(CC) -c $(CFLAGS_COMMON) $(ARCH_FLAGS) ffc_impl.c -o ffc_impl.o
	$(AR) rcs ../lib/libfast-float.a ffc_impl.o
	rm -f ffc_impl.o

# Universal (x86_64 + arm64) fat archive, output to the same lib/ path the Odin
# binding's non-Windows `foreign import` expects.
darwin:
	mkdir -p ../lib
	$(CC) -arch x86_64 -mavx2 -c $(CFLAGS_COMMON) $(MACOS_MIN) ffc_impl.c -o ffc_impl-x86_64.o
	$(CC) -arch arm64         -c $(CFLAGS_COMMON) $(MACOS_MIN) ffc_impl.c -o ffc_impl-arm64.o
	lipo -create ffc_impl-x86_64.o ffc_impl-arm64.o -output ../lib/libfast-float.a
	rm -f ffc_impl-x86_64.o ffc_impl-arm64.o

.PHONY: all unix darwin
