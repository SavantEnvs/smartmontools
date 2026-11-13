#!/usr/bin/env bash
#
# mayhem/build.sh — builds smartmontools three ways, all out of tree under mayhem/_build/:
#   fuzz/  libsmartmon + the smartctl/smartd objects with ASan+UBSan+SanCov, linked into the
#          fuzz harnesses (/mayhem/fuzz_*) and their -standalone reproducers
#   test/  the normal-flag smartctl that mayhem/test.sh runs
# Runs inside the commit image as `mayhem` in /mayhem, and must also work offline and after
# `git clean -ffdX` (autogen output, configure output and mayhem/_build are all gitignored).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
BUILD="$SRC/mayhem/_build"
FUZZ="$BUILD/fuzz"
TEST="$BUILD/test"
mkdir -p "$BUILD"

# autogen.sh creates configure and the Makefile.in files (all gitignored upstream)
if [ ! -f configure ] || [ ! -f src/Makefile.in ] || [ ! -f lib/Makefile.in ]; then
  ./autogen.sh
fi

# 1) sanitized + SanCov build of the library and of the program objects the harnesses link
FUZZ_CXXFLAGS="$SANITIZER_FLAGS -O1 $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
mkdir -p "$FUZZ"
if [ ! -f "$FUZZ/Makefile" ]; then
  (cd "$FUZZ" && "$SRC/configure" --disable-shared CC="$CC" CXX="$CXX" \
     CFLAGS="$FUZZ_CXXFLAGS" CXXFLAGS="$FUZZ_CXXFLAGS" LDFLAGS="$SANITIZER_FLAGS")
fi
make -C "$FUZZ/include" -j"$MAYHEM_JOBS"
make -C "$FUZZ/lib" -j"$MAYHEM_JOBS" libsmartmon.la
make -C "$FUZZ/src" -j"$MAYHEM_JOBS" ataidentify.o ataprint.o farmprint.o nvmeprint.o scsiprint.o popen_as_ugid.o

# 2) harnesses (+ standalone reproducers)
INC=(-DHAVE_CONFIG_H -I"$FUZZ/src" -I"$SRC/src" -I"$FUZZ" -I"$FUZZ/include" -I"$SRC/include" -I"$FUZZ/lib"
     '-DBUILD_INFO="(local build)"' '-DSMARTMONTOOLS_SYSCONFDIR="/usr/local/etc"'
     '-DSMARTMONTOOLS_SMARTDSCRIPTDIR="/usr/local/etc"' '-DSMARTMONTOOLS_DRIVEDBDIR="/usr/local/share/smartmontools"')
CXXF=($SANITIZER_FLAGS -O1 $DEBUG_FLAGS -fsanitize=fuzzer-no-link -std=gnu++11)
LINKF=($SANITIZER_FLAGS $DEBUG_FLAGS)
LIB="$FUZZ/lib/.libs/libsmartmon.a"
H="$SRC/mayhem"
OBJ="$FUZZ/mayhem-obj"
mkdir -p "$OBJ"

$CC "${LINKF[@]}" -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
$CXX "${LINKF[@]}" -c "$H/lsan_off.cc" -o "$OBJ/lsan_off.o"
# smartctl.cpp again, with its main() renamed so the libFuzzer main takes over
$CXX "${CXXF[@]}" "${INC[@]}" -Dmain=smartctl_original_main -c "$SRC/src/smartctl.cpp" -o "$OBJ/smartctl.o"
PROGOBJ=("$OBJ/smartctl.o" "$FUZZ/src/ataidentify.o" "$FUZZ/src/ataprint.o" "$FUZZ/src/farmprint.o"
         "$FUZZ/src/nvmeprint.o" "$FUZZ/src/scsiprint.o")

build_target() { # <name> <extra link objects...>
  local t="$1"; shift
  $CXX "${CXXF[@]}" "${INC[@]}" -c "$H/$t/$t.cpp" -o "$OBJ/$t.o"
  $CXX "${LINKF[@]}" $LIB_FUZZING_ENGINE "$OBJ/$t.o" "$@" "$OBJ/lsan_off.o" "$LIB" -o "$SRC/$t"
  $CXX "${LINKF[@]}" "$OBJ/$t.o" "$OBJ/standalone_main.o" "$@" "$OBJ/lsan_off.o" "$LIB" -o "$SRC/$t-standalone"
}
build_target fuzz_ataioctl "${PROGOBJ[@]}"
build_target fuzz_drivedb
build_target fuzz_smartd_conf "$FUZZ/src/popen_as_ugid.o"

# 3) the normal-flag build that mayhem/test.sh runs (no sanitizers, no SanCov)
mkdir -p "$TEST"
if [ ! -f "$TEST/Makefile" ]; then
  (cd "$TEST" && env -u CFLAGS -u CXXFLAGS -u LDFLAGS "$SRC/configure" --disable-shared CC="$CC" CXX="$CXX" \
     CFLAGS="-O2 $COVERAGE_FLAGS" CXXFLAGS="-O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS")
fi
make -C "$TEST/include" -j"$MAYHEM_JOBS"
make -C "$TEST/lib" -j"$MAYHEM_JOBS" libsmartmon.la
make -C "$TEST/src" -j"$MAYHEM_JOBS" smartctl
