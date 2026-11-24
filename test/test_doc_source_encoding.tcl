#!/usr/bin/env tclsh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

set doc [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $doc
set original [encoding system]
encoding system cp1252
package require aurig::doc
encoding system $original

set root [file join $doc test build "source encoding [pid] [clock clicks]"]
file mkdir $root
set failures 0
set assertions 0

proc check {label condition {detail ""}} {
    global assertions failures
    incr assertions
    if {!$condition} {
        incr failures
        puts stderr "FAIL $label $detail"
    }
}

proc write_bytes {path bytes} {
    set ch [open $path wb]
    puts -nonewline $ch $bytes
    close $ch
}

proc read_bytes {path} {
    set ch [open $path rb]
    set bytes [read $ch]
    close $ch
    return $bytes
}

# RFC 3629 byte grammar. Keep the oracle independent of Tcl's permissive
# decoder and of the Core reader. Byte comparisons below pin the text.
proc utf8_artifact {path} {
    set bytes [read_bytes $path]
    set name [file tail $path]
    set scalar {[\x00-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee-\xef][\x80-\xbf]{2}|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf]{2}|[\xf1-\xf3][\x80-\xbf]{3}|\xf4[\x80-\x8f][\x80-\xbf]{2}}
    check "$name strict UTF-8" [regexp -- "\\A(?:$scalar)*\\Z" $bytes]
    check "$name BOM-free" [expr {[string range $bytes 0 2] ne "\xef\xbb\xbf"}]
    check "$name LF output" [expr {[string first "\r" $bytes] < 0}]
    if {[file extension $path] eq ".html"} {
        contains "$name declares UTF-8" $bytes {<meta charset="utf-8">}
    }
    return $bytes
}

proc contains {label bytes expected} {
    check $label [expr {[string first $expected $bytes] >= 0}]
}

proc manifest {dir names {top ""} {project_name Encoding}} {
    set path [file join $dir project.yaml]
    set content "project_name: $project_name\nproject_root: .\n"
    if {$top ne ""} {
        append content "top: $top\n"
    }
    append content "file_sets:\n  rtl:\n    - lib: work\n      src:\n"
    foreach name $names {
        append content "        - $name\n"
    }
    write_bytes $path $content
    return $path
}

