package bench

// Benchmarks core:strconv text->number parsing (the reverse of formatting) for
// integers (parse_i64) and floats (parse_f64), across a few input-string lengths.
// Uses the Odin standard `core:time` benchmark harness.
//
// Run with optimizations:  just bench   (or: odin run bench -o:speed -microarch:native)

import ff ".."
import "core:fmt"
import "core:strconv"
import "core:time"

COUNT_ITERATIONS :: #config(COUNT_ITERATIONS, 1_000_000)

// The benchmarked input and accumulator sinks are package globals so the harness'
// fixed-signature bench procs can reach them. The sinks are read in teardown so the
// optimizer cannot drop the parse calls as dead code.
g_input: string
g_sink_i64: i64
g_sink_i32: i32
g_sink_f64: f64
g_sink_f32: f32

Case :: struct {
	name:  string,
	input: string,
}

// Integer inputs of increasing digit length, ending at i64::MAX (19 digits).
INT_CASES :: []Case {
	{"i64 short  (1 digit) ", "7"},
	{"i64 medium (6 digits)", "123456"},
	{"i64 long   (19 digits)", "9223372036854775807"},
}

// Integer inputs of increasing digit length, ending at i32::MAX (10 digits).
INT32_CASES :: []Case {
	{"i32 short  (1 digit) ", "7"},
	{"i32 medium (5 digits)", "12345"},
	{"i32 long   (10 digits)", "2147483647"},
}

// Float inputs of increasing length: few fraction digits -> many -> a long form
// with exponent (near f64::MAX).
FLOAT_CASES :: []Case {
	{"f64 short  (4 chars)  ", "3.14"},
	{"f64 medium (12 chars) ", "3.1415926535"},
	{"f64 long   (24 chars) ", "3.14159265358979311600"},
	{"f64 exp    (23 chars) ", "1.7976931348623157e308"},
}

// Same shapes for f32 (exponent form near f32::MAX).
FLOAT32_CASES :: []Case {
	{"f32 short  (4 chars) ", "3.14"},
	{"f32 medium (9 chars) ", "3.1415927"},
	{"f32 long   (16 chars)", "3.141592653589793"},
	{"f32 exp    (11 chars)", "3.40282347e38"},
}

bench_parse_i64 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: i64
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := strconv.parse_i64(g_input)
		acc += v
	}
	g_sink_i64 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_parse_i32 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: i32
	for _ in 0 ..< COUNT_ITERATIONS {
		// strconv has no parse_i32; parse_int returns a platform int, cast down.
		v, _ := strconv.parse_int(g_input)
		acc += i32(v)
	}
	g_sink_i32 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_parse_f64 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: f64
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := strconv.parse_f64(g_input)
		acc += v
	}
	g_sink_f64 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_parse_f32 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: f32
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := strconv.parse_f32(g_input)
		acc += v
	}
	g_sink_f32 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

// --- fast_float (C library) counterparts -----------------------------------

bench_ff_i64 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: i64
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := ff.parse_i64(g_input)
		acc += v
	}
	g_sink_i64 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_ff_i32 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: i32
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := ff.parse_i32(g_input)
		acc += v
	}
	g_sink_i32 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_ff_f64 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: f64
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := ff.parse_f64(g_input)
		acc += v
	}
	g_sink_f64 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

bench_ff_f32 :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
	acc: f32
	for _ in 0 ..< COUNT_ITERATIONS {
		v, _ := ff.parse_f32(g_input)
		acc += v
	}
	g_sink_f32 = acc
	options.count = COUNT_ITERATIONS
	options.processed = COUNT_ITERATIONS * len(g_input)
	return .Okay
}

run_case :: proc(c: Case, bench: type_of(bench_parse_i64)) {
	g_input = c.input
	options := &time.Benchmark_Options{bench = bench}
	time.benchmark(options)
	per_call := f64(time.duration_nanoseconds(options.duration)) / f64(COUNT_ITERATIONS)
	fmt.printfln("  %s  %.2f ns/call   %.2e calls/s   (%q)", c.name, per_call, options.rounds_per_second, c.input)
}

main :: proc() {
	fmt.printfln("strconv parse benchmarks (%v iterations each)\n", COUNT_ITERATIONS)

	fmt.println("i64 (text -> integer):")
	fmt.println("  strconv.parse_i64:")
	for c in INT_CASES {
		run_case(c, bench_parse_i64)
	}
	fmt.println("  fast_float.parse_i64:")
	for c in INT_CASES {
		run_case(c, bench_ff_i64)
	}

	fmt.println("\ni32 (text -> integer):")
	fmt.println("  strconv.parse_int->i32:")
	for c in INT32_CASES {
		run_case(c, bench_parse_i32)
	}
	fmt.println("  fast_float.parse_i32:")
	for c in INT32_CASES {
		run_case(c, bench_ff_i32)
	}

	fmt.println("\nf64 (text -> float):")
	fmt.println("  strconv.parse_f64:")
	for c in FLOAT_CASES {
		run_case(c, bench_parse_f64)
	}
	fmt.println("  fast_float.parse_f64:")
	for c in FLOAT_CASES {
		run_case(c, bench_ff_f64)
	}

	fmt.println("\nf32 (text -> float):")
	fmt.println("  strconv.parse_f32:")
	for c in FLOAT32_CASES {
		run_case(c, bench_parse_f32)
	}
	fmt.println("  fast_float.parse_f32:")
	for c in FLOAT32_CASES {
		run_case(c, bench_ff_f32)
	}

	// Read the sinks so the optimizer cannot eliminate the parse loops as dead code.
	fmt.printfln("\nsinks (ignore): i64=%v i32=%v f64=%v f32=%v", g_sink_i64, g_sink_i32, g_sink_f64, g_sink_f32)
}
