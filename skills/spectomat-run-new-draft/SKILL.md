---
name: spectomat-run-new-draft
description: Triggered by the word "spectomat" anywhere in the user's message when they are describing an idea, feature, or task rather than asking about the Spectomat tool itself. Turns the idea into a numbered draft file under .spectomat/drafts/ and starts the flow.
disable-model-invocation: false
argument-hint: express your new idea
---

# Spectomat draft

Turn the user's idea into a draft file for the Spectomat factory, then run the flow.

## When to use

The message contains the word "spectomat" **and** describes something to build, fix, or change —
not a question about how Spectomat works (that's `spectomat:help`) and not a request to check
progress or cancel (that's `spectomat:status` / `spectomat:cancel`).

## Steps

1. **Find the project root.** `.spectomat/` lives at the repo root the user is working in. If
   `.spectomat/drafts/` does not exist, create it.

2. **Pick the next number.** List `.spectomat/drafts/*.md` and the slug directories `.spectomat/*/`
   matching `NNN-*` — every idea keeps its own directory for its whole life, finished or not, so
   those two listings are the whole factory. Take the highest existing `NNN` prefix and add 1,
   zero-padded to 3 digits (`001`, `002`, …). Start at `001` if none exist.

3. **Slug the name.** Derive a short kebab-case slug from the idea (2-5 words, lowercase,
   hyphen-separated, no stopwords). Combine as `<nnn>-<slug>.md`.

4. **Write the draft.** Create `.spectomat/drafts/<nnn>-<slug>.md` with the user's idea written up
   as a clear, self-contained brief: what to build/change and why, in the user's own words where
   possible. Do not add speculative scope beyond what the user described. This is raw material for
   the `SPECIFY` phase, not a spec itself — keep it short.

5. **Confirm the file** to the user in one line (path only).

6. **Run the flow** by invoking the `/spectomat:run` command.

## Notes

- Never edit or delete existing files under `drafts/` — only add new ones.
- If `.spectomat/` doesn't exist at all in this repo, tell the user this project hasn't been
  initialized for Spectomat and stop — don't scaffold the rest of the floor yourself.
- If the user's message is too vague to write a brief from, ask one clarifying question before
  creating the file — a bad draft costs a whole SPECIFY phase to fix.
