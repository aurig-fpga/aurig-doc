<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2024-2026 LogiMentor S.r.l. -->

# Changelog

All notable changes to aurig-doc are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-22

Initial public release of aurig-doc as part of the AURIG open-source FPGA
tooling stack.

### Added

- VHDL documentation generator carved out of the legacy `tcl4fpga` `document/`
  layer into a standalone repository.
- Single-file generation via `::aurig::doc::documenter` (one VHDL file ->
  Markdown or self-contained HTML).
- Whole-project generation via `::aurig::doc::project_documenter` (scans from the
  manifest's top level and emits per-entity/package pages plus a navigable
  index).

### Changed

- Tcl namespace and package cutover to the AURIG namespace: the generator
  provides `aurig::doc`, and parser/util references target `aurig::core`. Direct
  cutover, no compatibility alias.

### Dependencies

- Requires [`aurig-core`](https://github.com/aurig-fpga/aurig-core) on `::auto_path`
  (via `TCLLIBPATH`); the VHDL parser/util core is not bundled.
- `project_documenter` requires tcllib (`yaml`) for YAML manifests; the
  single-file `documenter` path requires no tcllib.

### License

- Released under the Apache License 2.0.

[Unreleased]: https://github.com/aurig-fpga/aurig-doc/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aurig-fpga/aurig-doc/releases/tag/v0.1.0
