#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Tests for the project-mode doc runner (tools/run_doc_project_inprocess.tcl).
#
# Each case drives the runner as a subprocess (exec tclsh ...) and asserts on
# its exit code, mirroring how Sentinel invokes it. The runner depends on
# aurig::core via TCLLIBPATH; this harness preserves the caller's TCLLIBPATH
# in the child environment.
#
# Usage: TCLLIBPATH="/path/to/aurig-core" tclsh test/test_doc_runner.tcl
# Exit: 0 = all pass, 1 = some fail
#=============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set root_dir    [file dirname $script_dir]
set runner      [file join $root_dir tools run_doc_project_inprocess.tcl]
set fixture_dir [file join $script_dir fixtures documenter no_top_project]
set manifest    [file join $fixture_dir project.yaml]
set build_dir   [file join $script_dir build doc_runner]

set tests_passed 0
set tests_failed 0

proc pass {desc} {
    global tests_passed
    incr tests_passed
    puts "  \[PASS\] $desc"
}

proc fail {desc msg} {
    global tests_failed
    incr tests_failed
    puts "  \[FAIL\] $desc"
    puts "         $msg"
}

proc header {txt} {
    puts "\n=========================================="
    puts $txt
    puts "=========================================="
}

proc assert_true {desc condition msg} {
    if {$condition} {
        pass $desc
    } else {
        fail $desc $msg
    }
}

# Run the runner as a subprocess and return its exit code. stdout/stderr are
# captured and reported on unexpected results to aid debugging.
proc run_runner {args} {
    global runner
    set output ""
    set code [catch {
        exec [info nameofexecutable] $runner {*}$args 2>@1
    } output opts]
    if {$code == 0} {
        return 0
    }
    # Distinguish a non-zero process exit from a Tcl-level exec failure.
    set ec [dict get $opts -errorcode]
    if {[lindex $ec 0] eq "CHILDSTATUS"} {
        return [lindex $ec 2]
    }
    # Some other exec failure (e.g. could not launch); surface it.
    return -code error "exec failed: $output"
}

header "Doc Runner: valid manifest, html"
file delete -force $build_dir
file mkdir $build_dir
set html_outdir [file join $build_dir valid_html]
set ec [run_runner -manifest $manifest -outdir $html_outdir -format html]
assert_true "valid manifest exits 0" [expr {$ec == 0}] "exit code was $ec"
assert_true "index.html generated" [file exists [file join $html_outdir index.html]] \
    "Missing [file join $html_outdir index.html]"

header "Doc Runner: missing manifest"
set ec [run_runner -manifest /nonexistent/path.yaml -outdir [file join $build_dir missing]]
assert_true "missing manifest exits 2" [expr {$ec == 2}] "exit code was $ec"

header "Doc Runner: invalid format"
set ec [run_runner -manifest $manifest -outdir [file join $build_dir bad_fmt] -format pdf]
assert_true "invalid -format exits 2" [expr {$ec == 2}] "exit code was $ec"

header "Test Summary"
set total [expr {$tests_passed + $tests_failed}]
puts "Total:  $total"
puts "Passed: $tests_passed"
puts "Failed: $tests_failed"

if {$tests_failed == 0} {
    puts "\nAll doc runner tests passed."
    exit 0
}

puts "\nSome doc runner tests failed."
exit 1
