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

- **Tcl 8.5+** (8.6 recommended). On Tcl 8.5, generated text must be
  written to regular, readable, seekable output files.
- **AURIG Core** on `TCLLIBPATH`. Doc 0.2.0 loads Core in the Tcl range
  `0.1.0-0.3.0`, which includes supported Core 0.1 installations for
  precomputed AST and symbol operations. VHDL generation requires stable
  Core in `0.2.0-0.3.0` with `::aurig::core::util::read_vhdl_source`.
  The upper bound is exclusive. Source operations reject alpha and beta
  packages. Start a fresh interpreter after changing an incompatible loaded
  Core version.
- **tcllib** (`yaml`) — needed only by `project_documenter` when the project manifest is
  YAML. The single-file `documenter` path needs no tcllib (the parser is regex-based).

## Quick start (standalone)

Document one VHDL file:

```tcl
# aurig-core must be reachable on the package path (see "As part of the stack").
package require aurig::doc 0.2.0-0.3.0

# Markdown (default output name design.md)
::aurig::doc::documenter -input design.vhd -format md

# HTML to an explicit path
::aurig::doc::documenter -input design.vhd -format html -output docs/design.html
```

Document a whole project from its manifest:

```tcl
package require aurig::doc 0.2.0-0.3.0
package require yaml   ;# tcllib, for a YAML manifest

# -config <project.yaml> (or -ini <project.ini>) is required; -outdir defaults to
# "docs" and -format defaults to html.
::aurig::doc::project_documenter -config project.yaml -format html -outdir build/docs
```

## Output and source errors

Generated HTML, Markdown and text reports use BOM-free UTF-8. Rejected VHDL
sources raise a Tcl error with a structured `-errorcode`. The project
runner (`tools/run_doc_project_inprocess.tcl`) prints the diagnostic and exits
with status 2 on source or dependency failure. A source rejection can now
raise or return exit 2 in cases where 0.1.0 printed a message or skipped the
source and returned success.

A mixed project can generate valid pages and report the rejected sources in
`documentation_report.txt`. Generation is incremental, so pages from an
earlier run can remain after a failed rerun. Check the API result or CLI exit
status before publishing the output directory. Use a fresh output directory
for a staged publication. Keep source files stable
during generation because the parser and source viewer read them separately.

## As part of the stack (resolving AURIG Core)

AURIG Doc requires `aurig::core` on the Tcl package path. The dev/CI knob is the native
`TCLLIBPATH` environment variable (a Tcl list of dirs prepended to `::auto_path`); point
it at an AURIG Core checkout:

```sh
TCLLIBPATH='/path/to/core' tclsh your_doc_script.tcl
```

`package require aurig::doc` then pulls `aurig::core` transitively. On Windows, use
forward slashes in `TCLLIBPATH`. Brace directories containing spaces as Tcl
list elements. Select the exact Doc commit from the integration record when
using this development version.

## Development

```sh
# Check out doc and its dependency side by side.
git clone https://github.com/aurig-fpga/aurig-doc.git
git clone https://github.com/aurig-fpga/aurig-core.git

# Select the verified Core 0.2.0 candidate once published
git -C aurig-core checkout --detach c30326cbfc979847d0426eeca4540e12e05eb0ec

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
single-file path works without tcllib while the YAML project path requires it.
CI checks out the pinned Core dependency, sets `TCLLIBPATH` and runs all eight
harnesses on Tcl 8.6 on Linux and Windows. [CI test list](.github/workflows/ci.yml)

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Copyright 2024-2026 LogiMentor S.r.l.
