<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# Contributing to aurig-doc

Thanks for your interest in improving **aurig-doc**, the VHDL documentation
generator of the AURIG open-source FPGA tooling stack.

## What aurig-doc is

`aurig-doc` generates browsable documentation from VHDL — for a single file or a
whole project — in Markdown or self-contained HTML. It exposes two public entry
points under the `aurig::doc` package:

- **`::aurig::doc::documenter`** — document a single VHDL file (`-input` /
  `-format md|html` / optional `-output`).
- **`::aurig::doc::project_documenter`** — document a whole project from its
  manifest (`-config <project.yaml>` or `-ini <project.ini>`, `-outdir`,
  `-format html|md`), emitting per-entity/package pages plus a navigable index.

It is a *consumer* of [`aurig-core`](https://github.com/aurig-fpga/aurig-core): the
VHDL parser and the YAML/JSON utilities live there and are **not** bundled in
this repository. `aurig-doc` loads `aurig::core` off Tcl's `::auto_path` at
runtime, so you need an `aurig-core` checkout available to run or test the
generator.

## Prerequisites

- **Tcl 8.5+** (8.6 recommended; CI runs 8.6).
- A local checkout of **`aurig-core`** — required; aurig-doc bundles no parser of
  its own.
- **tcllib** (the `yaml` package) — needed only by `project_documenter` when the
  project manifest is YAML. The single-file `documenter` path needs no tcllib
  (its parser is regex-based).

## Running the test suite

`aurig-doc` finds `aurig-core` through the native **`TCLLIBPATH`** environment
variable (a Tcl list of directories prepended to `::auto_path`). Point it at your
`aurig-core` checkout — typically a sibling directory.

```sh
# Clone the dependency next to aurig-doc
git clone https://github.com/aurig-fpga/aurig-core ../aurig-core

# Tcl 8.6 + tcllib (Debian/Ubuntu)
sudo apt-get install -y tcl tcllib

# Point TCLLIBPATH at aurig-core, then run the CI test list
export TCLLIBPATH="$(cd ../aurig-core && pwd)"
tclsh test/test_doc_dependency.tcl
tclsh test/test_documenter.tcl
tclsh test/test_doc_tcllib_absent.tcl
tclsh test/smoke/test_documenter_cleanup.tcl
```

On **Windows**, `TCLLIBPATH` must be a **forward-slash** path even though the
drive uses backslashes elsewhere, and PowerShell sets it with `$env:` rather
than `export` — e.g.:

```powershell
# Windows (PowerShell, ActiveTcl)
$env:TCLLIBPATH = "C:/path/to/aurig-core"
```

`package require aurig::doc` then transitively pulls `aurig::core` from that
path. Each test exits non-zero on failure, so the exit code is the source of
truth. `test/test_doc_dependency.tcl` proves `aurig::doc` resolves only when
`aurig::core` is reachable; `test/test_doc_tcllib_absent.tcl` proves the
single-file path works without tcllib while the YAML project path requires it.
The authoritative test list lives in `.github/workflows/ci.yml`.

## How to contribute

- Open one pull request per concern, based on `main`.
- Keep changes focused: the namespace/convention migrations and behavior live in
  separate, small PRs — follow that grain.
- Files use **LF** line endings (enforced by `.gitattributes`). Do not introduce
  CRLF or a UTF-8 BOM.
- New `.tcl` source and project-authored docs carry the SPDX/copyright header
  used throughout the repo. Match the surrounding style.
- If you add or change behavior, add or update a `test/test_*.tcl` so it runs in
  CI (the CI test list lives in `.github/workflows/ci.yml`).

## License

By contributing, you agree that your contributions are licensed under the
Apache License 2.0 (see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE)).
