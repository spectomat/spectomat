#!/bin/bash
# Spectomat verification gates for /Users/alex/Projects/spectomat.
#
# The single gate command of this project. Run from the repository root, once
# per task in the IMPLEMENT phase before that task's commit, and once in the
# ARCHIVE phase before archiving. Exit 0 means every gate passed.
#
# This file was generated once, from the scripts package.json defined at the
# time. It is yours to edit: add, remove or reorder the lines below. `set -e`
# stops at the first failure, so the exit code always means what it says.
# Never weaken a gate to make an iteration pass.

set -e
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# No gates detected. Add this repo's gates below, one per line:
#   npm run typecheck
#   npm run lint
#   npm test

echo "ok: no gates yet — add them above"
