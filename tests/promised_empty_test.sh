#!/bin/bash
# promised_empty — the <promise>FACTORY EMPTY</promise> detector in utils.sh.
#
#   tests/promised_empty_test.sh              tests ../scripts
#   tests/promised_empty_test.sh DIR          tests the scripts in DIR

set -uo pipefail
SCRIPTS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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

finish
