---
name: Bug report
about: Report wrong, garbled, or failed documentation generation
title: ''
labels: bug
assignees: ''
---

## Description

A clear description of the bug (e.g. wrong/garbled generated docs, a parse error,
or a render problem).

## Input

The smallest VHDL source — or project manifest — that reproduces the issue:

```vhdl
-- your VHDL here (or paste the project.yaml / project.ini manifest)
```

## Command run

The exact `documenter` / `project_documenter` call you ran (with `-input` /
`-config`, `-format`, `-output` / `-outdir`):

```tcl
::aurig::doc::documenter -input ... -format md
```

## Output format

- [ ] md
- [ ] html

## Expected output

What you expected the generated documentation to contain.

## Actual output

What was actually generated (paste the garbled section or the error output).

## Versions

- aurig-doc: <!-- git commit or tag -->
- aurig-core: <!-- git commit or tag -->
- Tcl: <!-- output of `echo 'puts [info patchlevel]' | tclsh` -->

## OS / environment

<!-- e.g. Ubuntu 24.04, Windows 11 + ActiveTcl 8.6 -->
