#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# Documenter smoke and project-generation tests.
#
# Usage: tclsh test/test_documenter.tcl
# Exit: 0 = all pass, 1 = some fail
#=============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set root_dir    [file dirname $script_dir]
set fixture_dir [file join $script_dir fixtures documenter no_top_project]
set build_dir   [file join $script_dir build documenter]

# Make the carved doc package resolvable from its own root; the parser/util
# core resolves from aurig-core via TCLLIBPATH on ::auto_path (dev/CI).
if {[lsearch -exact $::auto_path $root_dir] < 0} {
    lappend ::auto_path $root_dir
}

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

proc run_no_error {desc body} {
    if {[catch {uplevel 1 $body} err opts]} {
        set detail $err
        if {[dict exists $opts -errorinfo]} {
            append detail "\n" [dict get $opts -errorinfo]
        }
        fail $desc $detail
        return 0
    }

    pass $desc
    return 1
}

proc read_text {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh
    return $content
}

proc with_cwd {dir body} {
    set old_cwd [pwd]
    cd $dir
    set code [catch {uplevel 1 $body} result opts]
    set restore_code [catch {cd $old_cwd} restore_err]
    if {$restore_code} {
        error "failed to restore cwd to $old_cwd: $restore_err"
    }
    if {$code} {
        return -options $opts $result
    }
    return $result
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

proc assert_file_nonempty {desc path} {
    if {![file exists $path]} {
        fail $desc "Missing file: $path"
        return
    }

    assert_true $desc [expr {[file size $path] > 0}] "File is empty: $path"
}

proc assert_file_contains {desc path needle} {
    if {![file exists $path]} {
        fail $desc "Missing file: $path"
        return
    }

    set content [read_text $path]
    assert_true $desc [expr {[string first $needle $content] >= 0}] "Did not find '$needle' in $path"
}

proc test_single_file_smoke {fixture_dir build_dir} {
    header "Single-File Documenter Smoke"

    set outdir [file join $build_dir single_file]
    file delete -force $outdir
    file mkdir $outdir

    set source_file [file join $fixture_dir rtl leaf_a.vhd]
    set html_file [file join $outdir leaf_a.html]
    set md_file [file join $outdir leaf_a.md]
    set log_file [file join $outdir documenter.log]

    if {![run_no_error "parse leaf_a.vhd" {
        set parse_dict [::aurig::core::analyze::vhdlscan -in $source_file -verbosity 0]
    }]} {
        return
    }

    set entities [::aurig::core::analyze::q_entity_names $parse_dict]
    assert_true "parsed entity list contains leaf_a" [expr {[lsearch -exact $entities leaf_a] >= 0}] "Entities: $entities"

    set log [open $log_file w]
    set html_ok [run_no_error "emit single-file HTML" {
        ::aurig::doc::_emit_html_doc $parse_dict $html_file $log
    }]
    set md_ok [run_no_error "emit single-file Markdown" {
        ::aurig::doc::_emit_md_doc $parse_dict $md_file $log
    }]
    close $log

    if {$html_ok} {
        assert_file_nonempty "single-file HTML is non-empty" $html_file
        assert_file_contains "single-file HTML contains entity name" $html_file "leaf_a"

        # Structural coverage for symbol_generator: the HTML emit path is the
        # only caller of _generate_entity_symbol, and nothing else asserted its
        # output. Pin that an <svg> symbol is embedded and that it carries at
        # least one port marker. Kept structural (element/class presence) and
        # deliberately free of coordinate/pixel values so it survives layout
        # tweaks; it still fails outright if symbol generation emits nothing.
        set html_content [read_text $html_file]
        assert_true "single-file HTML embeds an <svg> entity symbol" \
            [expr {[string first "<svg" $html_content] >= 0}] \
            "No <svg> element in $html_file"
        assert_true "single-file HTML symbol carries a port marker" \
            [expr {[string first "class=\"port-arrow\"" $html_content] >= 0 ||
                   [string first "class=\"port-line\"" $html_content] >= 0 ||
                   [string first "class=\"port-label\"" $html_content] >= 0}] \
            "No port-arrow/port-line/port-label marker in the SVG symbol in $html_file"
    }

    if {$md_ok} {
        assert_file_nonempty "single-file Markdown is non-empty" $md_file
        assert_file_contains "single-file Markdown contains entity name" $md_file "leaf_a"
    }
}

proc test_markdown_prepend_preserves_utf8 {build_dir} {
    header "Markdown Navigation Encoding"

    set outdir [file join $build_dir markdown_encoding]
    file delete -force $outdir
    file mkdir $outdir

    set parse_dict [dict create \
        entities [list [dict create \
            name leaf_utf8 \
            comment "Caf\u00e9 entity comment" \
            ports [list [dict create name clk mode in type std_logic comment ""]]]] \
        libraries {} \
        uses {} \
        architectures {}]

    set out_file [file join $outdir leaf_utf8.md]
    if {![run_no_error "emit Markdown entity page with UTF-8 content" {
        ::aurig::doc::_emit_entity_page $parse_dict $outdir md leaf_utf8
    }]} {
        return
    }

    set content [read_text $out_file]
    set home_link "\[\u2190 Home\](index.md)"
    assert_true "Markdown UTF-8 page keeps Home link" [expr {[string first $home_link $content] >= 0}] "Missing Home link in $out_file"
    assert_true "Markdown UTF-8 page keeps non-ASCII content" [expr {[string first "Caf\u00e9" $content] >= 0}] "Missing UTF-8 comment in $out_file"
}

proc test_html_rewrite_preserves_utf8 {build_dir} {
    header "HTML Navigation Encoding"

    set outdir [file join $build_dir html_encoding]
    file delete -force $outdir
    file mkdir $outdir

    set parse_dict [dict create \
        entities [list [dict create \
            name leaf_html_utf8 \
            comment "Caf\u00e9 entity comment" \
            ports [list [dict create name clk mode in type std_logic comment ""]]]] \
        libraries {} \
        uses {} \
        architectures {}]

    set out_file [file join $outdir leaf_html_utf8.html]
    if {![run_no_error "emit HTML entity page with UTF-8 content" {
        ::aurig::doc::_emit_entity_page $parse_dict $outdir html leaf_html_utf8
    }]} {
        return
    }

    set content [read_text $out_file]
    assert_true "HTML UTF-8 page declares UTF-8" [expr {[string first {<meta charset="utf-8">} $content] >= 0}] "Missing UTF-8 meta tag in $out_file"
    assert_true "HTML UTF-8 page keeps Home link" [expr {[string first "Home" $content] >= 0}] "Missing Home link in $out_file"
    assert_true "HTML UTF-8 page keeps non-ASCII content" [expr {[string first "Caf\u00e9" $content] >= 0}] "Missing UTF-8 comment in $out_file"
}

proc test_project_documenter_from_other_cwd {fixture_dir build_dir} {
    header "Project Documenter CWD Independence"

    set manifest [file join $fixture_dir project.yaml]
    set other_cwd [file join $build_dir other_cwd]
    set html_outdir [file join $build_dir cwd_html]
    set md_outdir [file join $build_dir cwd_md]
    file delete -force $other_cwd $html_outdir $md_outdir
    file mkdir $other_cwd

    if {[run_no_error "generate no-top project HTML from non-repo cwd" {
        with_cwd $other_cwd {
            ::aurig::doc::project_documenter \
                -config $manifest \
                -outdir $html_outdir \
                -format html
        }
    }]} {
        assert_file_contains "cwd HTML index is generated" [file join $html_outdir index.html] "<html"
        assert_file_contains \
            "cwd HTML report records VHDL file count" \
            [file join $html_outdir documentation_report.txt] \
            "Total VHDL files scanned: 2"
        assert_file_exists \
            "cwd HTML index copies package logo" \
            [file join $html_outdir LM_LOGO-full.png]
    }

    if {[run_no_error "generate no-top project Markdown from non-repo cwd" {
        with_cwd $other_cwd {
            ::aurig::doc::project_documenter \
                -config $manifest \
                -outdir $md_outdir \
                -format md
        }
    }]} {
        assert_file_contains "cwd Markdown index is generated" [file join $md_outdir index.md] "# "
        assert_file_contains \
            "cwd Markdown report records VHDL file count" \
            [file join $md_outdir documentation_report.txt] \
            "Total VHDL files scanned: 2"
    }
}

proc test_project_html_no_top {fixture_dir build_dir} {
    header "Project Documenter HTML No-Top"

    set manifest [file join $fixture_dir project.yaml]
    set outdir [file join $build_dir no_top_html]
    file delete -force $outdir

    if {![run_no_error "generate no-top project HTML" {
        ::aurig::doc::project_documenter \
            -config $manifest \
            -outdir $outdir \
            -format html
    }]} {
        return
    }

    set index_file [file join $outdir index.html]
    set report_file [file join $outdir documentation_report.txt]

    assert_file_exists "HTML index exists" $index_file
    assert_file_contains "HTML index contains html tag" $index_file "<html"
    assert_file_exists "HTML report exists" $report_file
    assert_file_contains "HTML report records no-top mode" $report_file "Mode: All files scanned (no top entity specified)"
    assert_file_contains "HTML report records VHDL file count" $report_file "Total VHDL files scanned: 2"

    set source_pages [glob -nocomplain [file join $outdir "src_*.html"]]
    assert_true "HTML source viewer page exists" [expr {[llength $source_pages] > 0}] "No src_*.html files in $outdir"

    set entity_pages [list]
    foreach page [glob -nocomplain [file join $outdir "*.html"]] {
        set tail [file tail $page]
        if {$tail eq "index.html"} continue
        if {$tail eq "files.html"} continue
        if {[string match "src_*.html" $tail]} continue
        lappend entity_pages $page
    }

    assert_true "HTML entity page exists" [expr {[llength $entity_pages] > 0}] "No entity .html pages in $outdir"

    set found_entity_name 0
    foreach page $entity_pages {
        set content [read_text $page]
        if {[string first "leaf_a" $content] >= 0 || [string first "leaf_b" $content] >= 0} {
            set found_entity_name 1
            break
        }
    }
    assert_true "HTML entity page contains leaf entity name" $found_entity_name "Entity pages: $entity_pages"
}

proc test_project_md_no_top {fixture_dir build_dir} {
    header "Project Documenter Markdown No-Top"

    set manifest [file join $fixture_dir project.yaml]
    set outdir [file join $build_dir no_top_md]
    file delete -force $outdir

    if {![run_no_error "generate no-top project Markdown" {
        ::aurig::doc::project_documenter \
            -config $manifest \
            -outdir $outdir \
            -format md
    }]} {
        return
    }

    set index_file [file join $outdir index.md]
    set report_file [file join $outdir documentation_report.txt]

    assert_file_exists "Markdown index exists" $index_file
    assert_file_contains "Markdown index contains heading" $index_file "# "
    assert_file_contains "Markdown index links leaf_a" $index_file {[leaf_a](leaf_a.md)}
    assert_file_contains "Markdown index links leaf_b" $index_file {[leaf_b](leaf_b.md)}
    assert_file_exists "Markdown report exists" $report_file
    assert_file_contains "Markdown report records no-top mode" $report_file "Mode: All files scanned (no top entity specified)"
    assert_file_contains "Markdown report records VHDL file count" $report_file "Total VHDL files scanned: 2"

    set entity_pages [list]
    foreach page [glob -nocomplain [file join $outdir "*.md"]] {
        if {[file tail $page] eq "index.md"} continue
        lappend entity_pages $page
    }

    assert_true "Markdown entity page exists" [expr {[llength $entity_pages] > 0}] "No entity .md pages in $outdir"

    set home_link "\[\u2190 Home\](index.md)"
    set found_home_link 0
    foreach page $entity_pages {
        set content [read_text $page]
        if {[string first $home_link $content] >= 0} {
            set found_home_link 1
            break
        }
    }
    assert_true "Markdown entity page contains Home link" $found_home_link "Entity pages: $entity_pages"
}

proc test_project_documenter_logo_scope {} {
    header "Project Documenter Logo Cache Scope"

    set caller_globals_ok [expr {
        [info exists ::_project_documenter_logo_path] &&
        [info exists ::_project_documenter_logo_fh] &&
        [info exists ::_project_documenter_logo_data] &&
        [info exists ::_project_documenter_logo_bytes] &&
        $::_project_documenter_logo_path eq "caller-logo-path" &&
        $::_project_documenter_logo_fh eq "caller-logo-fh" &&
        $::_project_documenter_logo_data eq "caller-logo-data" &&
        $::_project_documenter_logo_bytes eq "caller-logo-bytes"
    }]

    assert_true \
        "logo cache initialization leaves caller globals untouched" \
        $caller_globals_ok \
        "project_documenter load modified caller globals"

    set namespace_logo_ok [expr {
        [info exists ::aurig::doc::_project_documenter_logo_bytes] &&
        [string length $::aurig::doc::_project_documenter_logo_bytes] > 0
    }]
    assert_true \
        "logo cache is namespace-scoped and populated" \
        $namespace_logo_ok \
        "Missing namespace-scoped project documenter logo cache"

    set saved_logo_bytes $::aurig::doc::_project_documenter_logo_bytes
    set ::aurig::doc::_project_documenter_logo_bytes ""
    set empty_logo_ok [expr {
        [::aurig::doc::_emit_project_documenter_logo .] == 0
    }]
    set ::aurig::doc::_project_documenter_logo_bytes $saved_logo_bytes
    assert_true \
        "empty logo cache disables logo emission" \
        $empty_logo_ok \
        "Logo emission succeeded with an empty cache"

    set footer_without_logo [::aurig::doc::_generate_footer 0]
    assert_true \
        "footer can omit logo reference when logo is unavailable" \
        [expr {[string first "LM_LOGO-full.png" $footer_without_logo] < 0}] \
        "Footer still references LM_LOGO-full.png when includeLogo is false"

    unset -nocomplain ::_project_documenter_logo_path \
        ::_project_documenter_logo_fh \
        ::_project_documenter_logo_data \
        ::_project_documenter_logo_bytes
}

set ::_project_documenter_logo_path "caller-logo-path"
set ::_project_documenter_logo_fh "caller-logo-fh"
set ::_project_documenter_logo_data "caller-logo-data"
set ::_project_documenter_logo_bytes "caller-logo-bytes"
package require aurig::doc

file delete -force $build_dir
file mkdir $build_dir

test_project_documenter_logo_scope
test_single_file_smoke $fixture_dir $build_dir
test_markdown_prepend_preserves_utf8 $build_dir
test_html_rewrite_preserves_utf8 $build_dir
test_project_documenter_from_other_cwd $fixture_dir $build_dir
test_project_html_no_top $fixture_dir $build_dir
test_project_md_no_top $fixture_dir $build_dir

header "Test Summary"
set total [expr {$tests_passed + $tests_failed}]
puts "Total:  $total"
puts "Passed: $tests_passed"
puts "Failed: $tests_failed"

if {$tests_failed == 0} {
    puts "\nAll documenter tests passed."
    exit 0
}

puts "\nSome documenter tests failed."
exit 1
