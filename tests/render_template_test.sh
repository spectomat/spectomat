#!/bin/bash
# render_template — the {{KEY}} substitution helper in utils.sh.
#
#   tests/render_template_test.sh              tests ../scripts
#   tests/render_template_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
rt "ampersand twice"       '{{A}}/{{A}}'               'a&b/a&b'              'A=a&b'
rt "lone ampersand"        '[{{A}}]'                   '[&]'                  'A=&'
rt "ampersand with text"   'x {{A}} y'                 'x p&q r&s y'          'A=p&q r&s'
rt "value with backslash"  '{{A}}'                     'a\nb'                 'A=a\nb'
rt "value with slash"      '{{A}}'                     'a/b/c'                'A=a/b/c'
rt "value with dollar"     '{{A}}'                     'cost $5'              'A=cost $5'
rt "value with braces"     '{{A}}'                     '{{B}}'                'A={{B}}'
rt "trailing newlines"     $'x{{A}}\n\n'               $'xv\n\n'              A=v
rt "no trailing newline"   'x{{A}}'                    'xv'                   A=v
rt "multiline body"        $'{{A}}\nmid\n{{A}}'        $'v\nmid\nv'           A=v

finish
