@echo off
rem setlocal so the env changes vcvars64 makes below don't leak into the caller's
rem shell; it is auto-restored when the script exits.
setlocal

rem --- ensure cl (the MSVC compiler) is available ------------------------------
rem Lets this run from a plain cmd shell, not only an "x64 Native Tools" prompt:
rem if cl is missing we locate Visual Studio via vswhere and load the x64 env.
where cl >nul 2>nul
if %errorlevel%==0 goto have_cl

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [build] cl not on PATH and vswhere not found.
    echo [build] Open an "x64 Native Tools Command Prompt for VS" and re-run.
    exit /b 1
)
rem -prerelease so VS preview / future channels are found too.
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%i"
if not defined VSINSTALL (
    echo [build] No VS install with C++ tools found via vswhere.
    exit /b 1
)
if not exist "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" (
    echo [build] vcvars64.bat missing under "%VSINSTALL%".
    exit /b 1
)
echo [build] Loading x64 toolchain from "%VSINSTALL%"
rem 2>nul silences benign stderr from vcvars' own internal vswhere lookup; the
rem `where cl` check on the next line is the real guard that it actually worked.
call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul
where cl >nul 2>nul || (echo [build] cl still not on PATH after vcvars64. & exit /b 1)
:have_cl

rem Run from anywhere (repo root, src\, or elsewhere). %~dp0 is this script's own
rem dir (...\src\). pushd AFTER loading vcvars64 (which can change the cwd), so we
rem land in src\ regardless of where we were called or where vcvars left us. All
rem paths below stay relative to src\; popd restores the cwd at the end.
pushd "%~dp0"

if not exist "..\lib" mkdir ..\lib

rem --- the translation unit -----------------------------------------------------
rem ffc.h is a single-header C port of fast_float. ffc_impl.c is the one .c file
rem that `#define FFC_IMPL` + `#include "ffc.h"` to emit the out-of-line bodies,
rem so we compile ffc_impl.c (NOT ffc.h). The FFC_IMPL macro lives in the .c, so
rem no /D is needed here.

rem --- C runtime: /MT is REQUIRED here, not a preference -----------------------
rem https://learn.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library
rem /MT links the static CRT (LIBCMT.lib); /MD would link the dynamic CRT (MSVCRT).
rem
rem We build this .lib to be consumed by Odin programs. Odin's Windows backend
rem emits `/defaultlib:libcmt` for any non-static-library build (see Odin
rem src/linker.cpp: no_crt ? /nodefaultlib : /defaultlib:libcmt). i.e. the Odin
rem host links the STATIC CRT. There is no Odin flag to pick the dynamic CRT;
rem only -no-crt turns it off entirely.
rem
rem MSVC rule: "All modules passed to a given invocation of the linker must have
rem been compiled with the same runtime library compiler option (/MD, /MT, /LD)."
rem So fast-float MUST be /MT to match Odin's libcmt. /MD would give a /MD vs /MT
rem mismatch -> LNK4098 + two CRT copies -> two heaps. With /MT both sides resolve
rem to the single statically-linked libcmt the linker folds in -> one heap -> safe.
rem
rem Linker-independent: Odin's default Windows linker is MS link.exe, switchable
rem to lld-link (-linker:lld) or rad-link (-linker:radlink). All three are
rem MSVC-family COFF linkers that honor the /defaultlib directive /MT bakes into
rem the .obj, so the /MT match holds whichever is used.

rem /TC compile as C (ffc.h is the C port, not the C++ original).
rem /O2 maximum optimizations (favor speed). Already implies /Oi (intrinsics) and
rem /Ot (favor speed), so those are not listed separately.
rem -arch:AVX2 assumes an AVX2-capable CPU (Intel Haswell 2013+). fast_float's SIMD
rem paths are SSE2-gated (FFC_SSE2) with no runtime dispatch, so this is a codegen
rem ceiling for the scalar code; deliberate.
rem
rem /Gy (function COMDATs) + /Gw (data COMDATs): put each function and global in
rem its own section so the CONSUMER's linker can dead-strip the unused ones
rem individually instead of pulling the whole .obj -> smaller exe, faster link.
rem Verified: Odin's Windows link.exe invocation passes /opt:ref (+ /incremental:no),
rem which uses these COMDATs to strip the hundreds of ffc functions a given Odin
rem program never calls. (It does NOT pass /opt:icf by default; add it yourself with
rem `odin build ... -extra-linker-flags:"/opt:icf"` for identical-function folding.)
rem Pure link-time/size win; no effect on runtime throughput.
rem
rem NOT used: /GL (LTCG) - its objects hold MSVC proprietary IL, not COFF, so
rem lld-link / rad-link cannot read them, AND it would not buy cross-language inlining
rem anyway: Odin emits no /LTCG, so the linker treats this .lib as opaque COFF and the
rem Odin->ffc foreign call stays a real (non-inlined) call regardless. /O2 has already
rem inlined within this amalgamated TU.
rem NOT used: /fp:fast - fast_float does correct float round-trip parsing;
rem fast-math reordering can corrupt results. /GS stays on: parser eats untrusted
rem input, keep the buffer checks.
cl -nologo -MT -TC -O2 -arch:AVX2 /Gy /Gw -c ffc_impl.c

rem https://learn.microsoft.com/en-us/cpp/build/reference/lib-reference?view=msvc-170
rem create static library from COFF object files
lib -nologo ffc_impl.obj -out:..\lib\fast-float.lib

rem remove only our intermediate, not every .obj that happens to be in src\
del ffc_impl.obj

popd
endlocal
