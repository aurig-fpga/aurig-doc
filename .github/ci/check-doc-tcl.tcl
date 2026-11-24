# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

if {[llength $argv] != 1} {
    error "usage: check-doc-tcl.tcl <core-checkout>"
}
set doc_root [file dirname [file dirname [file dirname [file normalize [info script]]]]]
set core_root [file normalize [lindex $argv 0]]
lappend auto_path $doc_root

puts "Tcl patchlevel: [info patchlevel]"
puts "Tcl executable: [info nameofexecutable]"
puts "Tcl system encoding: [encoding system]"
if {[info tclversion] ne "8.6"} {
    error "Expected Tcl 8.6"
}

proc record_source {command op} {
    lappend ::loaded_sources [file normalize [lindex $command end]]
}
set loaded_sources {}
trace add execution ::source enter record_source
set doc_version [package require aurig::doc]
trace remove execution ::source enter record_source
puts "aurig::doc $doc_version from $doc_root"
puts "aurig::core [package present aurig::core] from $core_root"
foreach {root relative} [list $doc_root document/documenter.tcl \
    $core_root core.tcl $core_root util/vhdl_source.tcl $core_root analyze/vhdlscan.tcl] {
    set expected [file normalize [file join $root $relative]]
    if {$expected ni $loaded_sources} {
        error "Expected package source $expected. Loaded sources: $loaded_sources"
    }
    puts "Loaded $expected"
}
puts "yaml [package require yaml]"
