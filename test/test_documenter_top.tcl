#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Project documenter top-present mode tests.
#
# Regression coverage for top-entity resolution: a manifest with a `top:`
# entity whose source lives in a file_sets SUBDIRECTORY (rtl/*.vhd) must
# resolve via the manifest-driven file list, not by probing project_root for
# a file literally named <entity>.vhd. Pre-fix this failed with
# "cannot locate top-level file matching entity".
#
# Also guards:
#   - a genuinely missing top entity still fails loudly with that message;
#   - the manifest format passed to collect_project_files is not clobbered
#     by the extension-search loop (pre-fix, `foreach ext ...` overwrote the
#     config extension, so YAML manifests were collected as INI, silently
#     landing in the manual file_sets fallback -- asserted here by the
#     ABSENCE of the fallback marker in verbose runner output).
#
# Usage: TCLLIBPATH="/path/to/aurig-core" tclsh test/test_documenter_top.tcl
# Exit: 0 = all pass, 1 = some fail
#=============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set root_dir    [file dirname $script_dir]
set runner      [file join $root_dir tools run_doc_project_inprocess.tcl]
set fixture_dir [file join $script_dir fixtures documenter top_project]
set manifest    [file join $fixture_dir project.yaml]
set manifest_missing [file join $fixture_dir project_missing_top.yaml]
set build_dir   [file join $script_dir build documenter_top]

# Make the carved doc package resolvable from its own root; the parser/util
# core resolves from aurig-core via TCLLIBPATH on ::auto_path (dev/CI).
if {[lsearch -exact $::auto_path $root_dir] < 0} {
    lappend ::auto_path $root_dir
}
package require aurig::doc

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

proc assert_file_exists {desc path} {
    assert_true $desc [file exists $path] "Missing file: $path"
}

proc read_text {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh
    return $content
}

proc assert_file_contains {desc path needle} {
    if {![file exists $path]} {
        fail $desc "Missing file: $path"
        return
    }
    set content [read_text $path]
    assert_true $desc [expr {[string first $needle $content] >= 0}] \
        "Did not find '$needle' in $path"
}

# Run the runner as a subprocess; return {exit_code combined_output}.
proc run_runner_capture {args} {
    global runner
    set output ""
    set code [catch {
        exec [info nameofexecutable] $runner {*}$args 2>@1
    } output opts]
    if {$code == 0} {
        return [list 0 $output]
    }
    set ec [dict get $opts -errorcode]
    if {[lindex $ec 0] eq "CHILDSTATUS"} {
        return [list [lindex $ec 2] $output]
    }
    return -code error "exec failed: $output"
}

file delete -force $build_dir
file mkdir $build_dir

# ---------------------------------------------------------------------------
# (a) Regression: top entity in a file_sets subdirectory resolves and docs
#     are generated with the hierarchy rooted at the top entity.
# ---------------------------------------------------------------------------
header "Top-Present: entity in file_sets subdirectory (regression)"

set outdir [file join $build_dir md_top]
set gen_err ""
set gen_rc [catch {
    ::aurig::doc::project_documenter \
        -config $manifest -outdir $outdir -format md -verbosity 0
} gen_result]
if {$gen_rc} { set gen_err $gen_result }

assert_true "top-present generation succeeds" [expr {$gen_rc == 0}] \
    "project_documenter errored: $gen_err"
assert_true "project_documenter returns the outdir" \
    [expr {$gen_rc == 0 && $gen_result eq $outdir}] \
    "returned '$gen_result', expected '$outdir'"
assert_file_exists "index.md generated" [file join $outdir index.md]
assert_file_exists "top entity page generated" [file join $outdir top_unit.md]
assert_file_exists "child entity page generated" [file join $outdir leaf_x.md]
assert_file_contains "hierarchy is rooted at top_unit" \
    [file join $outdir index.md] "Top: **top_unit**"
assert_file_contains "hierarchy links the instantiated child" \
    [file join $outdir index.md] "leaf_x"

# ---------------------------------------------------------------------------
# (b) A genuinely missing top entity must still fail loudly with the
#     "cannot locate" diagnostic (both lookup tiers miss).
# ---------------------------------------------------------------------------
header "Top-Present: missing entity still errors"

set outdir_missing [file join $build_dir md_missing]
set miss_rc [catch {
    ::aurig::doc::project_documenter \
        -config $manifest_missing -outdir $outdir_missing -format md -verbosity 0
} miss_err]

assert_true "missing top entity raises an error" [expr {$miss_rc != 0}] \
    "project_documenter unexpectedly succeeded: $miss_err"
