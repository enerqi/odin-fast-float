package fast_float

// Odin bindings for the `ffc` C port of fast_float (Daniel Lemire's float parser).
//
// The static library is built from src/ffc.h via src/build.bat -> lib/fast-float.lib.
// Rebuild that first if the header changes:  cd src && .\build.bat
//
// The complete public ffc API (the FFC_API block of src/ffc.h) is bound below:
//   - the value-returning "simple" calls           (parse_*_simple)
//   - the stop-pointer calls returning ffc_result  (ffc_parse_*, ffc_from_chars_*)
//   - format options / presets                     (Parse_Options, Format, ffc_parse_options_default)
//   - JSON number parsing                          (ffc_parse_json_number, Json_Number)
// plus ergonomic Odin wrappers (string -> value/ok, or value/consumed/ok) over them.

import "core:c"

when ODIN_OS == .Windows {
	foreign import ffc "lib/fast-float.lib"
} else {
	foreign import ffc "lib/libfast-float.a"
}

// --- Types (mirror src/ffc.h) ---------------------------------------------------

// Outcome bitset returned in `ffc_result.outcome` and via the *_simple out-params.
Outcome :: enum c.uint32_t {
	Ok            = 0,
	Invalid_Input = 1,
	Out_Of_Range  = 2,
}

// Result of a stop-pointer call: `ptr` points one past the last consumed byte
// (== the start pointer on failure), `outcome` is the status.
Result :: struct {
	ptr:     [^]u8,
	outcome: Outcome,
}

// Accepted number formats. `Format` is a bit_set over these flags; the C side is a
// uint64_t with the same bit layout (note FFC leaves bit 1 unused: Fixed = 1<<2).
Format_Flag :: enum u64 {
	Scientific         = 0,
	Fixed              = 2,
	Hex                = 3,
	No_Infnan          = 4,
	Basic_Json         = 5,
	Basic_Fortran      = 6,
	Allow_Leading_Plus = 7,
	Skip_White_Space   = 8,
}
Format :: distinct bit_set[Format_Flag;u64]

// Presets matching FFC_PRESET_* in the header.
PRESET_GENERAL :: Format{.Fixed, .Scientific}
PRESET_JSON :: Format{.Basic_Json, .Fixed, .Scientific, .No_Infnan}
PRESET_JSON_OR_INFNAN :: Format{.Basic_Json, .Fixed, .Scientific}
PRESET_FORTRAN :: Format{.Basic_Fortran, .Fixed, .Scientific}

Parse_Options :: struct {
	format:        Format,
	decimal_point: u8, // '\0' means use '.'
}

// Detailed parse failure reasons (diagnostic enum mirrored from the header).
Parse_Outcome :: enum c.int {
	No_Error                           = 0,
	Json_Missing_Integer_After_Sign    = 1,
	Missing_Integer_Or_Dot_After_Sign  = 2,
	Json_Leading_Zeros_In_Integer_Part = 3,
	Json_No_Digits_In_Integer_Part     = 4,
	Json_No_Digits_In_Fractional_Part  = 5,
	No_Digits_In_Mantissa              = 6,
	Missing_Exponential_Part           = 7,
}

Json_Number_Kind :: enum c.uint32_t {
	Int64  = 0,
	Double = 1,
}

Json_Number :: struct {
	kind:  Json_Number_Kind,
	value: struct #raw_union {
		i64: i64,
		f64: f64,
	},
}

// --- Raw foreign bindings (1:1 with the C declarations) -------------------------
// `input`/`start`/`end` are (len, ptr) or [start, end) ranges, NOT NUL-terminated.

@(default_calling_convention = "c")
foreign ffc {
	ffc_parse_options_default :: proc() -> Parse_Options ---

	// f64
	ffc_parse_double_simple :: proc(len: c.size_t, input: [^]u8, outcome: ^Outcome) -> f64 ---
	ffc_parse_double :: proc(len: c.size_t, input: [^]u8, out: ^f64) -> Result ---
	ffc_from_chars_double :: proc(start: [^]u8, end: [^]u8, out: ^f64) -> Result ---
	ffc_from_chars_double_options :: proc(start: [^]u8, end: [^]u8, out: ^f64, options: Parse_Options) -> Result ---

	// f32
	ffc_parse_float_simple :: proc(len: c.size_t, input: [^]u8, outcome: ^Outcome) -> f32 ---
	ffc_parse_float :: proc(len: c.size_t, input: [^]u8, out: ^f32) -> Result ---
	ffc_from_chars_float :: proc(start: [^]u8, end: [^]u8, out: ^f32) -> Result ---
	ffc_from_chars_float_options :: proc(start: [^]u8, end: [^]u8, out: ^f32, options: Parse_Options) -> Result ---

	// integers (result-returning)
	ffc_parse_i64 :: proc(len: c.size_t, input: [^]u8, base: c.int, out: ^i64) -> Result ---
	ffc_parse_u64 :: proc(len: c.size_t, input: [^]u8, base: c.int, out: ^u64) -> Result ---
	ffc_parse_i32 :: proc(len: c.size_t, input: [^]u8, base: c.int, out: ^i32) -> Result ---
	ffc_parse_u32 :: proc(len: c.size_t, input: [^]u8, base: c.int, out: ^u32) -> Result ---

	// integers (simple value-returning)
	ffc_parse_i64_simple :: proc(len: c.size_t, input: [^]u8, base: c.int, outcome: ^Outcome) -> i64 ---
	ffc_parse_u64_simple :: proc(len: c.size_t, input: [^]u8, base: c.int, outcome: ^Outcome) -> u64 ---
	ffc_parse_i32_simple :: proc(len: c.size_t, input: [^]u8, base: c.int, outcome: ^Outcome) -> i32 ---
	ffc_parse_u32_simple :: proc(len: c.size_t, input: [^]u8, base: c.int, outcome: ^Outcome) -> u32 ---

	// JSON number ([start, end) -> int64 or double, tagged)
	ffc_parse_json_number :: proc(start: [^]u8, end: [^]u8, out: ^Json_Number) -> Result ---
}

