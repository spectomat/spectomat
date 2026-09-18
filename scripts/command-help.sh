#!/bin/bash
# Spectomat help — prints the user guide and the glossary verbatim.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

cat "$PLUGIN_ROOT/docs/guide.md"
cat "$PLUGIN_ROOT/references/glossary.md"
