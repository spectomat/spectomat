# Log Format

`log.md` is append-only; never edit an earlier line. Its format is not yours to
compose: run `bash <plugin_root>/scripts/log.sh <PHASE> <slug> <message>` and it
writes the line — timestamp, `·` separators and all — deterministically. Never
`printf`, `echo >>` or otherwise hand-write a line into `log.md`; `log.sh` is
the only writer. No commit SHA in the message: `git log` is the ledger of
commits, this file the ledger of phases.

The message is numbers, never adjectives — `Task 2/6 done · tests 41/41`, not
"tests mostly passing". A log line without numbers did not run the gates. A
strike ends the message `(strike N: <reason>)`, N from `slug_strike`'s own
output, not counted by hand — see [Three strikes](./three-strikes.md).

`log.md` is gitignored: the line enters no commit and never counts as dirt.
