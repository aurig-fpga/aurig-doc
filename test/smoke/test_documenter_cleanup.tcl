#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

# Zero-assertion smoke for documenter argument validation: it drives the
# bad-argument / missing-argument / invalid-format paths and prints what comes
# back. It has no pass/fail bookkeeping and no exit code, so it lives in
# test/smoke/ and is NOT part of the gate. Run it by hand for a quick eyeball.
#
# Re-anchored for aurig-doc: resolves aurig::doc from its own repo root
# (core comes from aurig-core via TCLLIBPATH on ::auto_path) instead of the
# upstream `source document/documenter.tcl`.

set smoke_dir [file dirname [file normalize [info script]]]
set doc_root  [file dirname [file dirname $smoke_dir]]
if {[lsearch -exact $::auto_path $doc_root] < 0} {
    lappend ::auto_path $doc_root
}
package require aurig::doc

puts "=== Test 1: -help flag ==="
::aurig::doc::documenter -help

puts "\n=== Test 2: No arguments ==="
::aurig::doc::documenter

puts "\n=== Test 3: Odd number of arguments ==="
::aurig::doc::documenter -input

puts "\n=== Test 4: Invalid switch ==="
::aurig::doc::documenter -invalid value

puts "\n=== Test 5: Missing -input ==="
::aurig::doc::documenter -format md

puts "\n=== Test 6: Missing -format ==="
::aurig::doc::documenter -input test/test_entity.vhd

puts "\n=== Test 7: Invalid format ==="
::aurig::doc::documenter -input test/test_entity.vhd -format xml

puts "\n=== Test 8: File not found ==="
::aurig::doc::documenter -input nonexistent.vhd -format md

puts "\n=== All validation tests completed ==="
