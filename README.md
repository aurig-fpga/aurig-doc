<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# AURIG Doc

> **AURIG Doc** is part of the [AURIG stack](https://github.com/aurig-fpga) — open-source FPGA tooling by [LogiMentor](https://logimentor.com).
>
> See also: [Sentinel](https://github.com/aurig-fpga/aurig-sentinel) · [Build](https://github.com/aurig-fpga/aurig-build) · [Lint](https://github.com/aurig-fpga/aurig-lint) · [Core](https://github.com/aurig-fpga/aurig-core)

Generates browsable documentation from VHDL — for a single file or a whole project — in
Markdown or self-contained HTML. It parses sources with the [AURIG Core](https://github.com/aurig-fpga/aurig-core)
VHDL parser and renders per-entity/package pages plus, for projects, a navigable index.

## Two entry points

Both live under the `aurig::doc` package:

- **`::aurig::doc::documenter`** — document a single VHDL file. `-input <file>` and
  `-format <md|html>` are required; `-output <file>` is optional (defaults to
  `<basename>.md` / `<basename>.html`). Run with `-help` for usage.
- **`::aurig::doc::project_documenter`** — document a whole project from its manifest:
  scans from the top level and emits per-entity/package docs plus a navigable index.

## Requirements

- **Tcl 8.5+** (8.6 recommended; CI runs 8.6).
- **[AURIG Core](https://github.com/aurig-fpga/aurig-core)** — required. AURIG Doc bundles no
  parser of its own; it pulls `aurig::core` off the Tcl package path (see below).
- **tcllib** (`yaml`) — needed only by `project_documenter` when the project manifest is
  YAML. The single-file `documenter` path needs no tcllib (the parser is regex-based).

## Quick start (standalone)

Document one VHDL file:

```tcl
# aurig-core must be reachable on the package path (see "As part of the stack").
package require aurig::doc

# Markdown (default output name design.md)
::aurig::doc::documenter -input design.vhd -format md

# HTML to an explicit path
::aurig::doc::documenter -input design.vhd -format html -output docs/design.html
```

Document a whole project from its manifest:

```tcl
package require aurig::doc
package require yaml   ;# tcllib, for a YAML manifest

# -config <project.yaml> (or -ini <project.ini>) is required; -outdir defaults to
# "docs" and -format defaults to html.
::aurig::doc::project_documenter -config project.yaml -format html -outdir build/docs
```

## As part of the stack (resolving AURIG Core)

AURIG Doc requires `aurig::core` on the Tcl package path. The dev/CI knob is the native
`TCLLIBPATH` environment variable (a Tcl list of dirs prepended to `::auto_path`); point
it at an AURIG Core checkout:

```sh
TCLLIBPATH='/path/to/core' tclsh your_doc_script.tcl
```

`package require aurig::doc` then pulls `aurig::core` transitively. On Windows, use
forward slashes in `TCLLIBPATH`.

## Development

```sh
# Check out doc and its dependency side by side.
git clone https://github.com/aurig-fpga/aurig-doc.git
git clone https://github.com/aurig-fpga/aurig-core.git

# Tcl 8.6 + tcllib (Debian/Ubuntu)
sudo apt-get install -y tcl tcllib

# Run the suite with core on the package path.
cd aurig-doc
TCLLIBPATH="$(cd ../aurig-core && pwd)" tclsh test/test_doc_dependency.tcl
TCLLIBPATH="$(cd ../aurig-core && pwd)" tclsh test/test_documenter.tcl
TCLLIBPATH="$(cd ../aurig-core && pwd)" tclsh test/test_doc_tcllib_absent.tcl
TCLLIBPATH="$(cd ../aurig-core && pwd)" tclsh test/smoke/test_documenter_cleanup.tcl
```

`test/test_doc_dependency.tcl` proves `aurig::doc` resolves only when `aurig::core` is
reachable (and fails cleanly when it isn't); `test/test_doc_tcllib_absent.tcl` proves the
single-file path works without tcllib while the YAML project path requires it. CI
(`.github/workflows/ci.yml`) checks out aurig-core as a sibling, sets `TCLLIBPATH`, and
runs the same four tests on Tcl 8.6.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Copyright 2024-2026 LogiMentor S.r.l.
