#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.
#
# NEGATIVE CONTROL: when tcllib `yaml` is absent, doc PROJECT mode must FAIL
# LOUDLY with installation guidance and must NOT silently fall back to
# ::aurig::core::util::readYamlMinimal (the lite subset parser that mis-parses the
# multi-key list items in canonical file_sets). This is the silent mis-parse
# failure class that was eliminated in core; the carved doc layer must not
# reintroduce it.
#
# We validate against the ACTUAL absence condition (not a mock): a child
# interpreter whose ::auto_path carries the doc root + the aurig-core checkout +
# the base Tcl library only, so `package require yaml` genuinely cannot resolve
# -- exactly as on a host where tcllib is not installed (e.g. the Git-for-Windows
# mingw tclsh). A tripwire wrapped around readYamlMinimal proves the documenter
# never reached the fallback parser on the manifest, and we cover BOTH the
# no-top (collect_project_files) and top-present (file_sets fallback) paths.
#
# REQUIREMENT: aurig-core must be reachable for the child (set TCLLIBPATH to the
# aurig-core checkout, dev/CI). The host tclsh need NOT lack tcllib: the child's
# restricted auto_path reproduces the absence regardless. The "genuinely
# unreachable" guard below FAILS loudly if some host layout still exposes tcllib
# through the kept paths, so the suite never passes for the wrong reason.

set test_dir   [file dirname [file normalize [info script]]]
set doc_root   [file dirname $test_dir]
set doc_root_n [file normalize $doc_root]

set ::pass 0
set ::fail 0
proc pass {name} { puts "  \[OK\]   $name"; incr ::pass }
proc fail {name msg} { puts "  \[XX\]   $name"; puts "         $msg"; incr ::fail }
proc check {name cond {detail ""}} {
    if {[uplevel 1 [list expr $cond]]} { pass $name } else { fail $name $detail }
}

puts "\n========== doc: tcllib-absent negative control =========="

# ---------------------------------------------------------------------------
# Discover the aurig-core checkout from the parent auto_path (where TCLLIBPATH
# placed it) so we can build a child auto_path that carries CORE but NOT tcllib.
# We do NOT try to identify and strip the tcllib directory by name (fragile
# across platforms); instead we build the child path from scratch out of known
# pieces -- doc root, the core-bearing entry, and the base Tcl library -- and let
# the absence guard confirm tcllib really is gone.
# ---------------------------------------------------------------------------
proc resolves_core {path} {
    set probe [interp create]
    $probe eval [list set ::auto_path [list $path $::tcl_library]]
    set ok [$probe eval {expr {![catch {package require aurig::core}]}}]
    interp delete $probe
    return $ok
}

set core_root ""
foreach p $::auto_path {
    if {[file normalize $p] eq $doc_root_n} continue
    if {[resolves_core $p]} { set core_root $p; break }
}

check "aurig-core checkout is reachable from auto_path (set TCLLIBPATH)" \
    {$core_root ne ""} \
    "no auto_path entry resolves aurig::core; set TCLLIBPATH to the aurig-core checkout"
if {$core_root eq ""} {
    puts "\n========================================"
    puts "  passed: $::pass    failed: $::fail"
    puts "========================================"
    exit 1
}

# Child interp: doc root + core checkout + base Tcl library only. tcllib lives in
# a DIFFERENT directory the parent had on auto_path, so it becomes unreachable --
# reproducing a host where tcllib is simply not installed.
set child [interp create]
$child eval [list set ::auto_path [list $doc_root $core_root $::tcl_library]]

# Sanity: the absence must be REAL in this child.
set yaml_rc [$child eval {catch {package require yaml}}]
check "tcllib yaml is genuinely unreachable in the child" {$yaml_rc != 0} \
    "package require yaml unexpectedly succeeded"

# The doc package still loads without tcllib (no runtime dep at source) and pulls
# core transitively.
set load_rc [$child eval {catch {package require aurig::doc} e; set e}]
check "aurig::doc still loads without tcllib" \
    {[$child eval {info procs ::aurig::doc::project_documenter}] ne ""} \
    "document load result: $load_rc"
check "loading document transitively pulled aurig::core" \
    {[$child eval {expr {![catch {package present aurig::core}]}}]} \
    "aurig::core not present after document load"

# Install a tripwire on the fallback parser: if the documenter ever calls
# readYamlMinimal on the manifest, we record it. It must NEVER be called on the
# project path under tcllib-absence.
$child eval {
    set ::__rym_called 0
    rename ::aurig::core::util::readYamlMinimal ::__real_readYamlMinimal
    proc ::aurig::core::util::readYamlMinimal {args} {
        incr ::__rym_called
        return [::__real_readYamlMinimal {*}$args]
    }
}

