#!/bin/bash
# log.sh — the one writer of log.md's line format.
#
#   tests/log_test.sh              tests ../scripts
#   tests/log_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "log.sh"

run() { ( cd "$FIXTURE" && bash "$SCRIPTS/log.sh" "$@" >/dev/null 2>&1 ); }
last_line() { tail -1 "$FIXTURE/.spectomat/log.md"; }

floor one
run SPECIFY 001-a 'spec written, 3 assumptions'
is "exit 0 on success" "$?" "0"
is "the line names the phase" "$(last_line | grep -c '· SPECIFY ·')" "1"
is "the line names the slug" "$(last_line | grep -c '· 001-a ·')" "1"
is "the line carries the message" "$(last_line | grep -c 'spec written, 3 assumptions')" "1"
is "the line starts with a dash" "$(last_line | grep -c '^- ')" "1"
is "the line carries a UTC timestamp" "$(last_line | grep -Ec '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z ·')" "1"

floor multi
run SPECIFY 001-a 'first'
run REVIEW 001-a 'second'
is "two calls append two lines" "$(grep -c '^- ' "$FIXTURE/.spectomat/log.md")" "2"
is "earlier lines are not rewritten" "$(grep -c 'first' "$FIXTURE/.spectomat/log.md")" "1"

floor missing
rm -f "$FIXTURE/.spectomat/log.md"
run IMPLEMENT 001-a 'Task 1/1 done'
is "a missing log.md is created" "$([[ -e "$FIXTURE/.spectomat/log.md" ]] && echo yes || echo no)" "yes"
is "the header is written" "$(head -1 "$FIXTURE/.spectomat/log.md")" "# Spectomat factory log"
is "the line still lands" "$(grep -c 'Task 1/1 done' "$FIXTURE/.spectomat/log.md")" "1"

floor usage
run '' '' ''
is "no phase or slug is refused" "$?" "1"
run SPECIFY 001-a ''
is "no message is refused" "$?" "1"

finish
