package main

// Minimal runnable demo of the fast_float bindings.
//   just example     (or: odin run examples)

import ff ".."
import "core:fmt"

main :: proc() {
	fmt.println("fast_float parsing demo\n")

	floats := []string{"3.14", "1.7976931348623157e308", "-0.0", "1e-300", "nope"}
	fmt.println("parse_f64:")
	for s in floats {
		v, ok := ff.parse_f64(s)
		fmt.printfln("  %-26q -> %v	ok=%v", s, v, ok)
	}

	fmt.println("\nparse_f32:")
	f32s := []string{"2.71828", "3.40282347e38", "0.1"}
	for s in f32s {
		v, ok := ff.parse_f32(s)
		fmt.printfln("  %-26q -> %v	ok=%v", s, v, ok)
	}

	fmt.println("\nparse_i64 (base 10):")
	ints := []string{"7", "9223372036854775807", "-42", "12.5"}
	for s in ints {
		v, ok := ff.parse_i64(s)
		fmt.printfln("  %-26q -> %v	ok=%v", s, v, ok)
	}

	fmt.println("\nparse_i32 / parse_u32:")
	iv, iok := ff.parse_i32("2147483647")
	uv, uok := ff.parse_u32("4294967295")
	fmt.printfln("  i32 max -> %v ok=%v", iv, iok)
	fmt.printfln("  u32 max -> %v ok=%v", uv, uok)

	fmt.println("\nparse_i64 base 16:")
	hv, hok := ff.parse_i64("ff", 16)
	fmt.printfln("  %-26q -> %v	ok=%v", "ff", hv, hok)

	// stop-pointer API: value + bytes consumed (the rest of the string is s[n:]).
	fmt.println("\nprefix parsing (value, consumed, ok):")
	pstr := "3.14abc"
	pv, pn, pok := ff.parse_f64_prefix(pstr)
	fmt.printfln("  %-26q -> %v  n=%v ok=%v  rest=%q", pstr, pv, pn, pok, pstr[pn:])
	sstr := "42, 7"
	sv, sn, sok := ff.parse_i64_prefix(sstr)
	fmt.printfln("  %-26q -> %v  n=%v ok=%v  rest=%q", sstr, sv, sn, sok, sstr[sn:])

	// strict end-of-input: require all bytes consumed.
	xstr := "1.5x"
	_, n, ok := ff.parse_f64_prefix(xstr)
	fmt.printfln("  strict %q -> ok=%v (n=%v of %v)", xstr, ok && n == len(xstr), n, len(xstr))

	// format options (by-value struct across FFI).
	fmt.println("\noptions (JSON preset rejects inf/nan):")
	jopts := ff.Parse_Options {
		format        = ff.PRESET_JSON,
		decimal_point = '.',
	}
	jv, _, jok := ff.parse_f64_opts("1e3", jopts)
	iv2, _, iok2 := ff.parse_f64_opts("inf", jopts)
	fmt.printfln("  %-26q -> %v ok=%v", "1e3", jv, jok)
	fmt.printfln("  %-26q -> %v ok=%v (inf rejected under JSON)", "inf", iv2, iok2)

	// JSON number: tagged int-or-double union.
	fmt.println("\nJSON numbers (tagged union):")
	jsons := []string{"123", "-45.6e2"}
	for s in jsons {
		num, _, nok := ff.parse_json_number(s)
		if num.kind == .Int64 {
			fmt.printfln("  %-26q -> i64 %v ok=%v", s, num.value.i64, nok)
		} else {
			fmt.printfln("  %-26q -> f64 %v ok=%v", s, num.value.f64, nok)
		}
	}
}