# ---------------------------------------------------------------------------
# Self-contained sandbox: two canonical-shaped manifests (multi-key file_sets
# list items -- exactly what readYamlMinimal mis-reads) differing only in the
# `top` key, plus a tiny VHDL source the no-top path could otherwise enumerate.
#   - no-top    -> exercises the :1061 collect_project_files site
#   - top-present -> exercises the :1390 collect_project_files + :1417 file_sets
#                    fallback site (the dangerous masked-absence path)
# ---------------------------------------------------------------------------
set sandbox [file join $test_dir .tmp_doc_absent]
file delete -force $sandbox
file mkdir [file join $sandbox rtl]

set vp [open [file join $sandbox rtl leaf.vhd] w]
fconfigure $vp -translation lf
puts $vp {entity leaf is port (clk : in bit); end entity leaf;}
puts $vp {architecture rtl of leaf is begin end architecture rtl;}
close $vp

proc write_manifest {path top} {
    set fp [open $path w]
    fconfigure $fp -translation lf
    puts $fp "project_name: doc_absent_sandbox"
    puts $fp "project_root: \".\""
    if {$top ne ""} { puts $fp "top: $top" }
    puts $fp "file_sets:"
    puts $fp "  rtl:"
    puts $fp "    - lib: work"
    puts $fp "      src:"
    puts $fp "        - \"rtl/*.vhd\""
    puts $fp "      vhdl_std: \"2008\""
    close $fp
}

set manifest_no_top [file join $sandbox project_no_top.yaml]
set manifest_top    [file join $sandbox project_top.yaml]
write_manifest $manifest_no_top ""
write_manifest $manifest_top    "leaf"

# ---------------------------------------------------------------------------
# Per-mode assertions: project_documenter must FAIL LOUDLY with tcllib guidance,
# and the readYamlMinimal tripwire must show ZERO reach on the manifest.
# ---------------------------------------------------------------------------
proc run_mode {child label manifest sandbox} {
    $child eval {set ::__rym_called 0}
    set outdir [file join $sandbox out_$label]
    set rc [$child eval [list catch \
        [list ::aurig::doc::project_documenter \
            -config $manifest -outdir $outdir -format md -verbosity 0] \
        ::pd_err]]
    set err [$child eval {set ::pd_err}]
    set rym [$child eval {set ::__rym_called}]

    check "$label: project_documenter FAILS when tcllib absent" {$rc != 0} \
        "project_documenter unexpectedly returned a result"
    check "$label: failure names tcllib" \
        {[string match -nocase {*tcllib*} $err]} "msg: $err"
    check "$label: failure names the yaml package" \
        {[string match -nocase {*yaml*} $err]} "msg: $err"
    check "$label: guidance mentions how to install (apt-get/teacup/auto_path)" \
        {[string match -nocase {*apt-get*} $err] ||
         [string match -nocase {*teacup*} $err] ||
         [string match -nocase {*auto_path*} $err]} "msg: $err"
    check "$label: readYamlMinimal was NEVER reached on the manifest" {$rym == 0} \
        "readYamlMinimal was invoked ($rym times) -- silent fallback occurred"
    # The pre-flight fires before ANY filesystem side effect (outdir creation,
    # logo emission, manifest read), so the loud failure must be entirely
    # SIDE-EFFECT-FREE. These assertions fail against the
    # pre-move code (which ran _ensure_dir + logo emission before the gate) and
    # pass after.
    check "$label: NO outdir was created on the failed run" \
        {![file exists $outdir]} \
        "outdir '$outdir' exists despite the loud tcllib-absent failure"
    check "$label: NO LM_LOGO-full.png was emitted on the failed run" \
        {![file exists [file join $outdir LM_LOGO-full.png]]} \
        "a stray LM_LOGO-full.png was emitted despite the loud failure"
    check "$label: no documentation index was emitted on the failed run" \
        {![file exists [file join $outdir index.md]]} \
        "an index.md was produced despite the loud failure"
}

run_mode $child "no-top"      $manifest_no_top $sandbox
run_mode $child "top-present" $manifest_top    $sandbox

file delete -force $sandbox
interp delete $child

puts "\n========================================"
puts "  passed: $::pass    failed: $::fail"
puts "========================================"
exit [expr {$::fail == 0 ? 0 : 1}]
