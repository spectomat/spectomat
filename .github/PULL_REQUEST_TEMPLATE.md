<!-- Terms used here are defined in references/glossary.md. -->

## What changed

<!-- One or two lines. -->

## Why

<!-- The problem this solves. Link an issue if there is one. -->

## Checks

- [ ] `claude plugin validate .claude-plugin/plugin.json --strict` passes
- [ ] `claude plugin validate .claude-plugin/marketplace.json --strict` passes
- [ ] `bash -n scripts/*.sh tests/*.sh templates/gates.sh` passes
- [ ] `scripts/selftest.sh` passes
- [ ] Exercised a real flow in a scratch git repo, not in this checkout — or the change cannot affect the runtime

## Documentation

- [ ] Behaviour this change alters is described in `docs/specification.md`, not only in prose
- [ ] A rule binding every phase went into `templates/contract.md`'s Constitution, not into a brief
- [ ] The verdict grammar stays in step across `scripts/phase.sh`, `pointer_prompt` in `scripts/utils.sh`, `scripts/print.sh` and `scripts/agent-archive.sh`
- [ ] Third-party material and its licence are listed in `NOTICE.md`
- [ ] Version in `.claude-plugin/plugin.json` bumped, if this ships to users