proc fixture {dir signature input_word expected_word suffix newline final} {
    file mkdir $dir
    # The source and expected escaped viewer text are specified separately.
    set head {entity Dut is
end entity;
-- Architecture @
architecture rtl of Dut is
  -- Signal @
  signal label_text : string := "@";
begin
  process
  begin
    wait;
  end process;
end architecture;
package Codes is
  -- Constant @
  constant banner : string := "@";
end package;}
    set raw [string map [list @ $input_word] $head]
    set expected [string map [list @ $expected_word] $head]
    append raw "\n-- Viewer </textarea><b> & ' \"\t$suffix"
    append expected "\n-- Viewer &lt;/textarea&gt;&lt;b&gt; &amp; &#39; &quot;\t$suffix"
    if {$final} {
        append raw \n
        append expected \n
    }
    set expected [string map {\" &quot;} $expected]
    if {$newline ne "\n"} {
        set raw [string map [list \n $newline] $raw]
    }
    write_bytes [file join $dir unit.vhd] "$signature$raw"
    return $expected
}

proc valid_cases {} {
    global root
    # Use explicit source and expected UTF-8 byte strings, including legacy
    # bytes that map to printable characters in Windows-1252.
    set accent [binary format H* 636166c3a920e282ac20c593]
    set legacy [binary format H* 636166e92080209c]
    set supplementary [binary format H* f09f9880]
    set feff [binary format H* efbbbf]
    set cases [list \
        [list ascii "" plain plain "" "\n" 1] \
        [list utf8 "" $accent $accent "" "\r\n" 1] \
        [list signed $feff $accent $accent "$feff\x1a" "\r" 0] \
        [list legacy "" $legacy $accent "" "\n" 0] \
        [list scalar "" "$accent $supplementary" "$accent $supplementary" "" "\n" 1]]

    foreach case $cases {
        lassign $case name signature input_word expected_word suffix newline final
        set dir [file join $root $name]
        set expected [fixture $dir $signature $input_word $expected_word $suffix $newline $final]
        set source [file join $dir unit.vhd]
        set cfg [manifest $dir {unit.vhd}]
        set first {}
        foreach host {utf-8 cp1252} {
            encoding system $host
            puts "CASE $name host=$host"
            foreach fmt {html md} {
                set dest [file join $dir $host $fmt]
                file mkdir $dest
                set single [file join $dest single.$fmt]
                ::aurig::doc::documenter -input $source -format $fmt -output $single
                set project [::aurig::doc::project_documenter -config $cfg -format $fmt -outdir $dest]
                check "$name/$host/$fmt success return" [expr {$project eq $dest}]
                foreach path [glob -directory $dest -types f *] {
                    if {[file extension $path] in {.html .md .txt}} {
                        set bytes [utf8_artifact $path]
                        # Generated timestamps can cross a second boundary.
                        regsub -all {[0-9]{2}:[0-9]{2}:[0-9]{2}} $bytes TIME comparable
                        set comparable [string map [list $dest OUTDIR] $comparable]
                        set key [list $fmt [file tail $path]]
                        if {$host eq "utf-8"} {
                            dict set first $key $comparable
                        } else {
                            check "$key identical across host codecs" [expr {$comparable eq [dict get $first $key]}]
                        }
                    }
                }

                foreach entity [list $single [file join $dest dut.$fmt]] {
                    set page [read_bytes $entity]
                    contains "entity title" $page [expr {$fmt eq "html" ? "<h1>Dut</h1>" : "# Dut"}]
                    contains "architecture title" $page {rtl of Dut}
                    contains "signal name" $page label_text
                    contains "signal literal" $page "\"$expected_word\""
                    contains "signal comment" $page "Signal $expected_word"
                    contains "process source line" $page [expr {$fmt eq "html" ? "<td>line 8</td>" : "| line 8 |"}]
                }
                if {$fmt eq "html"} {
                    set bytes [read_bytes [file join $dest dut.html]]
                    contains "project navigation home symbol" $bytes [binary format H* f09f8fa020486f6d65]
                }
                set pkg [read_bytes [file join $dest pkg_codes.$fmt]]
                contains "package title" $pkg {Package: Codes}
                contains "constant name" $pkg banner
                contains "constant literal" $pkg "\"$expected_word\""
                contains "constant comment" $pkg "Constant $expected_word"
                set index [read_bytes [file join $dest index.$fmt]]
                contains "index entity" $index Dut
                contains "index package" $index Codes
                if {$fmt eq "html"} {
                    contains "project index title typography" $index [binary format H* 456e636f64696e6720e2809320446f63756d656e746174696f6e]
                }

                set viewer [read_bytes [file join $dest src_unit.vhd.html]]
                set found [regexp {<textarea id='code'>(.*?)</textarea>} $viewer -> viewed]
                check "exact escaped viewer $name/$host/$fmt" [expr {$found && $viewed eq $expected}]
                if {$found} {
                    check "viewer starts with the declaration" [expr {[string first {entity Dut is} $viewed] == 0}]
                    contains "viewer comment decodes correctly" $viewed "Signal $expected_word"
                }
                if {$found} {
                    check "source line 4" [expr {[lindex [split $viewed \n] 3] eq "architecture rtl of Dut is"}]
                    check "source line 14" [expr {[lindex [split $viewed \n] 13] eq "  -- Constant $expected_word"}]
                }
                contains "viewer keeps line numbers" $viewer {lineNumbers: true}
                check "viewer text cannot close textarea" [expr {[string first {</textarea><b>} $viewer] < 0}]
            }
        }
    }
}

proc report_cases {} {
    global root
    set dir [file join $root report]
    file mkdir $dir
    write_bytes [file join $dir unit.vhd] {entity Dut is end entity;}
    foreach host {utf-8 cp1252} name_hex {436166c3a9 436166e9} {
        encoding system $host
        # The existing generic YAML reader uses the system codec. Supply the
        # same project name as Unicode under both reader settings.
        foreach top {{} Dut} mode {flat top} {
            set cfg [manifest $dir {unit.vhd} $top [binary format H* $name_hex]]
            set out [file join $dir $host $mode]
            ::aurig::doc::project_documenter -config $cfg -outdir $out -format md
            set report [utf8_artifact [file join $out documentation_report.txt]]
            contains "project report name in UTF-8 ($host/$mode)" $report [binary format H* 50726f6a6563743a20436166c3a9]
        }
    }
}

proc expect_error {label call expected} {
    set status [catch {uplevel 1 $call} message options]
    set actual {}
    if {$status == 1} {
        set actual [dict get $options -errorcode]
    }
    check $label [expr {$status == 1 && [lrange $actual 0 [expr {[llength $expected] - 1}]] eq $expected}] \
        "code={$actual} message={$message}"
    return $message
}

# Inject a channel READ error portably without requiring a special user,
# permission model, Tcl VFS extension or platform device.
proc fail_reads {command op} {
    if {[lindex $command 0] eq "read" && [llength $command] == 2} {
        return -code error -errorcode {POSIX EIO {synthetic read failure}} "synthetic read failure"
    }
}

proc fail_second_source_read {command op} {
    if {[file tail [lindex $command 1]] eq "valid.vhd" && [incr ::valid_reads] == 2} {
        return -code error -errorcode {AURIG CORE SOURCE IO READ {POSIX EIO {synthetic read failure}}} \
            "synthetic viewer read failure"
    }
}

proc rejected_cases {} {
    global root doc
    set dir [file join $root rejected]
    file mkdir $dir
    write_bytes [file join $dir valid.vhd] {entity Valid is end entity;}
    write_bytes [file join $dir malformed.vhd] "\xef\xbb\xbf-- \xe2\x82"
    write_bytes [file join $dir nul.vhd] "-- \x00\nentity Rejected is end entity;"
    set out [file join $dir single.html]
    foreach {name why} {
        malformed {INVALID_UTF8 6}
        nul {NUL 3}
        missing {IO OPEN}
    } {
        set source [file join $dir $name.vhd]
        expect_error "single $name" \
            [list ::aurig::doc::documenter -input $source -format html -output $out] \
            [concat {AURIG CORE SOURCE} $why]
        check "single $name created no artifact" [expr {![file exists $out]}]
    }
    trace add execution ::read enter fail_reads
    expect_error "single injected read failure" \
        [list ::aurig::doc::documenter -input [file join $dir valid.vhd] -format html -output $out] \
        {AURIG CORE SOURCE IO READ {POSIX EIO {synthetic read failure}}}
    trace remove execution ::read enter fail_reads

    set cfg [manifest $dir {valid.vhd}]
    set dest [file join $dir viewer_read_failure]
    set ::valid_reads 0
    trace add execution ::aurig::core::util::read_vhdl_source enter fail_second_source_read
    set message [expect_error "project source disappears from viewer read" \
        [list ::aurig::doc::project_documenter -config $cfg -outdir $dest] \
        {AURIG CORE SOURCE IO READ {POSIX EIO {synthetic read failure}}}]
    trace remove execution ::aurig::core::util::read_vhdl_source enter fail_second_source_read
    contains "report viewer read failure" $message {synthetic viewer read failure}
    foreach artifact {valid.html src_valid.vhd.html} {
        check "failed viewer read does not produce $artifact" [expr {![file exists [file join $dest $artifact]]}]
    }

    foreach top {{} Valid ./malformed.vhd} {
        set cfg [manifest $dir {malformed.vhd nul.vhd valid.vhd} $top]
        set dest [file join $dir "project [string map {/ _} $top]"]
        set msg [expect_error "mixed project top={$top}" \
            [list ::aurig::doc::project_documenter -config $cfg -outdir $dest] \
            {AURIG CORE SOURCE INVALID_UTF8 6}]
        foreach fragment {malformed.vhd {byte 6} nul.vhd {byte 3}} {
            contains "mixed API reports $fragment" $msg $fragment
        }
        foreach source {malformed nul} {
            check "no rejected viewer $source" [expr {![file exists [file join $dest src_${source}.vhd.html]]}]
        }
        if {$top ne "./malformed.vhd"} {
            check "valid entity generated" [file exists [file join $dest valid.html]]
            check "valid viewer generated" [file exists [file join $dest src_valid.vhd.html]]
        }
        set report [file join $dest documentation_report.txt]
        if {[file exists $report]} {
            set bytes [utf8_artifact $report]
            contains "report identifies partial output" $bytes {REJECTED VHDL SOURCES}
            contains "report names malformed source" $bytes {malformed.vhd}
            contains "report names NUL source" $bytes {nul.vhd}
            check "report has no unconditional success claim" [expr {[string first {successfully documented} $bytes] < 0}]
        }
        if {[file exists [file join $dest files.html]]} {
            set bytes [utf8_artifact [file join $dest files.html]]
            check "rejected files omitted from file list" [expr {![string match {*malformed.vhd*} $bytes] && ![string match {*nul.vhd*} $bytes]}]
        }

        set status [catch {
            exec [info nameofexecutable] [file join $doc tools run_doc_project_inprocess.tcl] \
                -manifest $cfg -outdir [file join $dest cli] 2>@1
        } output options]
        check "mixed CLI exits 2" [expr {$status == 1 && [lindex [dict get $options -errorcode] 2] eq "2"}] $output
        contains "mixed CLI error for malformed source" $output {byte 6}
        contains "mixed CLI error for NUL source" $output {byte 3}
    }

    set cfg [manifest $dir {valid.vhd} ./missing.vhd]
    set dest [file join $dir missing_top]
    expect_error "missing explicit top" \
        [list ::aurig::doc::project_documenter -config $cfg -outdir $dest] {AURIG CORE SOURCE IO OPEN}
    check "missing top generated no index" [expr {![file exists [file join $dest index.html]]}]

    # A failed rerun must leave earlier output alone while returning an error.
    write_bytes $out {preexisting artifact}
    expect_error "single file rejected with preexisting output" \
        [list ::aurig::doc::documenter -input [file join $dir nul.vhd] -format html -output $out] \
        {AURIG CORE SOURCE NUL 3}
    check "preexisting single-file output is untouched" [expr {[read_bytes $out] eq "preexisting artifact"}]
    set cfg [manifest $dir {nul.vhd valid.vhd}]
    set dest [file join $dir stale]
    file mkdir $dest
    set stale [file join $dest src_nul.vhd.html]
    write_bytes $stale {preexisting viewer}
    expect_error "mixed project rejected with preexisting output" \
        [list ::aurig::doc::project_documenter -config $cfg -outdir $dest] {AURIG CORE SOURCE NUL 3}
    check "preexisting project viewer is untouched" [expr {[read_bytes $stale] eq "preexisting viewer"}]
    set files [read_bytes [file join $dest files.html]]
    check "fresh file list omits preexisting rejected viewer" [expr {[string first src_nul.vhd.html $files] < 0}]
}

proc capability_cases {} {
    global root
    # Simulate older Core in this process. The task's separate probes also
    # exercise both exact old revisions in clean subprocesses.
    file mkdir [file join $root capability]
    set dir [file join $root capability]
    set source [file join $dir unit.vhd]
    write_bytes $source {entity Dut is end entity;}
    set cfg [manifest $dir {unit.vhd}]
    rename ::aurig::core::util::read_vhdl_source ::aurig::core::util::hidden_source_reader
    check "Doc package remains loadable" [expr {[package require aurig::doc] eq "0.1.0"}]
    foreach call [list \
        [list ::aurig::doc::documenter -input $source -format md -output [file join $dir unit.md]] \
        [list ::aurig::doc::project_documenter -config $cfg -outdir [file join $dir out]]] {
        set message [expect_error "older Core capability" $call {AURIG DOC SOURCE CAPABILITY}]
        contains "capability names missing reader" $message read_vhdl_source
        contains "capability gives dependency guidance" $message TCLLIBPATH
    }
    rename ::aurig::core::util::hidden_source_reader ::aurig::core::util::read_vhdl_source
    check "capability failure leaves no output" [expr {![file exists [file join $dir unit.md]] && ![file exists [file join $dir out]]}]
}

puts "Tcl [info patchlevel] via [info nameofexecutable]; evidence=[file nativename $root]"
foreach section {valid_cases report_cases rejected_cases capability_cases} {
    if {[catch {$section} problem options]} {
        check $section 0 [dict get $options -errorinfo]
    }
    encoding system $original
}
puts "Assertions: $assertions, failures: $failures"
exit [expr {$failures != 0}]
