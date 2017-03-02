#!/bin/bash

# Fail on the first error, and print every command as it is executed.
set -e

if [[ "${TRAVIS_RUST_VERSION}" != "nightly" ]]; then
  echo "Not fuzzing because we are not building on nightly."
  exit 0
fi

cd fuzz

# Clone the required libfuzzer crate sources. Cargo-fuzz does this
# automatically, but because we cannot pass it args we have to do it manually.
if [[ ! -d libfuzzer ]]; then
  echo "Cloning libfuzzer ..."
  git clone --depth=1 https://github.com/rust-fuzz/libfuzzer-sys.git libfuzzer

  # Also compile it.
  cd libfuzzer
  cargo build --release
  cd ..
fi

# Pre-populate the corpus with the test samples, if they did not exist already.
mkdir -p corpus
cp --update ../testsamples/*.flac corpus
cp --update ../testsamples/fuzz/*.flac corpus

# Compile Claxon with fuzzing support. This command line is based on the one
# generated by cargo-fuzz.
echo "Compiling Claxon with fuzzer enabled ..."
mkdir -p target/debug/deps
rustc --crate-name claxon ../src/lib.rs \
      --crate-type lib \
      --emit=dep-info,link \
      -C debuginfo=2 \
      -C metadata=e8a30fe69d34bd17 \
      -C extra-filename=-e8a30fe69d34bd17 \
      --out-dir target/debug/deps \
      -L dependency=target/debug/deps \
      -Cpasses=sancov \
      -Cllvm-args=-sanitizer-coverage-level=3 \
      -Zsanitizer=address \
      -Cpanic=abort

# Compile the fuzzer binary.
echo "Compiling fuzzer ..."
rustc --crate-name decode_full fuzzers/decode_full.rs \
      --crate-type bin \
      -C debuginfo=2 \
      -L libfuzzer/target/release \
      -C metadata=0dcaee2e3d91d450 \
      -C extra-filename=-0dcaee2e3d91d450 \
      -o target/debug/decode-full \
      -L dependency=target/debug/deps \
      --extern claxon=target/debug/deps/libclaxon-e8a30fe69d34bd17.rlib \
      -Cpasses=sancov \
      -Cllvm-args=-sanitizer-coverage-level=3 \
      -Zsanitizer=address \
      -Cpanic=abort

echo "Running fuzzer for ${FUZZ_SECONDS:-10} seconds ..."

# Disable leak detection, because when the fuzzer terminates after the set
# timeout, it might leak because it is in the middle of an iteration, but then
# the leak sanitizer will report that and exit with a nonzero exit code, while
# actually everything is fine.
export ASAN_OPTIONS="detect_leaks=0"

# Set max length to a small-ish number (in comparison to the test samples), as
# the coverage is similar (it is a harder to find a few elusive paths), but
# every iteration runs much faster. Warn about slow runs, as every iteration
# should execute in well below a second. Disable the leak sanitizer, otherwise
# it reports a leak when the fuzzer exits after the given total time.
target/debug/decode-full \
  -max_len=2048 \
  -report_slow_units=1 \
  -max_total_time=${FUZZ_SECONDS:-10} \
  -print_final_stats=1 \
  -detect_leaks=0 \
  corpus
