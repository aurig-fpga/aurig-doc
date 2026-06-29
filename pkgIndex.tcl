# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# Standalone package index for aurig-doc: a snapshot carve of tcl4fpga's
# documentation layer (document/{documenter,project_documenter,symbol_generator}.tcl).
#
# It declares ONE package, aurig::doc 0.1.0 (name mirrors the
# namespace ::aurig::doc).
#
# The three files were AMBIENT-LOADED by the tcl4fpga umbrella (init.tcl) and
# carry no `package provide` of their own. This index sources all three, then
# provides the version, so every ::aurig::doc::* proc exists before any
# is called -- define order among them is irrelevant since Tcl resolves procs
# at call time.
#
# The parser/util core is NOT bundled here: each document file declares
# `package require aurig::core`, expected to resolve from aurig-core on
# ::auto_path (set TCLLIBPATH to the aurig-core checkout in dev/CI). No core,
# lint, leaf, or umbrella packages live here.

package ifneeded aurig::doc 0.1.0 [list apply {dir {
    source [file join $dir document documenter.tcl]
    source [file join $dir document project_documenter.tcl]
    source [file join $dir document symbol_generator.tcl]
    package provide aurig::doc 0.1.0
}} $dir]
