#!/bin/bash
# Spectomat tasks — the CLI over one slug's task ledger,
# `.spectomat/<slug>/tasks.json`. A thin front for the tasks_* helpers in
# utils.sh, for a brief's `!` block or an agent's own Bash calls:
#
#   scripts/tasks.sh write <slug> '<json array>'   PLAN: write the ledger, no phase move
#   scripts/tasks.sh init  <slug> '<json array>'   the same, then -> IMPLEMENT
#   scripts/tasks.sh start <slug>                  -> IMPLEMENT, ledger already written
#   scripts/tasks.sh add   <slug> '<json array>'   REVIEW: append fix tasks, -> IMPLEMENT
#   scripts/tasks.sh next  <slug>                  the next ready task's id, or empty
#   scripts/tasks.sh show  <slug> [id]             the ledger, or one task, as JSON
#   scripts/tasks.sh count <slug> [status]         how many tasks, or how many at status
#   scripts/tasks.sh close <slug> <id> <commits> <tests> <gates>
#                                                  record the evidence, -> REVIEW when last
#
# The ledger is committed, so PLAN writes it before its commit and moves the
# phase after: `write` then `start`. `init` does both at once, for RECOVER and
# for anything that is not building a commit around the file.
#
# `write`, `init` and `add` read their JSON from stdin when the argument is `-`
# or absent. The task shape is documented above tasks_init in utils.sh.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
cd_root

usage() {
  die "usage: tasks.sh write|init|start|add|next|show|count|close <slug> [args]"
}

require_ledger() {
  [[ -f "$(tasks_file "$1")" ]] || die "no ledger for $1 — PLAN writes it"
}

main() {
  local cmd="${1:-}" slug="${2:-}"
  [[ -n "$cmd" && -n "$slug" ]] || usage
  [[ -f "$STATE_FILE" ]] || die "no $STATE_FILE — is a flow armed?"
  shift 2

  case "$cmd" in
    write)
      tasks_write "$slug" "${1:--}" || die "could not write $(tasks_file "$slug")"
      echo "$(tasks_file "$slug"): $(tasks_count "$slug") tasks"
      ;;
    init)
      tasks_init "$slug" "${1:--}" || die "could not write $(tasks_file "$slug")"
      echo "$slug -> IMPLEMENT, $(tasks_count "$slug") tasks"
      ;;
    start)
      require_ledger "$slug"
      tasks_start "$slug"
      echo "$slug -> IMPLEMENT, $(tasks_count "$slug") tasks"
      ;;
    add)
      require_ledger "$slug"
      tasks_add "$slug" "${1:--}" || die "could not append to $(tasks_file "$slug")"
      echo "$slug -> IMPLEMENT, $(tasks_pending "$slug") pending of $(tasks_count "$slug")"
      ;;
    next)
      require_ledger "$slug"
      task_next "$slug"
      ;;
    show)
      require_ledger "$slug"
      if [[ -n "${1:-}" ]]; then
        jq --arg i "$1" '.tasks[] | select(.id == ($i | tonumber))' "$(tasks_file "$slug")"
      else
        cat "$(tasks_file "$slug")"
      fi
      ;;
    count)
      tasks_count "$slug" "${1:-}"
      ;;
    close)
      [[ $# -eq 4 ]] || die "usage: tasks.sh close <slug> <id> <commits> <tests> <gates>"
      require_ledger "$slug"
      [[ -n "$(jq -r --arg i "$1" '.tasks[] | select(.id == ($i | tonumber)) | .id' "$(tasks_file "$slug")")" ]] \
        || die "no task $1 in $(tasks_file "$slug")"
      [[ "$(jq -r --arg i "$1" '.tasks[] | select(.id == ($i | tonumber)) | .status' "$(tasks_file "$slug")")" != "done" ]] \
        || die "task $1 is already closed — one task closes once"
      task_close "$slug" "$@" || die "could not close task $1"
      echo "$slug task $1 closed, $(tasks_pending "$slug") pending, phase $(slug_phase "$slug")"
      ;;
    *) usage ;;
  esac
}

main "$@"
