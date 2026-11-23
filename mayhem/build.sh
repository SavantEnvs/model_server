#!/usr/bin/env bash
#
# mayhem/build.sh — build this repo's fuzz harness(es).
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# OVMS's official build is Bazel over MediaPipe/TensorFlow/gRPC/OpenCV (hours, network). The fuzzed
# parsers are self-contained C++ sources, so they are compiled directly here against the same
# pinned dependencies upstream's WORKSPACE uses (cached in the image, see mayhem/Dockerfile) and
# the prebuilt OpenVINO runtime at /opt/intel/openvino.
DEPS=/opt/toolchains/deps
OV=/opt/intel/openvino/runtime
OUT="$SRC/mayhem/out"
INCS=(-I"$SRC" -I"$SRC/src" -I"$SRC/mayhem/harnesses"
      -I"$DEPS/rapidjson-973dc9c0/src/include" -I"$DEPS/spdlog-1.15.3/src/include"
      -I"$DEPS/mediapipe-2bce9dd1/src" -I"$DEPS/fmt-11.2.0/src/include" -I"$DEPS/stb-5c205738/src" -I"$DEPS/dr_libs-47a4f08e/src"
      -I"$DEPS/minitrace-020f42b1/src"
      -isystem "$OV/include")
DEFS=(-std=c++20 -DSPDLOG_FMT_EXTERNAL -DFMT_HEADER_ONLY)
OVLIBS=(-L"$OV/lib/intel64" -L"$OV/3rdparty/tbb/lib" -lopenvino_genai -lopenvino -ltbb -labsl_status -labsl_statusor -labsl_strings -lcrypto -ldl -lpthread -lm
        -Wl,-rpath,"$OV/lib/intel64" -Wl,-rpath,"$OV/3rdparty/tbb/lib")

# Project sources under test (+ what they need to link).
LIB_SRCS=(src/status.cpp src/logging.cpp src/utils/env_guard.cpp src/stringutils.cpp
          src/audio/audio_utils.cpp src/llm/io_processing/partial_json_builder.cpp
          src/image_utils/image_decoder.cpp src/image_utils/decoded_image_size.cpp
          src/schema.cpp
          src/llm/io_processing/chat_template/analyzer.cpp src/llm/io_processing/chat_template/probe.cpp
          src/llm/io_processing/chat_template/adjuster.cpp
          src/llm/io_processing/chat_template/adjustments/remove_filters_adjustment.cpp
          src/llm/io_processing/chat_template/adjustments/remove_function_params_adjustment.cpp
          src/tokenize/tokenize_parser.cpp
          src/image_gen/imagegenutils.cpp
          src/image_utils/image_conversion.cpp)  # also compiles the stb implementation (STB_*_IMPLEMENTATION), as upstream does

# compile <objdir> <flags...> -- <srcs...> : prints the object list
compile() {
  local dir="$1"; shift; local flags=(); while [ "$1" != "--" ]; do flags+=("$1"); shift; done; shift
  mkdir -p "$dir"
  local pids=() objs=() s o n=0
  for s in "$@"; do
    o="$dir/$(echo "$s" | tr '/' '_').o"; objs+=("$o")
    local extra=()
    # audio_utils.cpp compiles dr_wav/dr_mp3 (DR_*_IMPLEMENTATION). dr_wav's drwav_f32_to_s16 casts a
    # NaN float sample to int (dr_wav.h:7117) and then subtracts 32768 from INT_MIN (dr_wav.h:7118),
    # which UBSan reports within ~10 execs of any float WAV, so float-cast-overflow and
    # signed-integer-overflow are relaxed for this file only; ASan and the rest of UBSan stay halting.
    [ "$s" = src/audio/audio_utils.cpp ] && [ -n "$SANITIZER_FLAGS" ] && \
      extra=(-fno-sanitize=float-cast-overflow,signed-integer-overflow)
    "$CXX" "${flags[@]}" "${extra[@]}" "${DEFS[@]}" "${INCS[@]}" -c "$SRC/$s" -o "$o" &
    pids+=($!); n=$((n+1))
    if [ "$n" -ge "$MAYHEM_JOBS" ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); n=$((n-1)); fi
  done
  for p in "${pids[@]}"; do wait "$p"; done
  COMPILED=("${objs[@]}")
}

# 1) Sanitized + DWARF-3 project objects and harnesses.
FUZZ_FLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link)
compile "$OUT/obj-fuzz" "${FUZZ_FLAGS[@]}" -- "${LIB_SRCS[@]}"
LIB_OBJS=("${COMPILED[@]}")
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/obj-fuzz/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/obj-fuzz/standalone_main.o"

for h in fuzz_partial_json fuzz_audio fuzz_image_decode fuzz_chat_template fuzz_config_schema fuzz_tokenize fuzz_image_gen_options; do
  compile "$OUT/obj-fuzz" "${FUZZ_FLAGS[@]}" -- "mayhem/harnesses/$h.cpp"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${COMPILED[@]}" "${LIB_OBJS[@]}" \
      "$OUT/obj-fuzz/lsan_off.o" "${OVLIBS[@]}" -o "$OUT/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/obj-fuzz/standalone_main.o" "${COMPILED[@]}" "${LIB_OBJS[@]}" \
      "$OUT/obj-fuzz/lsan_off.o" "${OVLIBS[@]}" -o "$OUT/$h-standalone"
done

# 2) Upstream's own unit tests for this code (googletest), with normal flags, for mayhem/test.sh.
TEST_SRCS=(src/test/llm/output_parsers/partial_json_builder_test.cpp src/test/audio/audio_utils_test.cpp
           src/test/image_decoder_test.cpp src/test/schema_test.cpp src/test/llm/chat_template_adjuster_test.cpp
           src/test/tokenize_parser_test.cpp src/test/llm/chat_template_analyzer_test.cpp
           src/test/stringutils_test.cpp src/test/decoded_image_size_test.cpp src/test/platform_utils.cpp)
compile "$OUT/obj-test" -O1 -g $COVERAGE_FLAGS -- "${LIB_SRCS[@]}" "${TEST_SRCS[@]}"
$CXX $COVERAGE_FLAGS "${COMPILED[@]}" -lgmock -lgtest_main -lgtest "${OVLIBS[@]}" -o "$OUT/ovms_unit_tests"

ls -l "$OUT"
