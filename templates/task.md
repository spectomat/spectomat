---
component: <component>
slug: "{{SLUG}}"
task_number: "{{N}}"
branch: feat/{{SLUG}}
tasks: .spectomat/{{SLUG}}/tasks.json
---

# Task {{N}}: {{SLUG}}

**Task**
: is one independent piece of work in a plan, with its own file brief, its own test cycle and its own commit.
: The `implement` agent executes tasks one-by-one, in dependency order, running a `task` subagent in a separate session.

This document is a specific task brief: self-sufficient performative document. Readable with no other file open.

## Scope

the entire plan's goal, the architecture this task sits in.

## Goal

what this task adds: what exists when this task is done that did not before.

## Context

### Excerpts from Spec

Every requirement, criterion, constant, format and message this task implements, quoted from the spec with its id and section — the full text copied, not referenced, never the id alone:

#### **AC-1.1** (§3.2)

 <the criterion's full text>

#### **§4.1**

 <the rule's full text>

### From Memory

- every `memory.md` line that applies

### From existing codebase

What the task agent must know and cannot read off this file or the code it names: the existing files and signatures it touches (`path:lines`), the exemplar to copy (`path`), how tests run here.

### From previous tasks

- Task <M> (or none)
  - exact names and signatures consumed from task (none for Task 1)

## Constraints

- every Global Constraint from the plan that binds this task, copied verbatim
- exact values from the spec: constants, formats, messages

## Files

### Tests

- Test: `exact/path.test.js`

### Code

- Create: `exact/path.js`
- Modify: `exact/existing.js:120-140`

### Others (docs,resources, configs)

- Create: `exact/path.md`

## Procedure

### Step 1: Write test

— create `exact/path.test.js` with the content of `.spectomat/{{SLUG}}/snippets/task-{{N}}-step1.js.snippet`

### Step 2: Run test before Building

— `npm test -- exact/path.test.js`, fails with "fn is not defined"

### Step 3: Building

- create `exact/path.js` with the content of `.spectomat/{{SLUG}}/snippets/task-{{N}}-step3.js.snippet`
- modify `exact/existing.js:120-140`
- create: `exact/path.md` with the content of `.spectomat/{{SLUG}}/snippets/task-{{N}}-step3.md.snippet`

### Step 4: Run test after Building

— `npm test -- exact/path.test.js`, the full suite stays green
