#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path .build/module-cache \
  'Image Converter/ImageConversion.swift' \
  'Image Converter/ContentView.swift' Tests/RegressionTests.swift \
  -o .build/regression-tests
# A dedicated temporary directory also works where macOS blocks unsigned helpers in Documents.
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/image-converter-regression.XXXXXX")"
cp .build/regression-tests "$fixture_dir/regression-tests"
"$fixture_dir/regression-tests" "$fixture_dir/fixtures"
