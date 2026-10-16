#!/bin/zsh
# Runs the end-to-end build test with real tools. Downloads the 240 MB runtime on first run.
set -euo pipefail
cd "${0:A:h:h}"
GAMEWRAP_INTEGRATION=1 swift test --scratch-path "${TMPDIR:-/tmp/}gamewrap-build" --filter IntegrationTests
