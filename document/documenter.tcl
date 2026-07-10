# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#############################################
# aurig-doc documenter: generate documentation for VHDL files
# Supports Markdown and HTML formats.
#
# Example:
#   ::aurig::doc::documenter \
#       -input ../test0/src/ces_util_fifo_test0.vhd \
#       -format html \
#       -output my_doc.html
#
# Options:
#   -input   : path to VHDL file (required)
#   -format  : md | html (required)
#   -output  : output filename (optional; defaults to <basename>.md or <basename>.html)
#   -help    : show usage

# Parser/util closure this layer builds on (::aurig::core::analyze::* and
# ::aurig::core::util::*). aurig-doc does not bundle core, so declare the
# dependency explicitly (idempotent under the package index).
package require aurig::core

namespace eval ::aurig::doc {
	namespace export documenter _emit_md_doc _emit_html_doc
}

proc ::aurig::doc::documenter {args} {
	# Check for -help first
	if {"-help" in $args || [llength $args] == 0} {
		puts "Usage: ::aurig::doc::documenter -input <file> -format <md|html> \[-output <file>\]"
		puts ""
		puts "Options:"
		puts "  -input   : path to VHDL file (required)"
		puts "  -format  : md | html (required)"
		puts "  -output  : output filename (optional; defaults to <basename>.md or <basename>.html)"
		return
	}

	# Parse command-line arguments
	set input_file ""
	set format ""
	set output_file ""

	set i 0
	while {$i < [llength $args]} {
		set switch [lindex $args $i]
		incr i

		if {$i >= [llength $args]} {
			puts "ERROR: Switch $switch requires a value"
			return
		}

		set value [lindex $args $i]
		incr i

		switch -- $switch {
			"-input" {
				set input_file $value
			}
			"-format" {
				set format $value
			}
			"-output" {
				set output_file $value
			}
			default {
				puts "ERROR: Invalid switch: $switch"
				puts "Use -help for usage information."
				return
			}
		}
	}

	# Validate required arguments
	if {$input_file eq ""} {
		puts "ERROR: -input is required."
		return
	}

	if {![file exists $input_file]} {
		puts "ERROR: Input file not found: $input_file"
		return
	}
	if {![file isfile $input_file]} {
		puts "ERROR: Input file is not a regular file: $input_file"
		return
	}

	if {$format eq ""} {
		puts "ERROR: -format is required."
		return
	}

	if {$format ni {md html}} {
		puts "ERROR: -format must be md or html."
		return
	}

	# Determine output filename if not provided
	if {$output_file eq ""} {
		set base [file rootname [file tail $input_file]]
		if {$format eq "html"} {
			set output_file "$base.html"
		} else {
			set output_file "$base.md"
		}
	}

	# Use the structured parser to analyze the VHDL file
	if {[catch {set parse_dict [::aurig::core::analyze::vhdlscan -in $input_file]} err]} {
		puts "ERROR: Failed to parse VHDL file: $err"
		return
	}

	# Open a log channel for the emit procedures (write to stdout)
	set LOG stdout

	# Generate documentation using the appropriate emit procedure
	if {$format eq "html"} {
		::aurig::doc::_emit_html_doc $parse_dict $output_file $LOG
	} else {
		::aurig::doc::_emit_md_doc $parse_dict $output_file $LOG
	}

	puts "Documentation written to $output_file"
}