assert_true "error names the unresolvable entity" \
    [string match "*cannot locate top-level file matching entity 'no_such_entity'*" $miss_err] \
    "msg: $miss_err"

# ---------------------------------------------------------------------------
# (c) Clobber guard, via the Sentinel runner: the YAML manifest must be
#     collected by collect_project_files itself -- the manual file_sets
#     fallback (marker printed at verbosity > 1) must NOT engage.
# ---------------------------------------------------------------------------
header "Top-Present: collect_project_files handles the manifest (no fallback)"

set outdir_runner [file join $build_dir html_runner]
lassign [run_runner_capture \
    -manifest $manifest -outdir $outdir_runner -format html -verbosity 2] ec out

assert_true "runner exits 0 on top-present manifest" [expr {$ec == 0}] \
    "exit code was $ec; output:\n$out"
assert_file_exists "runner generated index.html" [file join $outdir_runner index.html]
assert_true "manual file_sets fallback did not engage" \
    [expr {[string first "Fallback: manually parsing" $out] < 0}] \
    "fallback marker found in runner output:\n$out"

# ---------------------------------------------------------------------------
# (d) INI guard: an INI manifest for which collect_project_files yields zero
#     entries must NOT enter the manual file_sets fallback (a YAML-only parse
#     over $Y, which the INI branch never sets). Pre-guard this crashed with
#     the raw Tcl error {can't read "Y": no such variable}; post-guard the
#     empty file list flows through to the proper "cannot locate" diagnostic.
# ---------------------------------------------------------------------------
header "Top-Present: INI manifest with empty collect skips the YAML fallback"

set manifest_ini [file join $fixture_dir project_fallback.ini]
set outdir_ini [file join $build_dir md_ini_fallback]
set ini_rc [catch {
    ::aurig::doc::project_documenter \
        -ini $manifest_ini -outdir $outdir_ini -format md -verbosity 0
} ini_err]

assert_true "INI manifest with zero collected files raises an error" \
    [expr {$ini_rc != 0}] \
    "project_documenter unexpectedly succeeded: $ini_err"
assert_true "failure is NOT the raw Tcl variable crash" \
    [expr {![string match {*can't read "Y"*} $ini_err]}] \
    "msg: $ini_err"
assert_true "failure is the proper cannot-locate diagnostic" \
    [string match "*cannot locate top-level file matching entity 'ghost_entity'*" $ini_err] \
    "msg: $ini_err"

# ---------------------------------------------------------------------------
# (e) YAML fallback regression: when collect_project_files returns nothing
#     for a YAML manifest, the manual file_sets fallback must still engage
#     and produce full documentation. collect_project_files is stubbed to an
#     empty dict so the fallback is the ONLY possible file source; the
#     rename is restored in a finally clause so a mid-test error cannot leak
#     the stub into later tests, and a post-restore probe proves the real
#     proc is back in service.
# ---------------------------------------------------------------------------
header "Top-Present: YAML manifest with empty collect still uses file_sets fallback"

rename ::aurig::core::util::collect_project_files ::__real_collect_project_files
proc ::aurig::core::util::collect_project_files {args} { return [dict create] }

set outdir_fb [file join $build_dir md_yaml_fallback]
try {
    set fb_rc [catch {
        ::aurig::doc::project_documenter \
            -config $manifest -outdir $outdir_fb -format md -verbosity 0
    } fb_result]

    assert_true "YAML generation succeeds via the file_sets fallback" \
        [expr {$fb_rc == 0}] \
        "project_documenter errored: $fb_result"
    assert_file_exists "fallback generated the top entity page" \
        [file join $outdir_fb top_unit.md]
    assert_file_contains "fallback hierarchy is rooted at top_unit" \
        [file join $outdir_fb index.md] "Top: **top_unit**"
} finally {
    rename ::aurig::core::util::collect_project_files {}
    rename ::__real_collect_project_files ::aurig::core::util::collect_project_files
}

set restored_files [::aurig::core::util::collect_project_files \
    -from $manifest -format yaml]
assert_true "collect_project_files is restored and operational after the stub" \
    [expr {[dict size $restored_files] > 0}] \
    "post-restore collect returned [dict size $restored_files] entries"

header "Test Summary"
set total [expr {$tests_passed + $tests_failed}]
puts "Total:  $total"
puts "Passed: $tests_passed"
puts "Failed: $tests_failed"

if {$tests_failed == 0} {
    puts "\nAll top-present documenter tests passed."
    exit 0
}

puts "\nSome top-present documenter tests failed."
exit 1
