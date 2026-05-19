---
name: Bug report
about: Report something that DoD-Guard does (or fails to do) incorrectly
title: "[bug] "
labels: bug
assignees: ''
---

## What happened

<!-- A short description of the behavior. -->

## What you expected

<!-- What DoD-Guard should have done in this case. -->

## Repro steps

1.
2.
3.

## Environment

- DoD-Guard version (`jq -r .version .claude-plugin/plugin.json`):
- Claude Code version (`claude --version`):
- OS and shell (`uname -a` + `bash --version | head -n 1`):
- Python version (`python3 --version`):
- Project stack (Node / Python / Go / Rust / other):

## Evidence

<!-- Paste the output of /dod:verify, /dod:audit, or the detector that misfired.
     For false positives, include the file + line that was flagged and the
     reason it shouldn't have been flagged. -->

```
<paste output here>
```

## Additional context

<!-- Anything else? Related plugins, custom .dod-guard.json overrides, hooks
     from other plugins that might interact, etc. -->
