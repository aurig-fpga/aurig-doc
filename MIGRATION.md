<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# aurig-doc — migration notes

## What this repository is

`aurig-doc` is a **snapshot carve** of the documentation layer from the
[tcl4fpga](https://github.com/LogiMentor/tcl4fpga) toolkit. It is a genuine
*consumer* of [aurig-core](https://github.com/aurig-fpga/aurig-core): it
requires the parser/util core off `::auto_path` and does **not** bundle it.

It contains exactly the documentation layer:

- `document/documenter.tcl` (single-file md/html documenter)
- `document/project_documenter.tcl` (project-wide doc generation)
- `document/symbol_generator.tcl` (SVG entity symbol generator)
- `config/LM_LOGO-full.png` (logo asset embedded in generated project docs)

It deliberately does **not** include the parser/util core (`core.tcl`,
`analyze/`, `util/`), the lint layer, the umbrella (`init.tcl`), the project
bootstrap (`bootstrap_root.tcl`), or any leaf tool.

## Packaging: from ambient-loaded to a real package

Upstream, the three `document/*.tcl` files were **ambient-loaded** by the
tcl4fpga umbrella (`init.tcl` sourced them) and carried no `package provide` of
their own. This carve mints a package for them:

- `pkgIndex.tcl` declares **one** package, `aurig::doc 0.1.0` (the name
  mirrors the namespace `::aurig::doc`). Its `package ifneeded` body
  sources all three `document/*.tcl` files and then provides the version, so
  every `::aurig::doc::*` proc exists before any is called — define
  order among the three is irrelevant since Tcl resolves procs at call time.
- Each of the three files now declares `package require aurig::core` at the
  top (idempotent under the package index). They reach core procs
  (`::aurig::core::analyze::vhdlscan`, the `q_*` query helpers, and
  `::aurig::core::util::{readYaml,readIni,collect_project_files}`) and must declare
  that dependency explicitly — the same pattern the analyze leaves adopted
  upstream.

## Dependency resolution model

aurig-doc reaches aurig-core through `::auto_path`. The dev/CI knob is the
native **`TCLLIBPATH`** environment variable (a Tcl list of dirs prepended to
`::auto_path`) pointing at the aurig-core checkout:

```sh
TCLLIBPATH='/path/to/aurig-core' tclsh test/test_doc_dependency.tcl
```

`package require aurig::doc` then transitively pulls `aurig::core`
from that path. aurig-doc is a **library**, not a run-by-path CLI, so it vendors
no `bootstrap_root.tcl`: consumers put the aurig-doc root on `::auto_path` and
`package require aurig::doc`. CI (`.github/workflows/ci.yml`) checks out
`aurig-fpga/aurig-core` into a sibling dir and sets `TCLLIBPATH` to it.

## Package names

The package and namespace were renamed from upstream as part of the
tcl4fpga → aurig cutover: this repository now provides `aurig::doc` (0.1.0) in
the namespace `::aurig::doc` (formerly `::tcl4fpga::document`). The rename is
**done** — it is part of this work, not a later phase.

## History

This is a content snapshot, not a history-preserving filter. The full commit
history of these files lives in the upstream `tcl4fpga` repository. Treat the
upstream tree as the source of record for provenance; changes here will diverge
from that point forward.

## Tests

- `test/test_doc_dependency.tcl` is the **carve proof**. In child interpreters
  it runs two legs: a POSITIVE leg (auto_path = doc root + aurig-core) where
  `package require aurig::doc` succeeds, transitively pulls
  `aurig::core`, and the engine actually documents a tiny entity fixture and
  emits a Markdown file naming the entity; and a NEGATIVE leg (aurig-core
  stripped from the path) where the require **must fail** with an error naming
  `aurig::core` — proving the dependency is external and unbundled. It also
  asserts the repo ships no `core.tcl`, no `analyze/`, no `util/`, no `lint/`,
  and no `bootstrap_root.tcl`.
- `test/test_documenter.tcl` is the documenter smoke + project-generation
  suite, re-anchored to a self `[info script]` root (it prepends the doc root to
  `::auto_path` and `package require`s `aurig::doc` instead of sourcing
  the upstream `setup.tcl`). It relies on `TCLLIBPATH` for core.
- `test/smoke/test_documenter_cleanup.tcl` is a zero-assertion argument-
  validation smoke (no pass/fail bookkeeping, no exit code). It lives under
  `test/smoke/` and is **not** part of the gate; run it by hand for an eyeball.