// --- Odin-friendly wrappers: take a string, return (value, ok). -----------------
// On error the value is the library's 0 / 0.0 default and ok is false.

@(require_results)
parse_f64 :: #force_inline proc(s: string) -> (value: f64, ok: bool) {
	outcome: Outcome
	value = ffc_parse_double_simple(len(s), raw_data(s), &outcome)
	return value, outcome == .Ok
}

@(require_results)
parse_f32 :: #force_inline proc(s: string) -> (value: f32, ok: bool) {
	outcome: Outcome
	value = ffc_parse_float_simple(len(s), raw_data(s), &outcome)
	return value, outcome == .Ok
}

@(require_results)
parse_i64 :: #force_inline proc(s: string, base := 10) -> (value: i64, ok: bool) {
	outcome: Outcome
	value = ffc_parse_i64_simple(len(s), raw_data(s), c.int(base), &outcome)
	return value, outcome == .Ok
}

@(require_results)
parse_u64 :: #force_inline proc(s: string, base := 10) -> (value: u64, ok: bool) {
	outcome: Outcome
	value = ffc_parse_u64_simple(len(s), raw_data(s), c.int(base), &outcome)
	return value, outcome == .Ok
}

@(require_results)
parse_i32 :: #force_inline proc(s: string, base := 10) -> (value: i32, ok: bool) {
	outcome: Outcome
	value = ffc_parse_i32_simple(len(s), raw_data(s), c.int(base), &outcome)
	return value, outcome == .Ok
}

@(require_results)
parse_u32 :: #force_inline proc(s: string, base := 10) -> (value: u32, ok: bool) {
	outcome: Outcome
	value = ffc_parse_u32_simple(len(s), raw_data(s), c.int(base), &outcome)
	return value, outcome == .Ok
}

// --- Stop-pointer wrappers: also report how many bytes were consumed. -----------
// `n` is the count of bytes parsed from the front of `s`; the rest of `s` is `s[n:]`.
// Useful for strict end-of-input (require n == len(s)) or parsing a number stream.

@(private)
_consumed :: #force_inline proc(s: string, res: Result) -> int {
	return int(uintptr(rawptr(res.ptr)) - uintptr(raw_data(s)))
}

@(require_results)
parse_f64_prefix :: proc(s: string) -> (value: f64, n: int, ok: bool) {
	res := ffc_parse_double(len(s), raw_data(s), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_f32_prefix :: proc(s: string) -> (value: f32, n: int, ok: bool) {
	res := ffc_parse_float(len(s), raw_data(s), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_i64_prefix :: proc(s: string, base := 10) -> (value: i64, n: int, ok: bool) {
	res := ffc_parse_i64(len(s), raw_data(s), c.int(base), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_u64_prefix :: proc(s: string, base := 10) -> (value: u64, n: int, ok: bool) {
	res := ffc_parse_u64(len(s), raw_data(s), c.int(base), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_i32_prefix :: proc(s: string, base := 10) -> (value: i32, n: int, ok: bool) {
	res := ffc_parse_i32(len(s), raw_data(s), c.int(base), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_u32_prefix :: proc(s: string, base := 10) -> (value: u32, n: int, ok: bool) {
	res := ffc_parse_u32(len(s), raw_data(s), c.int(base), &value)
	return value, _consumed(s, res), res.outcome == .Ok
}

// Parse a float with explicit format options (locale decimal point, JSON/Fortran/hex
// modes, leading '+', skip whitespace). Build options from a preset, e.g.
//   opts := fast_float.Parse_Options{ format = fast_float.PRESET_JSON, decimal_point = '.' }
@(require_results)
parse_f64_opts :: proc(s: string, options: Parse_Options) -> (value: f64, n: int, ok: bool) {
	start := raw_data(s)
	res := ffc_from_chars_double_options(start, start[len(s):], &value, options)
	return value, _consumed(s, res), res.outcome == .Ok
}

@(require_results)
parse_f32_opts :: proc(s: string, options: Parse_Options) -> (value: f32, n: int, ok: bool) {
	start := raw_data(s)
	res := ffc_from_chars_float_options(start, start[len(s):], &value, options)
	return value, _consumed(s, res), res.outcome == .Ok
}

// Parse one JSON number from the front of `s`. `num.kind` selects which union field
// is valid (Int64 -> num.value.i64, Double -> num.value.f64).
@(require_results)
parse_json_number :: proc(s: string) -> (num: Json_Number, n: int, ok: bool) {
	start := raw_data(s)
	res := ffc_parse_json_number(start, start[len(s):], &num)
	return num, _consumed(s, res), res.outcome == .Ok
}