# -----------------------------
# Emit HTML documentation from parse_dict
# -----------------------------
proc ::aurig::doc::_emit_html_doc {parse_dict out_file LOG {sourceViewerMap {}} {allHierarchy {}} {reverseHierarchy {}} {currentEntity {}}} {
	# Prefer official query helpers over manual dict traversal
	# Title = first entity name, if any
	set title "VHDL Documentation"
	set entity_names [::aurig::core::analyze::q_entity_names $parse_dict]
	if {[llength $entity_names] > 0} { set title [lindex $entity_names 0] }

	set fp [open $out_file w]
	fconfigure $fp -translation lf -encoding utf-8
	puts $fp "<!DOCTYPE html>"
	puts $fp "<html><head><meta charset=\"utf-8\"><title>$title</title>"
	puts $fp "<style>@import url('https://fonts.googleapis.com/css2?family=Oswald:wght@200..700&display=swap');@import url('https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100..900;1,100..900&display=swap');body{font-family:'Oswald',serif;margin:24px;color:#2f2a25} table{border-collapse:collapse;margin:12px 0} th,td{border:1px solid #ddd;padding:6px 10px} th{background:#f7f7f7;color:#2f2a25;font-weight:600} h1{margin-bottom:4px} h2{margin-top:24px} p,td{font-family:'Roboto',serif;line-height:1.6} a{color:#942c13;text-decoration:none} a:hover{text-decoration:underline} .comment{font-style:italic;color:#666} .metadata{background:#f9f9f9;padding:12px;margin:12px 0;border-left:4px solid #942c13} .footer{margin-top:40px;padding-top:20px;border-top:2px solid #ddd;text-align:center;color:#666;font-size:0.9em} .footer img{max-width:250px;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto} .footer a{color:#942c13;font-weight:500;text-decoration:none} .footer a:hover{text-decoration:underline}</style>"
	puts $fp "</head><body>"
	puts $fp "<h1>$title</h1>"

	# Always show source file link if available
	if {[dict exists $parse_dict meta file]} {
		set source_file [dict get $parse_dict meta file]
		# Check if we have a source viewer page for this file
		if {$sourceViewerMap ne "" && [dict exists $sourceViewerMap $source_file]} {
			set viewer_page [dict get $sourceViewerMap $source_file]
			puts $fp "<p><strong>Source File:</strong> <a href='$viewer_page'>[file tail $source_file]</a> (<code>$source_file</code>)</p>"
		} else {
			# Fallback to file:// URL
			set file_url "file:///[string map {{ } %20} [string map {\\ /} $source_file]]"
			puts $fp "<p><strong>Source File:</strong> <a href='$file_url' target='_blank'>[file tail $source_file]</a> (<code>$source_file</code>)</p>"
		}
	}

	# Header Metadata section
	if {[dict exists $parse_dict metadata]} {
		puts $fp "<div class='metadata'>"
		puts $fp "<h3>File Information</h3>"

		if {[dict exists $parse_dict metadata module_name]} {
			puts $fp "<p><strong>Module:</strong> [dict get $parse_dict metadata module_name]</p>"
		}
		if {[dict exists $parse_dict metadata author]} {
			puts $fp "<p><strong>Author:</strong> [dict get $parse_dict metadata author]</p>"
		}
		if {[dict exists $parse_dict metadata company]} {
			puts $fp "<p><strong>Company:</strong> [dict get $parse_dict metadata company]</p>"
		}
		if {[dict exists $parse_dict metadata project]} {
			puts $fp "<p><strong>Project:</strong> [dict get $parse_dict metadata project]</p>"
		}
		if {[dict exists $parse_dict metadata library]} {
			puts $fp "<p><strong>Library:</strong> [dict get $parse_dict metadata library]</p>"
		}
		if {[dict exists $parse_dict metadata description]} {
			puts $fp "<p><strong>Description:</strong> [dict get $parse_dict metadata description]</p>"
		}
		puts $fp "</div>"
	}

	# Libraries via q_libraries
	set libs [::aurig::core::analyze::q_libraries $parse_dict]
	if {[llength $libs] > 0} {
		puts $fp "<h2>Libraries</h2><table><tr><th>Name</th></tr>"
		foreach item $libs {
			if {[dict exists $item name]} { puts $fp "<tr><td>[dict get $item name]</td></tr>" }
		}
		puts $fp "</table>"
	}

	# Use clauses via q_uses
	set uses [::aurig::core::analyze::q_uses $parse_dict]
	if {[llength $uses] > 0} {
		puts $fp "<h2>Use Clauses</h2><table><tr><th>Library</th><th>Package</th><th>Selector</th></tr>"
		foreach item $uses {
			set lib [expr {[dict exists $item lib] ? [dict get $item lib] : ""}]
			set pkg [expr {[dict exists $item pkg] ? [dict get $item pkg] : ""}]
			set sel [expr {[dict exists $item selector] ? [dict get $item selector] : ""}]
			puts $fp "<tr><td>$lib</td><td>$pkg</td><td>$sel</td></tr>"
		}
		puts $fp "</table>"
	}

	# Entities, Generics, Ports using q_entity_* helpers
	foreach ename $entity_names {
		puts $fp "<h2>Entity: $ename</h2>"

		# Entity comment if available
		if {[dict exists $parse_dict entities]} {
			foreach ent [dict get $parse_dict entities] {
				if {[dict exists $ent name] && [dict get $ent name] eq $ename} {
					if {[dict exists $ent comment]} {
						puts $fp "<p class='comment'>[dict get $ent comment]</p>"
					}
					break
				}
			}
		}

		set generics [::aurig::core::analyze::q_entity_generics $parse_dict $ename]
		if {[llength $generics] > 0} {
			puts $fp "<h3>Generics</h3><table><tr><th>Name</th><th>Type</th><th>Init</th><th>Description</th></tr>"
			set prev_comment ""
			foreach g $generics {
				set n ""
				set t ""
				set i ""
				set c ""
				set n [expr {[dict exists $g name] ? [dict get $g name] : ""}]
				set t [expr {[dict exists $g type] ? [dict get $g type] : ""}]
				set i [expr {[dict exists $g init] ? [dict get $g init] : ""}]
				set c [expr {[dict exists $g comment] ? [dict get $g comment] : ""}]
				# Filter out duplicate comments from parser - if same comment as previous, treat as no comment
				if {$c eq $prev_comment && $c ne ""} {
					set c ""
				}
				set prev_comment $c
				if {$t eq ""} { set t "-" }
				if {$i eq ""} { set i "-" }
				if {$c eq ""} { set c "-" }
				puts $fp "<tr><td>$n</td><td>$t</td><td>$i</td><td class='comment'>$c</td></tr>"
			}
			puts $fp "</table>"
		}

		set ports [::aurig::core::analyze::q_entity_ports $parse_dict $ename]
		if {[llength $ports] > 0} {
			puts $fp "<h3>Ports</h3><table><tr><th>Name</th><th>Mode</th><th>Type</th><th>Description</th></tr>"
			set prev_comment ""
			foreach p $ports {
				set n ""
				set m ""
				set t ""
				set c ""
				set n [expr {[dict exists $p name] ? [dict get $p name] : ""}]
				set m [expr {[dict exists $p mode] ? [dict get $p mode] : ""}]
				set t [expr {[dict exists $p type] ? [dict get $p type] : ""}]
				set c [expr {[dict exists $p comment] ? [dict get $p comment] : ""}]
				# Filter out duplicate comments from parser - if same comment as previous, treat as no comment
				if {$c eq $prev_comment && $c ne ""} {
					set c ""
				}
				set prev_comment $c
				if {$m eq ""} { set m "-" }
				if {$t eq ""} { set t "-" }
				if {$c eq ""} { set c "-" }
				puts $fp "<tr><td>$n</td><td>$m</td><td>$t</td><td class='comment'>$c</td></tr>"
			}
			puts $fp "</table>"
		}

		# Generate and embed SVG symbol
		set svg_symbol [::aurig::doc::_generate_entity_symbol $ename $generics $ports]
		puts $fp "<h3>Block Symbol</h3>"
		puts $fp "<div class=\"symbol\" style=\"background:#fff;border:1px solid #ddd;padding:20px;margin:12px 0;text-align:center;\">"
		puts $fp $svg_symbol
		puts $fp "</div>"

		# Package Dependencies - show which packages this entity uses
		set entityUses [::aurig::core::analyze::q_uses $parse_dict]
		if {[llength $entityUses] > 0} {
			set hasRealPkgs 0
			set pkgBuffer ""
			foreach u $entityUses {
				set lib [expr {[dict exists $u lib] ? [dict get $u lib] : ""}]
				set pkg [expr {[dict exists $u pkg] ? [dict get $u pkg] : ""}]
				if {$pkg ne "" && $pkg ne "ALL" && $lib ne ""} {
					set hasRealPkgs 1
					set pkgSlug [::aurig::doc::_slug $pkg]
					set pkgLink "<a href='pkg_$pkgSlug.html'>$lib.$pkg</a>"
					append pkgBuffer "<tr><td>$pkgLink</td><td>Used by this entity</td></tr>"
				}
			}
			if {$hasRealPkgs} {
				puts $fp "<h3>Package Dependencies</h3><table><tr><th>Library.Package</th><th>Description</th></tr>"
				puts $fp $pkgBuffer
				puts $fp "</table>"
			}
		}

		# Hierarchy & Dependencies - consolidated view showing both parents and children
		if {$currentEntity ne ""} {
			# Try to find entity in hierarchy dicts with multiple key variations
			set children [list]
			set parents [list]

			# Try finding children - test both plain name and all dict keys
			if {$allHierarchy ne ""} {
				if {[dict exists $allHierarchy $currentEntity]} {
					set children [dict get $allHierarchy $currentEntity]
				} else {
					# Try looking for library-prefixed versions
					foreach key [dict keys $allHierarchy] {
						set strippedKey [::aurig::doc::_strip_lib_prefix $key]
						if {$strippedKey eq $currentEntity} {
							set children [dict get $allHierarchy $key]
							break
						}
					}
				}
			}

			# Try finding parents - test both plain name and all dict keys
			if {$reverseHierarchy ne ""} {
				if {[dict exists $reverseHierarchy $currentEntity]} {
					set parents [dict get $reverseHierarchy $currentEntity]
				} else {
					# Try looking for library-prefixed versions
					foreach key [dict keys $reverseHierarchy] {
						set strippedKey [::aurig::doc::_strip_lib_prefix $key]
						if {$strippedKey eq $currentEntity} {
							set parents [dict get $reverseHierarchy $key]
							break
						}
					}
				}
			}

			# Display consolidated hierarchy section if we found parents or children
			if {[llength $parents] > 0 || [llength $children] > 0} {
				puts $fp "<h3>Hierarchy & Dependencies</h3>"

				# Parent Entities (who uses this module)
				if {[llength $parents] > 0} {
					puts $fp "<h4>Used By (Parent Entities)</h4>"
					puts $fp "<table><tr><th>Entity</th><th>Description</th></tr>"
					foreach parent $parents {
						set parentName [::aurig::doc::_strip_lib_prefix $parent]
						set parentSlug [::aurig::doc::_slug $parentName]
						set parentLink "<a href='$parentSlug.html'>$parent</a>"
						puts $fp "<tr><td>$parentLink</td><td>Instantiates this entity</td></tr>"
					}
					puts $fp "</table>"
				}

				# Skip child entities table - it's shown in Architecture Instantiations section below
				# (The detailed instantiation information is in the Architecture section)
			}
		}
	}

	# Architectures via q_architectures and related helpers
	set archs [::aurig::core::analyze::q_architectures $parse_dict]
	if {[llength $archs] > 0} {
		foreach arch $archs {
			set aname   [expr {[dict exists $arch name]   ? [dict get $arch name]   : "arch"}]
			set aentity [expr {[dict exists $arch entity] ? [dict get $arch entity] : ""}]
			puts $fp "<h2>Architecture: $aname of $aentity</h2>"

			# Instantiations
			set insts [::aurig::core::analyze::q_arch_instantiations $parse_dict $arch]
			if {[llength $insts] > 0} {
			puts $fp "<h3>Instantiations</h3><table><tr><th>Label</th><th>Line</th><th>Entity</th><th>Description</th></tr>"
			foreach inst $insts {
				set lbl  [expr {[dict exists $inst label]  ? [dict get $inst label]  : ""}]
				set enty [expr {[dict exists $inst entity] ? [dict get $inst entity] : ""}]
				set comp [expr {[dict exists $inst component] ? [dict get $inst component] : ""}]
				set cmt  [expr {[dict exists $inst comment] ? [dict get $inst comment] : ""}]
				set line [expr {[dict exists $inst line] ? [dict get $inst line] : ""}]
				set cond [expr {[dict exists $inst condition] ? [dict get $inst condition] : ""}]

				# Use entity if present, otherwise use component
				set displayName [expr {$enty ne "" ? $enty : $comp}]

				# Create link if entity exists in the project
				set childName [::aurig::doc::_strip_lib_prefix $displayName]
				set childSlug [::aurig::doc::_slug $childName]
				set displayLink "<a href='$childSlug.html'>$displayName</a>"

				# Use line number if label is empty
				if {$lbl eq "" && $line ne ""} {
					set lbl "line $line"
				}
				if {$line eq ""} { set line "-" }

				# Build description with condition if present
				set desc_text ""
				if {$cond ne ""} {
					set desc_text "if $cond"
				}
				if {$cmt ne ""} {
					if {$desc_text ne ""} { append desc_text " - " }
					append desc_text $cmt
				}
				if {$desc_text eq ""} { set desc_text "-" }

				puts $fp "<tr><td>$lbl</td><td>$line</td><td>$displayLink</td><td class='comment'>$desc_text</td></tr>"
			}
			puts $fp "</table>"
		}

		# Processes
			set procs [::aurig::core::analyze::q_arch_processes $parse_dict $arch]
			if {[llength $procs] > 0} {
				puts $fp "<h3>Processes</h3><table><tr><th>Label</th><th>Sensitivity</th><th>Description</th></tr>"
				foreach pr $procs {
					set lbl  [expr {[dict exists $pr label] ? [dict get $pr label] : ""}]
					set sens [expr {[dict exists $pr sensitivity] ? [join [dict get $pr sensitivity] ", "] : ""}]
					set cmt  [expr {[dict exists $pr comment] ? [dict get $pr comment] : ""}]
					set line [expr {[dict exists $pr line] ? [dict get $pr line] : ""}]

					# Use line number if label is empty
					if {$lbl eq "" && $line ne ""} {
						set lbl "line $line"
					}

					# Use dash if comment is empty
					if {$cmt eq ""} {
						set cmt "-"
					}

					puts $fp "<tr><td>$lbl</td><td>$sens</td><td class='comment'>$cmt</td></tr>"
				}
				puts $fp "</table>"
			}

			# Signals (declarations) via q_arch_signals
			set sigs [::aurig::core::analyze::q_arch_signals $parse_dict $arch]
			if {[llength $sigs] > 0} {
				puts $fp "<h3>Signals</h3><table><tr><th>Name</th><th>Type</th><th>Init</th><th>Description</th></tr>"
				set prev_comment ""
				foreach d $sigs {
					set n [expr {[dict exists $d name] ? [dict get $d name] : ""}]
					# Type and init are in first element of args list
					set t ""
					set initval ""
					if {[dict exists $d args]} {
						set args_val [dict get $d args]
						if {[llength $args_val] > 0} {
							set args_dict [lindex $args_val 0]
							set t [expr {[dict exists $args_dict type] ? [dict get $args_dict type] : ""}]
							set initval [expr {[dict exists $args_dict init] ? [dict get $args_dict init] : ""}]
						}
					}
					set cmt [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
					# Filter out duplicate comments from parser
					if {$cmt eq $prev_comment && $cmt ne ""} {
						set cmt ""
					}
					set prev_comment $cmt
					if {$t eq ""} { set t "-" }
					if {$initval eq ""} { set initval "-" }
					if {$cmt eq ""} {
						set cmt "-"
					}
					puts $fp "<tr><td>$n</td><td>$t</td><td>$initval</td><td class='comment'>$cmt</td></tr>"
				}
				puts $fp "</table>"
			}

			# Constants via q_arch_decls_by_kind
			set consts [::aurig::core::analyze::q_arch_decls_by_kind $parse_dict $arch constant]
			if {[llength $consts] > 0} {
				puts $fp "<h3>Constants</h3><table><tr><th>Name</th><th>Type</th><th>Init</th><th>Description</th></tr>"
				set prev_comment ""
				foreach d $consts {
					set n ""
					set t ""
					set initval ""
					set cmt ""
					set n [expr {[dict exists $d name] ? [dict get $d name] : ""}]
					# Extract type and init from args structure (same as signals)
					if {[dict exists $d args]} {
						set args_val [dict get $d args]
						if {[llength $args_val] > 0} {
							set args_dict [lindex $args_val 0]
							set t [expr {[dict exists $args_dict type] ? [dict get $args_dict type] : ""}]
							set initval [expr {[dict exists $args_dict init] ? [dict get $args_dict init] : ""}]
						}
					}
					set cmt [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
					# Filter out duplicate comments from parser
					if {$cmt eq $prev_comment && $cmt ne ""} {
						set cmt ""
					}
					set prev_comment $cmt
					if {$t eq ""} { set t "-" }
					if {$initval eq ""} { set initval "-" }
					if {$cmt eq ""} { set cmt "-" }
					puts $fp "<tr><td>$n</td><td>$t</td><td>$initval</td><td class='comment'>$cmt</td></tr>"
				}
				puts $fp "</table>"
			}

			# Functions via q_arch_functions
			set funcs [::aurig::core::analyze::q_arch_functions $parse_dict $arch]
			if {[llength $funcs] > 0} {
				puts $fp "<h3>Functions</h3><table><tr><th>Name</th><th>Parameters</th><th>Return</th><th>Description</th></tr>"
				foreach d $funcs {
					set n [expr {[dict exists $d name] ? [dict get $d name] : ""}]
					set params ""
					set retType ""
					# Extract params and return from args structure
					if {[dict exists $d args]} {
						set args_val [dict get $d args]
						if {[llength $args_val] > 0} {
							set args_dict [lindex $args_val 0]
							set params [expr {[dict exists $args_dict params] ? [dict get $args_dict params] : ""}]
							set retType [expr {[dict exists $args_dict return] ? [dict get $args_dict return] : ""}]
						}
					}
					set cmt [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]

					# Format parameters: one per line
					set formattedParams ""
					if {$params ne ""} {
						set paramList [split $params ";"]
						set trimmedParams {}
						foreach p $paramList {
							set trimmed [string trim $p]
							if {$trimmed ne ""} {
								lappend trimmedParams $trimmed
							}
						}
						set formattedParams [join $trimmedParams "<br>"]
					}

					puts $fp "<tr><td>$n</td><td>$formattedParams</td><td>$retType</td><td class='comment'>$cmt</td></tr>"
				}
				puts $fp "</table>"
			}

			# Procedures via q_arch_procedures
			set procs [::aurig::core::analyze::q_arch_procedures $parse_dict $arch]
			if {[llength $procs] > 0} {
				puts $fp "<h3>Procedures</h3><table><tr><th>Name</th><th>Parameters</th><th>Description</th></tr>"
				foreach d $procs {
					set n [expr {[dict exists $d name] ? [dict get $d name] : ""}]
					set params ""
					# Extract params from args structure
					if {[dict exists $d args]} {
						set args_val [dict get $d args]
						if {[llength $args_val] > 0} {
							set args_dict [lindex $args_val 0]
							set params [expr {[dict exists $args_dict params] ? [dict get $args_dict params] : ""}]
						}
					}
					set cmt [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]

					# Format parameters: one per line
					set formattedParams ""
					if {$params ne ""} {
						set paramList [split $params ";"]
						set trimmedParams {}
						foreach p $paramList {
							set trimmed [string trim $p]
							if {$trimmed ne ""} {
								lappend trimmedParams $trimmed
							}
						}
						set formattedParams [join $trimmedParams "<br>"]
					}

					puts $fp "<tr><td>$n</td><td>$formattedParams</td><td class='comment'>$cmt</td></tr>"
				}
				puts $fp "</table>"
			}
		}
	}

	puts $fp "</body></html>"
	close $fp
	puts $LOG "HTML documentation written to $out_file"
}

# -----------------------------
# Emit Markdown documentation from parse_dict
# -----------------------------
proc ::aurig::doc::_emit_md_doc {parse_dict out_file LOG} {
	set title "VHDL Documentation"
	if {[dict exists $parse_dict entities] && [llength [dict get $parse_dict entities]] > 0} {
		set ent [lindex [dict get $parse_dict entities] 0]
		if {[dict exists $ent name]} { set title [dict get $ent name] }
	}
	set fp [open $out_file w]
	fconfigure $fp -translation lf -encoding utf-8
	puts $fp "# $title"

	# Header Metadata section
	if {[dict exists $parse_dict metadata]} {
		puts $fp "\n## File Information\n"
		if {[dict exists $parse_dict metadata module_name]} {
			puts $fp "**Module:** [dict get $parse_dict metadata module_name]  "
		}
		if {[dict exists $parse_dict metadata author]} {
			puts $fp "**Author:** [dict get $parse_dict metadata author]  "
		}
		if {[dict exists $parse_dict metadata company]} {
			puts $fp "**Company:** [dict get $parse_dict metadata company]  "
		}
		if {[dict exists $parse_dict metadata project]} {
			puts $fp "**Project:** [dict get $parse_dict metadata project]  "
		}
		if {[dict exists $parse_dict metadata library]} {
			puts $fp "**Library:** [dict get $parse_dict metadata library]  "
		}
		if {[dict exists $parse_dict metadata description]} {
			puts $fp "\n**Description:** [dict get $parse_dict metadata description]  "
		}
	}

	if {[dict exists $parse_dict libraries]} {
		puts $fp "\n## Libraries\n"
		puts $fp "| Name |\n|---|"
		foreach item [dict get $parse_dict libraries] {
			if {[dict exists $item name]} { puts $fp "| [dict get $item name] |" }
		}
	}

	if {[dict exists $parse_dict uses]} {
		puts $fp "\n## Use Clauses\n"
		puts $fp "| Library | Package | Selector |\n|---|---|---|"
		foreach item [dict get $parse_dict uses] {
			set lib [expr {[dict exists $item lib] ? [dict get $item lib] : ""}]
			set pkg [expr {[dict exists $item pkg] ? [dict get $item pkg] : ""}]
			set sel [expr {[dict exists $item selector] ? [dict get $item selector] : ""}]
			puts $fp "| $lib | $pkg | $sel |"
		}
	}

	if {[dict exists $parse_dict entities]} {
		foreach ent [dict get $parse_dict entities] {
			set ename [expr {[dict exists $ent name] ? [dict get $ent name] : "entity"}]
			puts $fp "\n## Entity: $ename\n"

			# Entity comment if available
			if {[dict exists $ent comment]} {
				puts $fp "*[dict get $ent comment]*\n"
			}

			if {[dict exists $ent generics] && [llength [dict get $ent generics]]} {
				puts $fp "\n### Generics\n| Name | Type | Init | Description |\n|---|---|---|---|"
				foreach g [dict get $ent generics] {
					set n [dict get $g name]
					set t [expr {[dict exists $g type] ? [dict get $g type] : ""}]
					set i [expr {[dict exists $g init] ? [dict get $g init] : ""}]
					set c [expr {[dict exists $g comment] ? [dict get $g comment] : ""}]
					puts $fp "| $n | $t | $i | $c |"
				}
			}
			if {[dict exists $ent ports] && [llength [dict get $ent ports]]} {
				puts $fp "\n### Ports\n| Name | Mode | Type | Description |\n|---|---|---|---|"
				foreach p [dict get $ent ports] {
					set n [dict get $p name]
					set m [expr {[dict exists $p mode] ? [dict get $p mode] : ""}]
					set t [expr {[dict exists $p type] ? [dict get $p type] : ""}]
					set c [expr {[dict exists $p comment] ? [dict get $p comment] : ""}]
					puts $fp "| $n | $m | $t | $c |"
				}
			}
		}
	}

	if {[dict exists $parse_dict architectures]} {
		foreach arch [dict get $parse_dict architectures] {
			set aname [expr {[dict exists $arch name] ? [dict get $arch name] : "arch"}]
			set aentity [expr {[dict exists $arch entity] ? [dict get $arch entity] : ""}]
			puts $fp "\n## Architecture: $aname of $aentity\n"
			if {[dict exists $arch instantiations] && [llength [dict get $arch instantiations]]} {
				puts $fp "\n### Instantiations\n| Label | Entity | Description |\n|---|---|---|"
				foreach inst [dict get $arch instantiations] {
					set lbl [expr {[dict exists $inst label] ? [dict get $inst label] : ""}]
					set enty [expr {[dict exists $inst entity] ? [dict get $inst entity] : ""}]
					set cmt [expr {[dict exists $inst comment] ? [dict get $inst comment] : ""}]
					puts $fp "| $lbl | $enty | $cmt |"
				}
			}
			if {[dict exists $arch processes] && [llength [dict get $arch processes]]} {
				puts $fp "\n### Processes\n| Label | Sensitivity | Description |\n|---|---|---|"
				foreach pr [dict get $arch processes] {
					set lbl [expr {[dict exists $pr label] ? [dict get $pr label] : ""}]
					set sens [expr {[dict exists $pr sensitivity] ? [join [dict get $pr sensitivity] ", "] : ""}]
					set cmt [expr {[dict exists $pr comment] ? [dict get $pr comment] : ""}]
					set line [expr {[dict exists $pr line] ? [dict get $pr line] : ""}]

					# Use line number if label is empty
					if {$lbl eq "" && $line ne ""} {
						set lbl "line $line"
					}

					# Use dash if comment is empty
					if {$cmt eq ""} {
						set cmt "-"
					}

					puts $fp "| $lbl | $sens | $cmt |"
				}
			}
			if {[dict exists $arch declarations] && [llength [dict get $arch declarations]]} {
				puts $fp "\n### Signals\n| Name | Type | Init | Description |\n|---|---|---|---|"
				foreach d [dict get $arch declarations] {
					if {[dict exists $d kind] && [string equal -nocase [dict get $d kind] signal]} {
						set n [expr {[dict exists $d name] ? [dict get $d name] : ""}]
						# Type and init are in first element of args list
						set t ""
						set initval ""
						if {[dict exists $d args]} {
							set args_val [dict get $d args]
							if {[llength $args_val] > 0} {
								set args_dict [lindex $args_val 0]
								set t [expr {[dict exists $args_dict type] ? [dict get $args_dict type] : ""}]
								set initval [expr {[dict exists $args_dict init] ? [dict get $args_dict init] : ""}]
							}
						}
						set cmt [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
						if {$cmt eq ""} {
							set cmt "-"
						}
						puts $fp "| $n | $t | $initval | $cmt |"
					}
				}
			}
		}
	}

	close $fp
	puts $LOG "Markdown documentation written to $out_file"
}
