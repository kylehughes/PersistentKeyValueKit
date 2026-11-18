#!/usr/bin/env bash
# Builds the DocC archive that the documentation deployment publishes, treating every DocC warning as an error.
#
# Usage: bash Scripts/check-documentation-build.sh [derived-data-path]
#
# The archive is written to `<derived-data-path>/Build/Products/Debug-iphoneos/PersistentKeyValueKit.doccarchive`.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

derived_data_path="${1:-$repo_root/.build/DocumentationDerivedData}"

xcodebuild docbuild \
    -scheme PersistentKeyValueKit \
    OTHER_DOCC_FLAGS="--warnings-as-errors" \
    -derivedDataPath "$derived_data_path" \
    -destination 'generic/platform=iOS'

echo "Documentation build passed."
