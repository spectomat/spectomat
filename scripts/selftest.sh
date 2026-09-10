#!/bin/bash
# Spectomat self-test — the helpers in utils.sh that parse or build text.
#
#   scripts/selftest.sh          tests the utils.sh next to it
#
# No dependencies and no network; runs in under a second. Everything else in
# scripts/ is orchestration, exercised by hand in a scratch repo (see .claude/CLAUDE.md).

set -uo pipefail

SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$SCRIPTS/utils.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no() {
  FAIL=$((FAIL+1))
  printf '  FAIL %s\n       want: %q\n       got:  %q\n' "$1" "$3" "$2"
}
is() { [[ "$2" == "$3" ]] && ok "$1" || no "$1" "$2" "$3"; }

# rt NAME TEMPLATE_BODY WANT KEY=VAL...
# The trailing X on both sides keeps the comparison byte-exact at end of file.
rt() {
  local name="$1" body="$2" want="$3"; shift 3
  printf '%s' "$body" > "$TMP/src"
  render_template "$TMP/src" "$TMP/dst" "$@" 2>/dev/null
  is "$name" "$(cat "$TMP/dst"; printf X)" "$want$(printf X)"
}

echo "render_template"
rt "single key"            'hello {{NAME}}'            'hello world'          NAME=world
rt "repeated key"          '{{A}}/{{A}}'               'x/x'                  A=x
rt "two keys"              '{{A}}-{{B}}'               'x-y'                  A=x B=y
rt "unknown key kept"      'a {{NOPE}} b'              'a {{NOPE}} b'         A=x
rt "empty value"           '[{{A}}]'                   '[]'                   A=
rt "value with ampersand"  '{{A}}'                     'me & you'             'A=me & you'
rt "value with backslash"  '{{A}}'                     'a\nb'                 'A=a\nb'
rt "value with slash"      '{{A}}'                     'a/b/c'                'A=a/b/c'
rt "value with dollar"     '{{A}}'                     'cost $5'              'A=cost $5'
rt "value with braces"     '{{A}}'                     '{{B}}'                'A={{B}}'
rt "trailing newlines"     $'x{{A}}\n\n'               $'xv\n\n'              A=v
rt "no trailing newline"   'x{{A}}'                    'xv'                   A=v
rt "multiline body"        $'{{A}}\nmid\n{{A}}'        $'v\nmid\nv'           A=v

# ep NAME INPUT yes|no — does INPUT carry the completion promise?
ep() {
  local got=no
  promised_empty "$2" && got=yes
  is "$1" "$got" "$3"
}

echo "promised_empty"
ep "bare tag"          '<promise>FACTORY EMPTY</promise>'                 yes
ep "surrounded"        'blah <promise>FACTORY EMPTY</promise> blah'       yes
ep "tag on own line"   $'text\n<promise>FACTORY EMPTY</promise>\nmore'    yes
ep "inner padding"     '<promise>  FACTORY EMPTY  </promise>'             yes
ep "inner newlines"    $'<promise>\nFACTORY\nEMPTY\n</promise>'          yes
ep "indented tags"     $'  <promise>\n\t FACTORY EMPTY\n  </promise>'    yes
ep "second of two"     '<promise>ONE</promise><promise>FACTORY EMPTY</promise>' yes
ep "lenient spacing"   '<promise>FACTORYEMPTY</promise>'                  yes
ep "other wording"     '<promise>ALL DONE</promise>'                      no
ep "wrong case"        '<promise>factory empty</promise>'                 no
ep "no tag"            'I am done, the factory is empty.'                 no
ep "no tag, exact"     'FACTORY EMPTY'                                    no
ep "unclosed tag"      'x <promise>FACTORY EMPTY'                         no
ep "empty input"       ''                                                 no
ep "empty tag"         '<promise></promise>'                              no

# jq is the only non-base dependency the scripts may take. This file names the
# forbidden command, so it has to leave itself out of its own scan.
echo "dependencies"
hits=$(grep -ln 'perl' "$SCRIPTS"/*.sh 2>/dev/null | grep -v '/selftest\.sh$' | tr '\n' ' ')
is "scripts invoke no perl" "${hits% }" ""

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
