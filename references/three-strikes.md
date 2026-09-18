# Three strikes

The canonical procedure for a phase that defeated you, and for the third strike
that blocks a slug. Every phase brief cites this file rather than restating it.

## A strike

A phase that defeated you is a strike, not a retry. Never attempt the phase a
second time in the same iteration.

1. Bump the slug's strike count for this phase with `scripts/utils.sh`'s
   `slug_strike <slug> <PHASE>`. It prints the new count — N below is that
   number, never one you counted by hand.
2. Leave the tree clean. `state.json`, `log.md` and `work/` are gitignored and
   never count as dirt.
3. Run `log.sh <PHASE> <slug> <reason> (strike N)` — see
   [Log Format](./log-format.md).
4. Stop. Do not advance the slug's phase in `state.json`: a strike changes
   nothing but the strike count.

Under three, the next iteration's picker skips this slug in favour of the
following candidate in the same stage.

## The third strike

On the third strike the slug is blocked and leaves the flow. Both steps happen
in the same iteration, in this order:

1. Write `.spectomat/<slug>/blocked.md` naming the phase and the reason, and
   commit it.
2. Run `bash <plugin_root>/scripts/block_slug.sh <slug> "<reason>"`, then log
   the reason.

**The order is load-bearing.** The state call is what takes the slug out of the
flow, so a marker written without it leaves the slug at its phase with three
strikes against it — the picker skips it, finds no other candidate, and sends
every remaining iteration to the janitor. Writing the marker first keeps any
commit from describing a state change that did not happen.

The marker is the committed record: `state.json` is gitignored, so `blocked.md`
is the only trace of how the slug ended that survives in git. Nothing moves and
nothing is deleted — the trail stays in the slug dir for the operator to read,
and the blocked slug shows in `/spectomat:status`.
