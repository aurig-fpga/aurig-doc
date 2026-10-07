#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Architecture body line numbers in the HTML and Markdown output.
#
# Regression coverage for aurig-core#23: with a blank line in the
# architecture declarative tail (between the last declaration and `begin`),
# the parser reported body statements one line too early. aurig-doc prints
# those parser lines verbatim:
#   - _emit_html_doc: the Line column of the Instantiations table;
#   - _emit_html_doc and _emit_md_doc: the "line N" label given to an
#     unlabelled process.
#
# Expected lines are found by searching the fixture text, independently of
# the parser. A control fixture with the same content minus the blank line
# must report the same statements one line earlier.
#
# Usage: TCLLIBPATH="/path/to/aurig-core" tclsh test/test_documenter_body_lines.tcl
# Exit: 0 = all pass, 1 = some fail
#=============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set root_dir    [file dirname $script_dir]

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

proc assert_line {desc expected actual} {
    if {[string is integer -strict $actual]} {
        set msg "expected line $expected, got $actual (delta [expr {$actual - $expected}])"
    } else {
        set msg "expected line $expected, got '$actual'"
    }
    assert_true $desc [expr {$actual eq $expected}] $msg
}

proc read_text {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh
    return $content
}

proc write_text {path content} {
    set fh [open $path w]
    fconfigure $fh -encoding utf-8 -translation lf
    puts -nonewline $fh $content
    close $fh
}

# Unique per-run scratch directory under the system temp dir, so concurrent
# or aborted runs never share fixtures.
proc make_run_dir {} {
    set base ""
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
            set base $::env($var)
            break
        }
    }
    if {$base eq ""} { set base /tmp }
    while 1 {
        set dir [file join [file normalize $base] \
            "aurig_doc_body_lines_[pid]_[clock clicks]_[expr {int(rand() * 1000000)}]"]
        if {![file exists $dir]} break
    }
    file mkdir $dir
    return $dir
}

# The fixture: one labelled instantiation and one unlabelled process, each
# on a single line. with_blank adds one blank line before `begin`.
proc fixture_text {with_blank} {
    set lines {
        "library ieee;"
        "use ieee.std_logic_1164.all;"
        ""
        "entity body_lines_top is"
        "  port (clk : in std_logic; d : in std_logic; q : out std_logic);"
        "end entity body_lines_top;"
        ""
        "architecture rtl of body_lines_top is"
        "  signal s : std_logic;"
    }
    if {$with_blank} { lappend lines "" }
    lappend lines \
        "begin" \
        "  u_leaf : entity work.body_lines_leaf port map (a => d, y => s);" \
        "  process (clk)" \
        "  begin" \
        "    if rising_edge(clk) then" \
        "      q <= s;" \
        "    end if;" \
        "  end process;" \
        "end architecture rtl;"
    return "[join $lines \n]\n"
}

# 1-based line of the single fixture line matching pattern.
proc find_line {text pattern} {
    set hits [list]
    set n 0
    foreach l [split $text \n] {
        incr n
        if {[regexp $pattern $l]} { lappend hits $n }
    }
    if {[llength $hits] != 1} {
        error "pattern '$pattern' matched lines {$hits}, expected exactly one"
    }
    return [lindex $hits 0]
}

proc check_layout {title with_blank run_dir} {
    header $title

    set tag [expr {$with_blank ? "blank" : "control"}]
    set text [fixture_text $with_blank]
    set vhd_file  [file join $run_dir "body_lines_$tag.vhd"]
    set html_file [file join $run_dir "body_lines_$tag.html"]
    write_text $vhd_file $text

    set inst_line [find_line $text {^\s*u_leaf\s*:}]
    set proc_line [find_line $text {^\s*process\s*\(}]

    ::aurig::doc::documenter -input $vhd_file -format html -output $html_file
    if {![file exists $html_file]} {
        fail "$tag: HTML output generated" "Missing file: $html_file"
        return
    }
    pass "$tag: HTML output generated"
    set html [read_text $html_file]

    set inst_actual ""
    regexp {<tr><td>u_leaf</td><td>([^<]*)</td>} $html -> inst_actual
    assert_line "$tag: instantiation u_leaf Line column" $inst_line $inst_actual

    set proc_actual ""
    if {[regexp {<h3>Processes</h3>(.*?)</table>} $html -> proc_table]} {
        regexp {<tr><td>line ([^<]*)</td>} $proc_table -> proc_actual
    }
    assert_line "$tag: unlabelled process 'line N' label" $proc_line $proc_actual

    # Markdown: _emit_md_doc prints the same "line N" process label. Its
    # Instantiations table has no line column, so only the label is checked.
    set md_file [file join $run_dir "body_lines_$tag.md"]
    ::aurig::doc::documenter -input $vhd_file -format md -output $md_file
    if {![file exists $md_file]} {
        fail "$tag: Markdown output generated" "Missing file: $md_file"
        return
    }
    pass "$tag: Markdown output generated"
    set md [read_text $md_file]

    set md_proc_actual ""
    if {[regexp {### Processes\n(.*?)(?:\n\n|$)} $md -> md_proc_table]} {
        regexp {\| line ([^ |]*) \|} $md_proc_table -> md_proc_actual
    }
    assert_line "$tag: Markdown unlabelled process 'line N' label" $proc_line $md_proc_actual

    return [list $inst_line $proc_line]
}

set run_dir [make_run_dir]
try {
    set control [check_layout "Body Lines: Control (no blank before begin)" 0 $run_dir]
    set blank   [check_layout "Body Lines: Blank Line Before begin" 1 $run_dir]

    # Guard the fixtures themselves: the blank layout shifts both statements
    # by exactly one line, so the two cases really differ only in the tail.
    header "Body Lines: Fixture Sanity"
    assert_true "blank fixture shifts both statements by one line" \
        [expr {[llength $control] == 2 && [llength $blank] == 2 &&
               [lindex $blank 0] == [lindex $control 0] + 1 &&
               [lindex $blank 1] == [lindex $control 1] + 1}] \
        "control {$control}, blank {$blank}"
} finally {
    file delete -force $run_dir
}

header "Test Summary"
set total [expr {$tests_passed + $tests_failed}]
puts "Total:  $total"
puts "Passed: $tests_passed"
puts "Failed: $tests_failed"

if {$tests_failed == 0} {
    puts "\nAll body line tests passed."
    exit 0
}

puts "\nSome body line tests failed."
exit 1
