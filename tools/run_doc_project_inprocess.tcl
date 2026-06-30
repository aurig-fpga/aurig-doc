#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Project-mode documentation runner (in-process).
#
# Purpose:
#   Subprocess entry point for generating project documentation with
#   aurig-doc. It loads the carved `aurig::doc` package from this checkout
#   and invokes `::aurig::doc::project_documenter` against a project manifest.
#   Symmetric with aurig-lint's tools/run_lint_project_inprocess.tcl so
#   Sentinel can drive both tools through the same `-manifest <file>` flag.
#
# Usage:
#   tclsh tools/run_doc_project_inprocess.tcl -manifest <project.yaml> \
#       [-outdir <dir>] [-format html|md] [-verbosity <n>]
#   tclsh tools/run_doc_project_inprocess.tcl -help
#
#   -manifest <file>   REQUIRED. Project manifest (YAML); maps to
#                      project_documenter's -config.
#   -outdir <dir>      Output directory (default: docs).
#   -format html|md    Output format (default: html).
#   -verbosity <n>     Verbosity level (default: 0).
#   -h | -help | --help  Print this usage and exit 0.
#
# Requirements:
#   The carved `aurig::doc` package depends on `aurig::core`, which must be
#   resolvable on ::auto_path. In dev/CI that is provided via the TCLLIBPATH
#   environment variable pointing at an aurig-core checkout, e.g.:
#       TCLLIBPATH="/path/to/aurig-core" \
#           tclsh tools/run_doc_project_inprocess.tcl -manifest project.yaml
#   The YAML manifest path additionally requires tcllib's `yaml` package;
#   project_documenter pre-flights it and fails loudly if it is absent.
#
# Exit codes:
#   0  Documentation generated successfully.
#   2  Any tool/setup error: package load failure, missing/unknown switch,
#      missing -manifest, missing/bad manifest, invalid -format, tcllib yaml
#      absent, or a manifest parse/generation failure.
#   (There is no exit 1: documentation has no quality-threshold notion like
#    lint's fail_on.)
#=============================================================================

# Self-anchor: resolve this checkout's root from the script location so the
# carved aurig::doc package is resolvable regardless of the caller's cwd.
set aurig_doc_root [file dirname [file dirname [file normalize [info script]]]]
if {[lsearch -exact $::auto_path $aurig_doc_root] < 0} {
    set ::auto_path [linsert $::auto_path 0 $aurig_doc_root]
}

if {[catch {package require aurig::doc} pkg_err]} {
    puts stderr "error: failed to load aurig::doc package: $pkg_err"
    puts stderr "hint: ensure aurig::core is resolvable (set TCLLIBPATH to an aurig-core checkout)"
    exit 2
}

proc usage {} {
    puts "Usage: tclsh tools/run_doc_project_inprocess.tcl -manifest <project.yaml> \[options\]"
    puts ""
    puts "Generate project documentation in-process via aurig-doc."
    puts ""
    puts "Options:"
    puts "  -manifest <file>     Project manifest (YAML). REQUIRED."
    puts "  -outdir <dir>        Output directory (default: docs)."
    puts "  -format html|md      Output format (default: html)."
    puts "  -verbosity <n>       Verbosity level (default: 0)."
    puts "  -h, -help, --help    Print this help and exit."
    puts ""
    puts "Exit codes: 0 = docs generated; 2 = any tool/setup error."
    puts ""
    puts "Requires aurig::core on ::auto_path (set TCLLIBPATH to an aurig-core checkout)."
}

# Defaults.
set manifest  ""
set outdir    "docs"
set fmt       "html"
set verbosity 0

# Argument parsing.
set argc_count [llength $argv]
for {set i 0} {$i < $argc_count} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        -h - -help - --help {
            usage
            exit 0
        }
        -manifest {
            incr i
            if {$i >= $argc_count} {
                puts stderr "error: -manifest requires a file argument"
                exit 2
            }
            set manifest [lindex $argv $i]
        }
        -outdir {
            incr i
            if {$i >= $argc_count} {
                puts stderr "error: -outdir requires a directory argument"
                exit 2
            }
            set outdir [lindex $argv $i]
        }
        -format {
            incr i
            if {$i >= $argc_count} {
                puts stderr "error: -format requires a value (html|md)"
                exit 2
            }
            set fmt [lindex $argv $i]
        }
        -verbosity {
            incr i
            if {$i >= $argc_count} {
                puts stderr "error: -verbosity requires a numeric argument"
                exit 2
            }
            set verbosity [lindex $argv $i]
        }
        default {
            puts stderr "error: unknown switch: $arg"
            usage
            exit 2
        }
    }
}

if {$manifest eq ""} {
    puts stderr "error: -manifest <project.yaml> is required"
    usage
    exit 2
}

# Generate. project_documenter raises a Tcl error on any failure (missing or
# bad manifest, invalid -format, tcllib yaml absent, parse failure); all of
# these collapse to exit 2.
if {[catch {
    ::aurig::doc::project_documenter \
        -config $manifest \
        -outdir $outdir \
        -format $fmt \
        -verbosity $verbosity
} err]} {
    puts stderr $err
    if {[info exists ::errorInfo]} {
        puts stderr $::errorInfo
    }
    exit 2
}

exit 0
