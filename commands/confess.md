---
description: Force the orchestrator into paranoid self-audit mode. Produces a 7-section confession of every gap, fudge, and shortcut.
---

# /dod:confess

This is the anti-hallucination ritual. The orchestrator now drops the optimistic "looks done" frame and writes an honest confession of where the work falls short.

The output of this command is the document that the `claim-validator` will fact-check. So lying here costs the orchestrator more than telling the truth.

## What to do

1. Read the most recent task description (from the transcript or `.dod-guard/reports/`).
2. Read `git diff HEAD` and `git status --porcelain`.
3. Write the following document **verbatim in structure** — every section is mandatory, even if its content is "(nothing to confess in this section)". Save it to `.dod-guard/reports/confession-$(date -u +%Y%m%dT%H%M%SZ).md`.

```markdown
# Confession — <task name>  (<timestamp>)

## 1. Gaps in the implementation
List, with file:line citations, every place where the production behavior is
incomplete versus what was promised. Include silent error swallowers, stubs
that "kind of work," and any function whose docstring overpromises.

## 2. Weak or decorative tests
List every test you added in this diff that does not actually exercise the
code path. Cite the assertion that is too weak and what it should assert.

## 3. Edge cases not handled
For each public surface touched, list the boundary inputs you did not test:
null, empty, max-int, concurrent, malformed, non-ascii, very long, very fast,
very slow, exact threshold.

## 4. Hardcoded or placeholder values
Every literal that should be configuration, every IP/URL/secret-shaped string
that should not be in source, every magic number whose origin you cannot defend.

## 5. Files not wired up
New files created but not imported, exported, registered, or referenced. Code
that compiles but is dead.

## 6. TODOs / FIXMEs left behind
Every TODO/FIXME/XXX/HACK you added or noticed in your touched files. Include
the marker text and a one-line explanation of why it's there.

## 7. Refactors you wanted to do but didn't
List, with file paths, the improvements you would make if you had another
hour. This is not a deflection — it is to flag what the next session needs
to inherit honestly.
```

4. After writing the file, print:
   - the file path,
   - a one-paragraph summary of the highest-priority confession,
   - a recommendation: "Run `/dod:audit` so the claim-validator can score this confession."

## Hard rules

- Every section heading is required. "Nothing to confess" is a valid body, but the section must appear.
- Do not soften findings. The whole point is that this document is more honest than the orchestrator's normal completion report.
- Do not skip section 7 ("refactors not done"). It is the most-skipped section in practice.
- Save to disk. A confession that lives only in chat output is too easy to discard.
