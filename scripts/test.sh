#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/test_portable.py
if command -v swiftc >/dev/null 2>&1; then
  mkdir -p build/module-cache
  swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Settings.swift \
    Sources/ConfigurationLifecycle.swift Sources/ToolbarAction.swift tests/main.swift -o build/core-tests
  FOLDERTERM_TEST_ROOT="$PWD/build/test-artifacts" build/core-tests
  xcrun clang -c Sources/ToolbarAliasBridge.c -o build/ToolbarAliasBridge-tests.o
  swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
    -import-objc-header Sources/ToolbarAliasBridge.h build/ToolbarAliasBridge-tests.o Sources/Core.swift \
    Sources/ToolbarPreferencesModel.swift Sources/ToolbarReference.swift Sources/ToolbarTransaction.swift \
    Sources/FinderToolbarStore.swift Sources/ToolbarInstaller.swift \
    tests/toolbar/main.swift -o build/toolbar-tests
  FOLDERTERM_TEST_ROOT="$PWD/build/test-artifacts" build/toolbar-tests
else
  echo 'SKIP: native Swift core tests (swiftc unavailable). Portable tests do not compile or execute the Swift app.'
fi
