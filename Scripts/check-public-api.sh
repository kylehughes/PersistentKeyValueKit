#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

swift build
build_path=$(swift build --show-bin-path)
# The native build system emits modules under `Modules`; Swift Build emits them in the bin path itself.
module_path="$build_path/Modules"

check_fixture() {
    local fixture="$1"
    local expected="$2"
    local output
    if output=$(swiftc -warnings-as-errors -typecheck -I "$module_path" -I "$build_path" "$fixture" 2>&1); then
        echo "Expected compilation to fail: $fixture" >&2
        exit 1
    fi
    if ! grep -Fq "$expected" <<<"$output"; then
        echo "Unexpected diagnostic for $fixture (expected: $expected)" >&2
        echo "$output" >&2
        exit 1
    fi
}

check_fixture Tests/CompileFail/MissingRepresentation.swift "does not conform to protocol 'PersistentKeyValueRepresentation'"
check_fixture Tests/CompileFail/MissingPrimitive.swift "does not conform to protocol 'PrimitiveKeyValuePersistible'"
check_fixture Tests/CompileFail/EndpointConstruction.swift "initializer is inaccessible"
check_fixture Tests/CompileFail/BackendAccess.swift "'backend' is inaccessible due to 'internal' protection level"
check_fixture Tests/CompileFail/IdentityAccess.swift "has no member 'identity'"
check_fixture Tests/CompileFail/SnapshotAccess.swift "has no member 'snapshot'"
check_fixture Tests/CompileFail/WriteAccess.swift "has no member 'prepareWrite'"
check_fixture Tests/CompileFail/OperationAccess.swift "has no member 'commitWrite'"
check_fixture Tests/CompileFail/MissingMigrationEndpoint.swift "does not conform to protocol 'PersistentKeyValueStore'"

echo "Public API compile-fail checks passed."
