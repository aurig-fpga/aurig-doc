# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#=============================================================================
# aurig-doc cross-repo dependency proof.
#
# Proves that aurig-doc is a genuine CONSUMER of aurig-core: it requires
# aurig::core from ::auto_path and does NOT bundle it. The headline is the
# pair of legs run in child interpreters:
#
#   POSITIVE  auto_path = [aurig-doc root] + parent auto_path (which carries
#             aurig-core via TCLLIBPATH + tcllib): `package require
#             aurig::doc` SUCCEEDS, transitively pulls aurig::core,
#             and the engine RUNS -- it documents a tiny entity fixture and
#             emits a Markdown file naming that entity.
#
#   NEGATIVE  auto_path = [aurig-doc root] + parent auto_path with every
#             aurig-core entry stripped: `package require
#             aurig::doc` must FAIL with a can't-find-package error
#             naming aurig::core -- proving the dependency is external and
#             unbundled.
#
# It also asserts aurig-doc defines no core proc of its own (no
# ::aurig::core::analyze::vhdlscan before core loads) and ships no core/lint file
# and no bootstrap_root.tcl.
#
# REQUIREMENT: the interpreter running this test must have aurig-core on its
# ::auto_path for the POSITIVE leg -- set TCLLIBPATH to the aurig-core checkout
# (dev/CI). With core absent from the parent path the POSITIVE leg fails with an
# actionable message rather than degrading silently.
#=============================================================================

set test_dir    [file dirname [file normalize [info script]]]
set doc_root    [file dirname $test_dir]
set doc_root_n  [file normalize $doc_root]

set ::pass 0
set ::fail 0
proc ok {label cond} {
    if {[uplevel 1 [list expr $cond]]} {
        puts "PASS: $label"; incr ::pass
    } else {
        puts "FAIL: $label"; incr ::fail
    }
}

# ---------------------------------------------------------------------------
# Two views of the parent auto_path:
#   with_core  : parent path verbatim (minus the doc root, which we prepend) --
#                carries aurig-core (via TCLLIBPATH) and tcllib for the engine.
#   strip_core : parent path with every aurig-core entry removed --
#                tcllib stays reachable; core is gone.
# ---------------------------------------------------------------------------
set with_core {}
set strip_core {}
foreach p $::auto_path {
    set np [file normalize $p]
    if {$np eq $doc_root_n} continue
    lappend with_core $p
    if {[string match -nocase *aurig-core* $np]} continue
    lappend strip_core $p
}

# ---------------------------------------------------------------------------
# POSITIVE leg
# ---------------------------------------------------------------------------
set pos [interp create]
$pos eval [list set ::auto_path [linsert $with_core 0 $doc_root]]
set prc [catch {$pos eval {package require aurig::doc}} pver]

ok "POSITIVE: package require aurig::doc succeeds (core reachable on auto_path)" \
    {$prc == 0}
ok "POSITIVE: reports document version 0.1.0" {$pver eq "0.1.0"}
ok "POSITIVE: requiring document transitively pulled aurig::core" \
    {[$pos eval {expr {![catch {package present aurig::core}]}}]}
ok "POSITIVE: core parser proc ::aurig::core::analyze::vhdlscan is now defined" \
    {[$pos eval {llength [info commands ::aurig::core::analyze::vhdlscan]}] == 1}

# Engine actually runs: document a tiny entity fixture and assert a Markdown
# file is produced that names the entity.
set sandbox [file join $test_dir .tmp_dep_proof]
file delete -force $sandbox
file mkdir $sandbox
set fixture [file join $sandbox dut.vhd]
set fp [open $fixture w]
fconfigure $fp -translation lf
puts $fp {library ieee;
use ieee.std_logic_1164.all;

entity DocProofEnt is
    port (
        clk : in  std_logic;
        q   : out std_logic
    );
end entity DocProofEnt;

architecture rtl of DocProofEnt is
begin
    q <= clk;
end architecture rtl;
}
close $fp

set md_out [file join $sandbox dut.md]
set drc [catch {
    $pos eval [list ::aurig::doc::documenter -input $fixture -format md -output $md_out]
} dres]

ok "POSITIVE: ::aurig::doc::documenter executes without error" {$drc == 0}
ok "POSITIVE: documenter produced a non-empty Markdown file" \
    {[file exists $md_out] && [file size $md_out] > 0}

set md_text ""
if {[file exists $md_out]} {
    set mf [open $md_out r]
    fconfigure $mf -encoding utf-8
    set md_text [read $mf]
    close $mf
}
ok "POSITIVE: emitted Markdown names the entity DocProofEnt" \
    {[string first DocProofEnt $md_text] >= 0}

interp delete $pos
file delete -force $sandbox

# ---------------------------------------------------------------------------
# NEGATIVE leg -- the dependency proof
# ---------------------------------------------------------------------------
set neg [interp create]
$neg eval [list set ::auto_path [linsert $strip_core 0 $doc_root]]
set nrc [catch {$neg eval {package require aurig::doc}} nerr]

ok "NEGATIVE: package require aurig::doc FAILS when aurig-core is off auto_path" \
    {$nrc != 0}
ok "NEGATIVE: the failure names aurig::core (dependency is external, not bundled)" \
    {[string match -nocase {*aurig::core*} $nerr]}
ok "NEGATIVE: aurig-doc defined NO ::aurig::core::analyze::vhdlscan of its own" \
    {[$neg eval {llength [info commands ::aurig::core::analyze::vhdlscan]}] == 0}
if {$nrc != 0} { puts "  (negative-leg error: $nerr)" }

interp delete $neg

# ---------------------------------------------------------------------------
# Repo-shape assertions: aurig-doc ships no core, no lint, no umbrella bootstrap.
# ---------------------------------------------------------------------------
proc find_under {root name} {
    set hits {}
    foreach f [glob -nocomplain -directory $root -- *] {
        if {[file isdirectory $f]} {
            lappend hits {*}[find_under $f $name]
        } elseif {[string equal [file tail $f] $name]} {
            lappend hits $f
        }
    }
    return $hits
}

ok "repo ships NO core.tcl" {![file exists [file join $doc_root core.tcl]]}
ok "repo ships NO analyze/ dir (parser stack lives in aurig-core)" \
    {![file isdirectory [file join $doc_root analyze]]}
ok "repo ships NO util/ parser dir (lives in aurig-core)" \
    {![file isdirectory [file join $doc_root util]]}
ok "repo ships NO lint/ dir (lint layer lives in aurig-lint)" \
    {![file isdirectory [file join $doc_root lint]]}
ok "repo vendors NO bootstrap_root.tcl anywhere" \
    {[llength [find_under $doc_root bootstrap_root.tcl]] == 0}
ok "repo ships the three document/*.tcl files" \
    {[file exists [file join $doc_root document documenter.tcl]] &&
     [file exists [file join $doc_root document project_documenter.tcl]] &&
     [file exists [file join $doc_root document symbol_generator.tcl]]}

puts ""
puts "============================================================"
puts "  passed: $::pass    failed: $::fail"
puts "============================================================"
exit [expr {$::fail == 0 ? 0 : 1}]
