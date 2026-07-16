# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#############################################
# aurig-doc project_documenter: generate project-wide documentation (HTML/Markdown)
# Namespace: ::aurig::doc
# Purpose  : From a YAML/INI project config, scan starting at the top-level
#             and produce per-entity/package documentation plus a navigable index.
#
# Usage:
#   ::aurig::doc::project_documenter \
#       -config project.yaml|-ini project.ini \
#       -outdir docs \
#       -format html|md \
#       -verbosity 3
#
# Notes:
# - Uses ::aurig::core::util::readYaml / ::aurig::core::util::readIni to load config.
# - Uses ::aurig::core::analyze::vhdlscan to parse source files.
# - Queries via ::aurig::core::analyze::q_* to extract structured info.
# - Emits per-entity and per-package pages and an index with hierarchy links.

# Parser/util closure this layer builds on (::aurig::core::analyze::* and
# ::aurig::core::util::*). aurig-doc does not bundle core, so declare the
# dependency explicitly (idempotent under the package index).
package require aurig::core

namespace eval ::aurig::doc {
    namespace export project_documenter
    variable _project_documenter_logo_bytes ""
}

proc ::aurig::doc::_load_project_documenter_logo {module_dir} {
    variable _project_documenter_logo_bytes

    set logo_path [file join $module_dir ".." "config" "LM_LOGO-full.png"]
    if {![file isfile $logo_path]} {
        return
    }

    if {[catch {open $logo_path r} fp]} {
        return
    }

    if {![catch {
        fconfigure $fp -translation binary -encoding binary
        read $fp
    } logo_bytes]} {
        set _project_documenter_logo_bytes $logo_bytes
    }
    catch {close $fp}
}

proc ::aurig::doc::_emit_project_documenter_logo {outdir} {
    variable _project_documenter_logo_bytes

    if {$_project_documenter_logo_bytes eq ""} {
        return 0
    }

    set logo_out [file join $outdir "LM_LOGO-full.png"]
    set fp ""
    if {[catch {
        set fp [open $logo_out w]
        fconfigure $fp -translation binary -encoding binary
        puts -nonewline $fp $_project_documenter_logo_bytes
    }]} {
        if {$fp ne ""} {
            catch {close $fp}
        }
        catch {file delete -force $logo_out}
        return 0
    }

    if {[catch {close $fp}]} {
        catch {file delete -force $logo_out}
        return 0
    }

    return 1
}

::aurig::doc::_load_project_documenter_logo [file dirname [info script]]

# Small helpers
proc ::aurig::doc::_ensure_dir {d} {
    if {![file exists $d]} { file mkdir $d }
}
proc ::aurig::doc::_write_file {path content} {
    set f [open $path w]; fconfigure $f -translation lf -encoding utf-8; puts $f $content; close $f
}
proc ::aurig::doc::_slug {name} {
    string map {" " "_" "/" "_" ":" "_"} [string tolower $name]
}

# Helper to strip library prefix from entity name
proc ::aurig::doc::_strip_lib_prefix {name} {
    if {[string match "*.*" $name]} {
        return [lindex [split $name "."] end]
    }
    return $name
}

# Helper to emit hierarchy tree recursively with collapsible sections (HTML)
proc ::aurig::doc::_emit_hierarchy_tree_collapsible {entity hierarchy fmt emitted path} {
    upvar $emitted seen

    # Avoid infinite loops on SAME PATH only (check if entity is in current path)
    if {[lsearch -exact $path $entity] >= 0} {
        return "<li><a href='[::aurig::doc::_slug [::aurig::doc::_strip_lib_prefix $entity]].$fmt'>$entity</a> <i>(recursive)</i></li>"
    }

    # Add to current path
    lappend path $entity

    set buf ""
    # Strip library prefix for slug/filename
    set simpleName [::aurig::doc::_strip_lib_prefix $entity]
    set slug [::aurig::doc::_slug $simpleName]

    # Try to find children with multiple key variations
    set children {}
    if {[dict exists $hierarchy $entity]} {
        set children [dict get $hierarchy $entity]
    } elseif {[dict exists $hierarchy $simpleName]} {
        set children [dict get $hierarchy $simpleName]
    } else {
        # Try matching by stripped name against all dict keys
        foreach key [dict keys $hierarchy] {
            set strippedKey [::aurig::doc::_strip_lib_prefix $key]
            if {$strippedKey eq $simpleName || $strippedKey eq $entity} {
                set children [dict get $hierarchy $key]
                break
            }
        }
    }

    if {[llength $children] > 0} {
        # Has children - make collapsible
        append buf "<li><span class='collapsible has-children' onclick='toggleCollapse(this)'><a href='$slug.$fmt'>$entity</a></span>"
        append buf "<ul class='nested'>"
        foreach child $children {
            append buf [::aurig::doc::_emit_hierarchy_tree_collapsible $child $hierarchy $fmt seen $path]
        }
        append buf "</ul></li>"
    } else {
        # Leaf node
        append buf "<li><a href='$slug.$fmt'>$entity</a></li>"
    }
    return $buf
}

# Helper to emit hierarchy tree recursively
proc ::aurig::doc::_emit_hierarchy_tree {entity hierarchy fmt emitted path} {
    upvar $emitted seen

    # Avoid infinite loops on SAME PATH only
    if {[lsearch -exact $path $entity] >= 0} {
        set simpleName [::aurig::doc::_strip_lib_prefix $entity]
        set slug [::aurig::doc::_slug $simpleName]
        if {$fmt eq "html"} {
            return "<li><a href='$slug.$fmt'>$entity</a> <i>(recursive)</i></li>"
        } else {
            return "- \[$entity\]($slug.$fmt) *(recursive)*\n"
        }
    }

    # Add to current path
    lappend path $entity

    set buf ""
    # Strip library prefix for slug/filename
    set simpleName [::aurig::doc::_strip_lib_prefix $entity]
    set slug [::aurig::doc::_slug $simpleName]

    # Try to find children with multiple key variations
    set children {}
    if {[dict exists $hierarchy $entity]} {
        set children [dict get $hierarchy $entity]
    } elseif {[dict exists $hierarchy $simpleName]} {
        set children [dict get $hierarchy $simpleName]
    } else {
        # Try matching by stripped name against all dict keys
        foreach key [dict keys $hierarchy] {
            set strippedKey [::aurig::doc::_strip_lib_prefix $key]
            if {$strippedKey eq $simpleName || $strippedKey eq $entity} {
                set children [dict get $hierarchy $key]
                break
            }
        }
    }

    if {$fmt eq "html"} {
        append buf "<li><a href='$slug.$fmt'>$entity</a>"
        if {[llength $children] > 0} {
            append buf "<ul>"
            foreach child $children {
                append buf [::aurig::doc::_emit_hierarchy_tree $child $hierarchy $fmt seen $path]
            }
            append buf "</ul>"
        }
        append buf "</li>"
    } else {
        append buf "- \[$entity\]($slug.$fmt)\n"
        if {[llength $children] > 0} {
            foreach child $children {
                set childBuf [::aurig::doc::_emit_hierarchy_tree $child $hierarchy $fmt seen $path]
                # Indent child lines
                foreach line [split $childBuf "\n"] {
                    if {$line ne ""} { append buf "  $line\n" }
                }
            }
        }
    }
    return $buf
}

# Generate footer HTML with logo and timestamp
proc ::aurig::doc::_generate_footer {{includeLogo 0}} {
    set footer "<div class='footer'>"
    if {$includeLogo} {
        append footer "<img src='LM_LOGO-full.png' alt='Logimentor Logo' style='max-width:200px'><br>"
    }
    append footer "Generated by <strong>AURIG Doc</strong> — LogiMentor<br>"
    append footer "<a href='https://www.logimentor.com' target='_blank'>www.logimentor.com</a><br>"
    append footer "on [clock format [clock seconds] -format {%B %d, %Y}]"
    append footer " at [clock format [clock seconds] -format {%H:%M:%S}]</div>"
    return $footer
}

# Generate file list page with filtering capability
proc ::aurig::doc::_emit_file_list {outdir allFiles entityToFile packageToFile sourceViewerMap {includeLogo 0}} {
    set outFile [file join $outdir "files.html"]
    set fp [open $outFile w]
    fconfigure $fp -translation lf -encoding utf-8

    puts $fp "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>File List</title>"
    puts $fp "<style>@import url('https://fonts.googleapis.com/css2?family=Oswald:wght@200..700&display=swap');"
    puts $fp "@import url('https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100..900;1,100..900&display=swap');"
    puts $fp "body{font-family:'Oswald',serif;margin:24px;color:#2f2a25;max-width:1400px}"
    puts $fp "table{border-collapse:collapse;margin:12px 0;width:100%}"
    puts $fp "th,td{border:1px solid #ddd;padding:8px 12px;text-align:left}"
    puts $fp "th{background:#f7f7f7;font-weight:600;cursor:pointer;user-select:none}"
    puts $fp "th:hover{background:#e8e8e8}"
    puts $fp "p,td{font-family:'Roboto',serif;line-height:1.6}"
    puts $fp "a{color:#942c13;text-decoration:none}"
    puts $fp "a:hover{text-decoration:underline}"
    puts $fp ".filter-buttons{margin:20px 0;display:flex;gap:10px;flex-wrap:wrap}"
    puts $fp ".filter-btn{padding:8px 16px;border:2px solid #942c13;background:#fff;color:#942c13;cursor:pointer;font-family:'Oswald',serif;font-weight:500;border-radius:4px;transition:all 0.2s}"
    puts $fp ".filter-btn:hover{background:#f5f5f5}"
    puts $fp ".filter-btn.active{background:#942c13;color:#fff}"
    puts $fp ".hidden{display:none}"
    puts $fp ".footer{margin-top:40px;padding-top:20px;border-top:2px solid #ddd;text-align:center;color:#666;font-size:0.9em}"
    puts $fp ".footer img{max-width:250px;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto}"
    puts $fp ".footer a{color:#942c13;font-weight:500;text-decoration:none}"
    puts $fp ".footer a:hover{text-decoration:underline}"
    puts $fp "</style></head><body>"

    puts $fp "<div style='margin-bottom:20px;padding:10px;background:#f0f0f0;border-radius:4px'>"
    puts $fp "<a href='index.html' style='margin-right:15px'>Home</a>"
    puts $fp "</div>"

    puts $fp "<h1>Project Files</h1>"
    puts $fp "<p>Filter files by type:</p>"
    puts $fp "<div class='filter-buttons'>"
    puts $fp "<button class='filter-btn active' onclick='filterFiles(\"all\")'>All Files</button>"
    puts $fp "<button class='filter-btn' onclick='filterFiles(\"entity\")'>Entities</button>"
    puts $fp "<button class='filter-btn' onclick='filterFiles(\"package\")'>Packages</button>"
    puts $fp "<button class='filter-btn' onclick='filterFiles(\"other\")'>Other</button>"
    puts $fp "</div>"

    puts $fp "<table id='fileTable'><thead><tr><th>File Name</th><th>Type</th><th>Contains</th><th>Library</th><th>Actions</th></tr></thead><tbody>"

    # Process all files
    dict for {filepath fileInfo} $allFiles {
        set fullpath [dict get $fileInfo fullpath]
        set fileName [file tail $fullpath]
        set lib ""
        if {[dict exists $fileInfo lib]} {
            set lib [dict get $fileInfo lib]
        }

        # Determine file type and contents
        set fileType "other"
        set contents ""
        set contentLinks [list]

        # Check if this file contains entities
        set hasEntity 0
        dict for {entity entityFile} $entityToFile {
            if {$entityFile eq $fullpath} {
                set hasEntity 1
                set entitySlug [::aurig::doc::_slug $entity]
                lappend contentLinks "<a href='$entitySlug.html'>$entity</a>"
            }
        }

        # Check if this file contains packages
        set hasPackage 0
        dict for {pkg pkgFile} $packageToFile {
            if {$pkgFile eq $fullpath} {
                set hasPackage 1
                set pkgSlug [::aurig::doc::_slug $pkg]
                lappend contentLinks "<a href='pkg_$pkgSlug.html'>$pkg</a>"
            }
        }

        if {$hasEntity} { set fileType "entity" }
        if {$hasPackage} { set fileType "package" }

        set contents [join $contentLinks ", "]

        # Get source viewer link
        set viewerLink ""
        if {[dict exists $sourceViewerMap $fullpath]} {
            set viewerPage [dict get $sourceViewerMap $fullpath]
            set viewerLink "<a href='$viewerPage'>View Source</a>"
        }

        puts $fp "<tr class='file-row' data-type='$fileType'>"
        puts $fp "<td><strong>$fileName</strong></td>"
        puts $fp "<td>$fileType</td>"
        puts $fp "<td>$contents</td>"
        puts $fp "<td>$lib</td>"
        puts $fp "<td>$viewerLink</td>"
        puts $fp "</tr>"
    }

    puts $fp "</tbody></table>"

    puts $fp [::aurig::doc::_generate_footer $includeLogo]

    puts $fp "<script>"
    puts $fp "function filterFiles(type) {"
    puts $fp "  var rows = document.querySelectorAll('.file-row');"
    puts $fp "  var buttons = document.querySelectorAll('.filter-btn');"
    puts $fp "  buttons.forEach(function(btn) { btn.classList.remove('active'); });"
    puts $fp "  event.target.classList.add('active');"
    puts $fp "  rows.forEach(function(row) {"
    puts $fp "    if (type === 'all' || row.getAttribute('data-type') === type) {"
    puts $fp "      row.style.display = '';"
    puts $fp "    } else {"
    puts $fp "      row.style.display = 'none';"
    puts $fp "    }"
    puts $fp "  });"
    puts $fp "}"
    puts $fp "</script>"
    puts $fp "</body></html>"

    close $fp
}

# Render minimal index page with collapsible hierarchy
proc ::aurig::doc::_emit_index {outdir fmt projectName topEntity hierarchy entities packages {configData {}} {entityToFile {}} {entityToDesc {}} {packageToFile {}} {packageToDesc {}} {includeLogo 0}} {
    set title "${projectName} – Documentation"
    set idx [file join $outdir [expr {$fmt eq "html" ? "index.html" : "index.md"}]]
    if {$fmt eq "html"} {
        set buf "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>$title</title>"
        append buf "<style>"
        append buf "@import url('https://fonts.googleapis.com/css2?family=Oswald:wght@200..700&display=swap');"
        append buf "@import url('https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100..900;1,100..900&display=swap');"
        append buf "body{font-family:'Oswald',serif;margin:24px;max-width:1400px;color:#2f2a25} "
        append buf "table{border-collapse:collapse;margin:12px 0;width:100%} "
        append buf "th,td{border:1px solid #ddd;padding:8px 12px;text-align:left} "
        append buf "th{background:#f7f7f7;font-weight:600;color:#2f2a25} "
        append buf "ul{margin:8px 0 16px;list-style:none} "
        append buf "li{margin:4px 0} "
        append buf "a{text-decoration:none;color:#942c13} "
        append buf "a:hover{text-decoration:underline} "
        append buf "p{font-family:'Roboto',serif;line-height:1.6} "
        append buf ".collapsible{cursor:pointer;user-select:none;font-weight:bold} "
        append buf ".collapsible:before{content:'▶ ';display:inline-block;transition:transform 0.2s} "
        append buf ".collapsible.active:before{transform:rotate(90deg)} "
        append buf ".nested{display:none;padding-left:20px} "
        append buf ".nested.active{display:block} "
        append buf ".has-children{font-weight:500;text-decoration:underline} "
        append buf ".metadata{background:#f9f9f9;padding:16px;margin:16px 0;border-left:4px solid #942c13} "
        append buf ".footer{margin-top:40px;padding-top:20px;border-top:2px solid #ddd;text-align:center;color:#666;font-size:0.9em} "
        append buf ".footer img{max-width:250px;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto} "
        append buf ".footer a{color:#942c13;font-weight:500;text-decoration:none}"
        append buf ".footer a:hover{text-decoration:underline}"
        append buf "</style>"
        append buf "<script>"
        append buf "function toggleCollapse(el){el.classList.toggle('active');var n=el.nextElementSibling;if(n&&n.classList.contains('nested'))n.classList.toggle('active');}"
        append buf "window.addEventListener('DOMContentLoaded',function(){"
        append buf "var hierarchySection=document.querySelector('h2');"
        append buf "if(hierarchySection&&hierarchySection.textContent.includes('Hierarchy')){"
        append buf "var nextUl=hierarchySection.nextElementSibling;"
        append buf "while(nextUl&&nextUl.tagName!=='UL'){nextUl=nextUl.nextElementSibling;}"
        append buf "if(nextUl){"
        append buf "var firstLi=nextUl.querySelector('li>span.collapsible');"
        append buf "if(firstLi){firstLi.click();}"
        append buf "}"
        append buf "}"
        append buf "});"
        append buf "</script>"
        append buf "</head><body>"
        append buf "<h1>$title</h1>"

        # Project metadata section
        if {[dict size $configData] > 0} {
            append buf "<div class='metadata'><h3>Project Information</h3>"
            append buf "<table>"

            # FPGA Device (vendor + family + part)
            if {[dict exists $configData device_vendor] || [dict exists $configData device_family] || [dict exists $configData device_part]} {
                set fpga_display ""
                if {[dict exists $configData device_vendor]} {
                    set fpga_display [string totitle [dict get $configData device_vendor]]
                }
                if {[dict exists $configData device_family]} {
                    if {$fpga_display ne ""} { append fpga_display " " }
                    append fpga_display [string toupper [dict get $configData device_family]]
                }
                if {[dict exists $configData device_part]} {
                    if {$fpga_display ne ""} { append fpga_display " " }
                    append fpga_display [dict get $configData device_part]
                }
                append buf "<tr><td><strong>FPGA Device</strong></td><td>$fpga_display</td></tr>"
            } elseif {[dict exists $configData fpga_device]} {
                set fpga_dev [dict get $configData fpga_device]
                if {[dict exists $configData fpga_family]} {
                    set fpga_fam [dict get $configData fpga_family]
                    append buf "<tr><td><strong>FPGA Device</strong></td><td>$fpga_fam $fpga_dev</td></tr>"
                } else {
                    append buf "<tr><td><strong>FPGA Device</strong></td><td>$fpga_dev</td></tr>"
                }
            } elseif {[dict exists $configData fpga_family]} {
                append buf "<tr><td><strong>FPGA Family</strong></td><td>[dict get $configData fpga_family]</td></tr>"
            }

            # Tool information
            if {[dict exists $configData tool_kind] || [dict exists $configData tool_version]} {
                set tool_display ""
                if {[dict exists $configData tool_kind]} {
                    set tool_display [string totitle [dict get $configData tool_kind]]
                }
                if {[dict exists $configData tool_version]} {
                    if {$tool_display ne ""} {
                        append tool_display " [dict get $configData tool_version]"
                    } else {
                        set tool_display [dict get $configData tool_version]
                    }
                }
                if {$tool_display ne ""} {
                    append buf "<tr><td><strong>Tool</strong></td><td>$tool_display</td></tr>"
                }
            } elseif {[dict exists $configData tool]} {
                # Fallback for simple tool string
                append buf "<tr><td><strong>Tool</strong></td><td>[dict get $configData tool]</td></tr>"
            }

            # Constraint files
            if {[dict exists $configData constraints]} {
                set constraints [dict get $configData constraints]
                if {[llength $constraints] > 0} {
                    append buf "<tr><td><strong>Constraints</strong></td><td>"
                    foreach c $constraints {
                        append buf "<code>[file tail $c]</code><br>"
                    }
                    append buf "</td></tr>"
                }
            }

            # Libraries and source folders from file_sets
            if {[dict exists $configData filesets]} {
                append buf "<tr><td><strong>Libraries & Sources</strong></td><td>"
                append buf "<table style='width:100%;border:none;margin:0'>"
                append buf "<tr style='background:#e8f4f8'><th style='width:25%;text-align:left;border:1px solid #ddd'>Library</th><th style='text-align:left;border:1px solid #ddd'>Source Folders</th></tr>"

                # Parse file_sets structure: {fileset_name: [{lib: ..., src: [...]}, ...]}
                dict for {fileset_name entries} [dict get $configData filesets] {
                    foreach entry $entries {
                        if {[catch {dict get $entry lib} lib] == 0 && [catch {dict get $entry src} src_files] == 0} {
                            # Extract unique directories from source files
                            set dirs [dict create]
                            foreach f $src_files {
                                set dir [file dirname $f]
                                dict set dirs $dir 1
                            }

                            append buf "<tr><td style='border:1px solid #ddd'><strong>$lib</strong></td><td style='border:1px solid #ddd'>"
                            set first 1
                            foreach dir [lsort [dict keys $dirs]] {
                                if {!$first} { append buf "<br>" }
                                set first 0
                                append buf "<code>$dir</code>"
                            }
                            append buf "</td></tr>"
                        }
                    }
                }
                append buf "</table></td></tr>"
            }

            # Top entity
            if {$topEntity ne ""} {
                append buf "<tr><td><strong>Top Entity</strong></td><td><strong>$topEntity</strong></td></tr>"
            }

            append buf "</table></div>"
        } else {
            if {$topEntity ne ""} {
                append buf "<p>Top: <strong>$topEntity</strong></p>"
            }
        }

        append buf "<h2>Hierarchy</h2>"
        append buf "<p><a href='files.html' style='font-size:0.9em'>&rarr; View complete file list</a></p>"
        append buf "<ul>"

        # Emit collapsible tree starting from top entity
        array set emitted {}
        append buf [::aurig::doc::_emit_hierarchy_tree_collapsible $topEntity $hierarchy $fmt emitted [list]]

        # Entities table with source file and description
        append buf "</ul><h2>Entities</h2>"
        append buf "<table><tr><th>Entity Name</th><th>Source File</th><th>Description</th></tr>"

        foreach e $entities {
            set es [::aurig::doc::_slug $e]
            append buf "<tr><td><a href='$es.$fmt'>$e</a></td>"

            # Get source file and description from mappings
            set sourceFile ""
            set description ""
            if {[dict exists $entityToFile $e]} {
                set sourceFile [dict get $entityToFile $e]
            }
            if {[dict exists $entityToDesc $e]} {
                set description [dict get $entityToDesc $e]
            }

            if {$sourceFile ne ""} {
                set file_url "file:///[string map {{ } %20} [string map {\\ /} $sourceFile]]"
                append buf "<td><a href='$file_url' target='_blank'>[file tail $sourceFile]</a></td>"
            } else {
                append buf "<td></td>"
            }

            append buf "<td>$description</td></tr>"
        }
        append buf "</table>"

        # Packages table with source file and description
        append buf "<h2>Packages</h2>"
        append buf "<table><tr><th>Package Name</th><th>Source File</th><th>Description</th></tr>"
        foreach p $packages {
            set ps [::aurig::doc::_slug $p]
            append buf "<tr><td><a href='pkg_$ps.$fmt'>$p</a></td>"

            # Get source file and description from mappings
            set sourceFile ""
            set description ""
            if {[dict exists $packageToFile $p]} {
                set sourceFile [dict get $packageToFile $p]
            }
            if {[dict exists $packageToDesc $p]} {
                set description [dict get $packageToDesc $p]
            }

            if {$sourceFile ne ""} {
                set file_url "file:///[string map {{ } %20} [string map {\\ /} $sourceFile]]"
                append buf "<td><a href='$file_url' target='_blank'>[file tail $sourceFile]</a></td>"
            } else {
                append buf "<td></td>"
            }

            append buf "<td>$description</td></tr>"
        }
        append buf "</table>"

        append buf [::aurig::doc::_generate_footer $includeLogo]

        append buf "</body></html>"
        ::aurig::doc::_write_file $idx $buf
    } else {
        set buf "# $title\n\nTop: **$topEntity**\n\n## Hierarchy\n"

        # Emit tree starting from top entity
        array set emitted {}
        append buf [::aurig::doc::_emit_hierarchy_tree $topEntity $hierarchy $fmt emitted [list]]

        append buf "\n## Entities\n"
        foreach e $entities { set es [::aurig::doc::_slug $e]; append buf "- \[$e\]($es.$fmt)\n" }
        append buf "\n## Packages\n"
        foreach p $packages { set ps [::aurig::doc::_slug $p]; append buf "- \[$p\](pkg_$ps.$fmt)\n" }
        ::aurig::doc::_write_file $idx $buf
    }
}

# Generate VHDL source code viewer page with syntax highlighting
proc ::aurig::doc::_emit_source_viewer {sourceFile outdir {includeLogo 0}} {
    set fileName [file tail $sourceFile]
    set slug [::aurig::doc::_slug $fileName]
    set outFile [file join $outdir "src_${slug}.html"]

    # Read the source file
    if {![file exists $sourceFile]} {
        return ""
    }

    set fp [open $sourceFile r]
    fconfigure $fp -encoding utf-8
    set sourceCode [read $fp]
    close $fp

    # Escape HTML special characters
    set sourceCode [string map {& &amp; < &lt; > &gt; ' &#39;} $sourceCode]
    set sourceCode [string map [list \" &quot;] $sourceCode]

    # Generate HTML with CodeMirror
    set out [open $outFile w]
    fconfigure $out -translation lf -encoding utf-8

    puts $out "<!DOCTYPE html>"
    puts $out "<html><head><meta charset=\"utf-8\"><title>$fileName - Source Code</title>"
    puts $out "<link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.css\">"
    puts $out "<link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/theme/eclipse.min.css\">"
    puts $out "<style>@import url('https://fonts.googleapis.com/css2?family=Oswald:wght@200..700&display=swap');"
    puts $out "body{font-family:'Oswald',serif;margin:0;padding:0;color:#2f2a25;background:#f5f5f5}"
    puts $out ".header{background:#fff;border-bottom:2px solid #942c13;padding:15px 20px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}"
    puts $out ".header h1{margin:0;font-size:1.5em;color:#2f2a25}"
    puts $out ".header .nav{margin-top:10px}"
    puts $out ".header a{color:#942c13;text-decoration:none;margin-right:15px;font-weight:500}"
    puts $out ".header a:hover{text-decoration:underline}"
    puts $out ".code-container{margin:20px;background:#fff;border:1px solid #ddd;border-radius:4px;box-shadow:0 2px 4px rgba(0,0,0,0.05)}"
    puts $out ".CodeMirror{height:auto;min-height:600px;font-size:14px;line-height:1.5}"
    puts $out ".file-info{padding:10px 15px;background:#f9f9f9;border-bottom:1px solid #ddd;font-family:'Roboto',sans-serif;font-size:0.9em;color:#666}"
    puts $out ".footer{margin-top:20px;padding:20px;text-align:center;color:#666;font-size:0.9em;border-top:2px solid #ddd}"
    puts $out ".footer img{max-width:200px;margin-bottom:10px}"
    puts $out ".footer a{color:#942c13;font-weight:500;text-decoration:none}"
    puts $out ".footer a:hover{text-decoration:underline}"
    puts $out "</style>"
    puts $out "</head><body>"
    puts $out "<div class='header'>"
    puts $out "<h1>$fileName</h1>"
    puts $out "<div class='nav'>"
    puts $out "<a href='index.html'>Home</a>"
    puts $out "<a href='javascript:history.back()'>&larr; Back</a>"
    puts $out "</div>"
    puts $out "</div>"
    puts $out "<div class='code-container'>"
    puts $out "<div class='file-info'>File: <code>$sourceFile</code></div>"
    puts $out "<textarea id='code'>$sourceCode</textarea>"
    puts $out "</div>"

    set footer [::aurig::doc::_generate_footer $includeLogo]
    puts $out $footer

    puts $out "<script src=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.js\"></script>"
    puts $out "<script src=\"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/mode/vhdl/vhdl.min.js\"></script>"
    puts $out "<script>"
    puts $out "var editor = CodeMirror.fromTextArea(document.getElementById('code'), {"
    puts $out "  mode: 'vhdl',"
    puts $out "  theme: 'eclipse',"
    puts $out "  lineNumbers: true,"
    puts $out "  readOnly: true,"
    puts $out "  lineWrapping: false,"
    puts $out "  viewportMargin: Infinity"
    puts $out "});"
    puts $out "</script>"
    puts $out "</body></html>"

    close $out
    return "src_${slug}.html"
}

# Emit per-entity page using documenter helpers with navigation
proc ::aurig::doc::_emit_entity_page {parseDict outdir fmt entityName {sourceViewerMap {}} {allHierarchy {}} {reverseHierarchy {}} {includeLogo 0}} {
    set slug [::aurig::doc::_slug $entityName]
    set out [file join $outdir "$slug.$fmt"]
    if {$fmt eq "html"} {
        # Generate the standard HTML doc
        ::aurig::doc::_emit_html_doc $parseDict $out stdout $sourceViewerMap $allHierarchy $reverseHierarchy $entityName

        # Read it back, add navigation and footer, and rewrite
        set fp [open $out r]; fconfigure $fp -encoding utf-8; set content [read $fp]; close $fp

        # Insert navigation after <body> tag
        set nav "<div style='margin-bottom:20px;padding:10px;background:#f0f0f0;border-radius:4px'>"
        append nav "<a href='index.html' style='margin-right:15px'>🏠 Home</a>"
        append nav "</div>"

        set content [string map [list "<body>" "<body>$nav"] $content]

        # Insert footer before </body>
        set footer [::aurig::doc::_generate_footer $includeLogo]
        set content [string map [list "</body>" "$footer</body>"] $content]

        set fp [open $out w]; fconfigure $fp -translation lf -encoding utf-8; puts $fp $content; close $fp
    } else {
        # Generate the standard MD doc, then prepend project navigation.
        ::aurig::doc::_emit_md_doc $parseDict $out stdout
        set fp [open $out r]; fconfigure $fp -encoding utf-8
        set content [read $fp]
        close $fp

        set fp [open $out w]; fconfigure $fp -translation lf -encoding utf-8
        puts $fp "\[\u2190 Home\](index.md)\n"
        puts -nonewline $fp $content
        close $fp
    }
}

# Emit per-package page (basic fields)
proc ::aurig::doc::_emit_package_page {parseDict outdir fmt pkgDict {includeLogo 0}} {
    set pkgName [expr {[dict exists $pkgDict name] ? [dict get $pkgDict name] : "package"}]
    set slug [::aurig::doc::_slug $pkgName]
    set out [file join $outdir "pkg_$slug.$fmt"]
    if {$fmt eq "html"} {
        set fp [open $out w]; fconfigure $fp -translation lf
        puts $fp "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>$pkgName</title><style>@import url('https://fonts.googleapis.com/css2?family=Oswald:wght@200..700&display=swap');@import url('https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100..900;1,100..900&display=swap');body{font-family:'Oswald',serif;margin:24px;color:#2f2a25} table{border-collapse:collapse;margin:12px 0} th,td{border:1px solid #ddd;padding:6px 10px} th{background:#f7f7f7;color:#2f2a25;font-weight:600} p,td{font-family:'Roboto',serif;line-height:1.6} a{color:#942c13;text-decoration:none} a:hover{text-decoration:underline} .footer{margin-top:40px;padding-top:20px;border-top:2px solid #ddd;text-align:center;color:#666;font-size:0.9em} .footer img{max-width:250px;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto} .footer a{color:#942c13;font-weight:500;text-decoration:none} .footer a:hover{text-decoration:underline}</style></head><body>"
        puts $fp "<div style='margin-bottom:20px;padding:10px;background:#f0f0f0;border-radius:4px'><a href='index.html' style='margin-right:15px'>🏠 Home</a></div>"
        puts $fp "<h1>Package: $pkgName</h1>"

        # Add source file link if available
        if {[dict exists $parseDict meta file]} {
            set source_file [dict get $parseDict meta file]
            # Convert to file:// URL and escape spaces
            set file_url "file:///[string map {{ } %20} [string map {\\ /} $source_file]]"
            puts $fp "<p><strong>Source File:</strong> <a href='$file_url' target='_blank'>$source_file</a></p>"
        }

        # Separate functions, procedures from other declarations
        set decls [::aurig::core::analyze::q_pkg_decls $parseDict $pkgDict]
        set functions {}
        set procedures {}
        set otherDecls {}
        foreach d $decls {
            set kind [expr {[dict exists $d kind] ? [dict get $d kind] : ""}]
            if {$kind eq "function"} {
                lappend functions $d
            } elseif {$kind eq "procedure"} {
                lappend procedures $d
            } else {
                lappend otherDecls $d
            }
        }

        # Emit non-function declarations
        if {[llength $otherDecls]} {
            puts $fp "<h2>Declarations</h2><table><tr><th>Kind</th><th>Name</th><th>Type</th><th>Init</th><th>Comment</th></tr>"
            foreach d $otherDecls {
                set kind [expr {[dict exists $d kind] ? [dict get $d kind] : ""}]
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set type [expr {[dict exists $d type] ? [dict get $d type] : ""}]
                set init [expr {[dict exists $d init] ? [dict get $d init] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                puts $fp "<tr><td>$kind</td><td>$name</td><td>$type</td><td>$init</td><td>$comment</td></tr>"
            }
            puts $fp "</table>"
        }

        # Emit functions in separate table
        if {[llength $functions]} {
            puts $fp "<h2>Functions</h2><table><tr><th>Name</th><th>Parameters</th><th>Return</th><th>Comment</th></tr>"
            foreach d $functions {
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                set returnType [expr {[dict exists $d return] ? [dict get $d return] : ""}]
                set params [expr {[dict exists $d params] ? [dict get $d params] : ""}]

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

                puts $fp "<tr><td>$name</td><td>$formattedParams</td><td>$returnType</td><td>$comment</td></tr>"
            }
            puts $fp "</table>"
        }

        # Emit procedures in separate table
        if {[llength $procedures]} {
            puts $fp "<h2>Procedures</h2><table><tr><th>Name</th><th>Parameters</th><th>Comment</th></tr>"
            foreach d $procedures {
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                set params [expr {[dict exists $d params] ? [dict get $d params] : ""}]

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

                puts $fp "<tr><td>$name</td><td>$formattedParams</td><td>$comment</td></tr>"
            }
            puts $fp "</table>"
        }

        # Add footer
        puts $fp [::aurig::doc::_generate_footer $includeLogo]

        puts $fp "</body></html>"; close $fp
    } else {
        set fp [open $out w]; fconfigure $fp -translation lf
        puts $fp "# Package: $pkgName\n"

        # Separate functions, procedures from other declarations
        set decls [::aurig::core::analyze::q_pkg_decls $parseDict $pkgDict]
        set functions {}
        set procedures {}
        set otherDecls {}
        foreach d $decls {
            set kind [expr {[dict exists $d kind] ? [dict get $d kind] : ""}]
            if {$kind eq "function"} {
                lappend functions $d
            } elseif {$kind eq "procedure"} {
                lappend procedures $d
            } else {
                lappend otherDecls $d
            }
        }

        # Emit non-function declarations
        if {[llength $otherDecls]} {
            puts $fp "\n## Declarations\n| Kind | Name | Type | Init | Comment |\n|---|---|---|---|---|"
            foreach d $otherDecls {
                set kind [expr {[dict exists $d kind] ? [dict get $d kind] : ""}]
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set type [expr {[dict exists $d type] ? [dict get $d type] : ""}]
                set init [expr {[dict exists $d init] ? [dict get $d init] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                puts $fp "| $kind | $name | $type | $init | $comment |"
            }
        }

        # Emit functions in separate table
        if {[llength $functions]} {
            puts $fp "\n## Functions\n| Name | Parameters | Return | Comment |\n|---|---|---|---|"
            foreach d $functions {
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                set returnType [expr {[dict exists $d return] ? [dict get $d return] : ""}]
                set params [expr {[dict exists $d params] ? [dict get $d params] : ""}]

                puts $fp "| $name | $params | $returnType | $comment |"
            }
        }

        # Emit procedures in separate table
        if {[llength $procedures]} {
            puts $fp "\n## Procedures\n| Name | Parameters | Comment |\n|---|---|---|"
            foreach d $procedures {
                set name [expr {[dict exists $d name] ? [dict get $d name] : ""}]
                set comment [expr {[dict exists $d comment] ? [dict get $d comment] : ""}]
                set params [expr {[dict exists $d params] ? [dict get $d params] : ""}]

                puts $fp "| $name | $params | $comment |"
            }
        }

        close $fp
    }
}

# Build a simple hierarchy map: parent -> unique children labels/entities
proc ::aurig::doc::_build_hierarchy {parseDict} {
    set H {}
    foreach arch [::aurig::core::analyze::q_architectures $parseDict] {
        set parent [expr {[dict exists $arch entity] ? [dict get $arch entity] : ""}]
        if {$parent eq ""} continue
        set insts [::aurig::core::analyze::q_arch_instantiations $parseDict $arch]
        set children {}
        foreach inst $insts {
            set child ""
            # Check entity field first, then component field
            if {[dict exists $inst entity]} {
                set ent [dict get $inst entity]
                if {$ent ne ""} {
                    set child $ent
                }
            }
            if {$child eq "" && [dict exists $inst component]} {
                set comp [dict get $inst component]
                if {$comp ne ""} {
                    set child $comp
                }
            }
            if {$child ne "" && [lsearch -exact $children $child] < 0} { lappend children $child }
        }
        dict set H $parent $children
    }
    return $H
}

# Build reverse hierarchy map: child -> list of parents that instantiate it
proc ::aurig::doc::_build_reverse_hierarchy {hierarchyMap} {
    set reverseH [dict create]
    dict for {parent children} $hierarchyMap {
        foreach child $children {
            if {![dict exists $reverseH $child]} {
                dict set reverseH $child [list]
            }
            set parentList [dict get $reverseH $child]
            if {[lsearch -exact $parentList $parent] < 0} {
                lappend parentList $parent
                dict set reverseH $child $parentList
            }
        }
    }
    return $reverseH
}

# Project-mode tcllib `yaml` pre-flight. Mirrors core's
# ::aurig::core::schema::require_libs and aurig-lint's runner package check.
#
# Project-mode manifest reads MUST go through tcllib's `yaml`: the only
# alternative core offers is ::aurig::core::util::readYamlMinimal, a lite subset
# parser that silently mis-parses the multi-key YAML list items canonical
# manifests use under file_sets/ip_cores. readYaml (the manifest entry at the
# YAML branch below) silently falls back to that lite parser when `yaml` is
# absent, so without this gate doc would proceed on a mis-parsed manifest:
#   - no-top mode throws late from collect_project_files, but only AFTER the
#     manifest was already mis-read by readYamlMinimal; and
#   - top-present mode catches collect_project_files's throw and falls back to
#     hand-parsing file_sets from the mis-parsed `Y`, masking the absence and
#     emitting a misleading "cannot locate top-level" error instead of loud
#     install guidance.
# Gating here -- BEFORE the first manifest readYaml -- closes all three sites in
# one place: readYaml, collect_project_files, and the file_sets fallback are all
# downstream of this point and unreachable once it fires.
#
# doc HARD-REQUIRES tcllib for project mode (consistent with core and lint);
# there is intentionally NO degraded-reader opt-in. aurig-lint exposes an
# explicit -allow_degraded_yaml_reader flag because it has a demand for one;
# doc does not, and adding one unbidden would reintroduce exactly the silent
# mis-parse class this gate removes.
proc ::aurig::doc::_require_project_yaml_lib {} {
    if {![catch {package require yaml}]} { return }
    error [join [list \
        "project_documenter: project-mode YAML manifest loading requires the tcllib `yaml` package, which was not found on the Tcl auto_path." \
        "This is MANDATORY for project manifests and has no safe fallback: file_sets/ip_cores use multi-key YAML list items that ::aurig::core::util::readYamlMinimal cannot parse, so falling back to it would silently mis-read the manifest." \
        "Install tcllib and ensure it is on the Tcl auto_path, e.g.:" \
        "  Debian/Ubuntu : sudo apt-get install tcllib" \
        "  ActiveTcl     : teacup install tcllib" \
        "  from source   : add the tcllib directory to \$auto_path." \
        "On Windows with multiple tclsh.exe on PATH, verify the one being invoked has tcllib reachable: `echo puts \[package require yaml\] | tclsh`." ] "\n"]
}

# Main entry: generate project documentation
proc ::aurig::doc::project_documenter {args} {
    set config ""; set outdir "docs"; set fmt "html"; set verbosity 0
    # Accept either -config <yaml> or -ini <ini>
    foreach {switch value} $args {
        switch -- $switch {
            -config { set config $value }
            -ini    { set config $value }
            -outdir { set outdir $value }
            -format { set fmt [string tolower $value] }
            -verbosity { set verbosity $value }
            -help {
                puts "Usage: ::aurig::doc::project_documenter -config <project.yaml>|-ini <project.ini> -outdir <dir> -format html|md"; return
            }
            default { puts stderr "Unknown switch: $switch" }
        }
    }
    if {$config eq ""} { error "project_documenter: missing -config/-ini" }
    if {$fmt ni {html md}} { error "project_documenter: -format must be html or md" }

    # Determine the config format up front. For project-mode YAML the tcllib
    # `yaml` pre-flight MUST run BEFORE any filesystem side effect (outdir
    # creation, logo emission), so a tcllib-absent loud failure is
    # side-effect-free: no half-created outdir, no stray LM_LOGO-full.png. This
    # is the first project-mode-YAML action.
    set ext [string tolower [file extension $config]]
    set cfgFormat [expr {$ext in {.yaml .yml} ? "yaml" : "ini"}]
    if {$ext in {.yaml .yml}} {
        ::aurig::doc::_require_project_yaml_lib
    }

    ::aurig::doc::_ensure_dir $outdir
    set includeLogo [::aurig::doc::_emit_project_documenter_logo $outdir]

    # Load config (YAML or INI)
    set configDir [file dirname [file normalize $config]]
    set configData [dict create]

    if {$ext in {.yaml .yml}} {
        # tcllib `yaml` was pre-flighted above (before any side effect), so
        # readYaml never silently degrades to readYamlMinimal here. That gate
        # closes the readYaml / collect_project_files / file_sets-fallback sites
        # under tcllib-absence in one place.
        set Y [::aurig::core::util::readYaml $config]
        set top [expr {[dict exists $Y top] ? [dict get $Y top] : ""}]
        set projectName [expr {[dict exists $Y project_name] ? [dict get $Y project_name] : [file rootname [file tail $config]]}]
        set projectRoot [expr {[dict exists $Y project_root] ? [dict get $Y project_root] : ""}]
        set libs [expr {[dict exists $Y external_libraries] ? [dict get $Y external_libraries] \
                      : ([dict exists $Y libraries] ? [dict get $Y libraries] : {})}]

        # Extract additional metadata for documentation

        # Extract device info from device section
        if {[dict exists $Y device]} {
            set device_dict [dict get $Y device]
            if {[catch {dict get $device_dict vendor} vendor] == 0} {
                dict set configData device_vendor $vendor
            }
            if {[catch {dict get $device_dict family} family] == 0} {
                dict set configData device_family $family
            }
            if {[catch {dict get $device_dict part} part] == 0} {
                dict set configData device_part $part
            }
        }

        # Fallback to old fpga_device/fpga_family if present
        if {[dict exists $Y fpga_device]} { dict set configData fpga_device [dict get $Y fpga_device] }
        if {[dict exists $Y fpga_family]} { dict set configData fpga_family [dict get $Y fpga_family] }

        # Extract tool info - handle nested dict structure (e.g., tool: {synth: {kind: quartus, version: 24.1}})
        if {[dict exists $Y tool]} {
            set tool_dict [dict get $Y tool]
            # Check if it's a nested dict with synth/sim keys
            if {[catch {dict get $tool_dict synth} synth_info] == 0} {
                # Extract synth tool info
                if {[catch {dict get $synth_info kind} tool_kind] == 0} {
                    dict set configData tool_kind $tool_kind
                }
                if {[catch {dict get $synth_info version} tool_ver] == 0} {
                    dict set configData tool_version $tool_ver
                }
            } else {
                # Simple tool string
                dict set configData tool $tool_dict
            }
        }
        if {[dict exists $Y tool_version]} { dict set configData tool_version [dict get $Y tool_version] }

        # Extract constraints from board section
        set constraints [list]
        if {[dict exists $Y board]} {
            set board_dict [dict get $Y board]
            if {[catch {dict get $board_dict sdc_files} sdc_files] == 0} {
                foreach sdc $sdc_files {
                    lappend constraints $sdc
                }
            }
            if {[catch {dict get $board_dict xdc_files} xdc_files] == 0} {
                foreach xdc $xdc_files {
                    lappend constraints $xdc
                }
            }
        }

        # Extract additional constraints from quartus section
        if {[dict exists $Y quartus]} {
            set quartus_dict [dict get $Y quartus]
            if {[catch {dict get $quartus_dict qsf_extra_files} qsf_files] == 0} {
                foreach qsf $qsf_files {
                    lappend constraints $qsf
                }
            }
        }

        if {[llength $constraints] > 0} {
            dict set configData constraints $constraints
        }

        if {[dict exists $Y file_sets]} {
            set filesets [dict create]
            dict for {lib files} [dict get $Y file_sets] {
                dict set filesets $lib $files
            }
            dict set configData filesets $filesets
        }
    } else {
        set INI [::aurig::core::util::readIni $config]
        set top [expr {[dict exists $INI config top_level] ? [dict get $INI config top_level] : ""}]
        set projectName [expr {[dict exists $INI config project] ? [dict get $INI config project] : [file rootname [file tail $config]]}]
        set projectRoot [expr {[dict exists $INI config workdir] ? [dict get $INI config workdir] : ""}]
        set libs [expr {[dict exists $INI external_libraries] ? [dict get $INI external_libraries] \
                      : ([dict exists $INI libraries] ? [dict get $INI libraries] : {})}]

        # Extract additional metadata for documentation
        if {[dict exists $INI config fpga_device]} { dict set configData fpga_device [dict get $INI config fpga_device] }
        if {[dict exists $INI config fpga_family]} { dict set configData fpga_family [dict get $INI config fpga_family] }
        if {[dict exists $INI config tool]} { dict set configData tool [dict get $INI config tool] }
        if {[dict exists $INI config tool_version]} { dict set configData tool_version [dict get $INI config tool_version] }
    }

    # Make project_root absolute if it's relative (relative to config file location)
    if {$projectRoot ne "" && [file pathtype $projectRoot] ne "absolute"} {
        set projectRoot [file normalize [file join $configDir $projectRoot]]
    }

    # If no top specified, scan all files from file_sets
    if {$top eq ""} {
        if {$verbosity > 0} { puts "No top-level specified, scanning all files from file_sets..." }

        # Collect all files from project
        set allFiles [::aurig::core::util::collect_project_files -from $config -format $cfgFormat]

        # Aggregate all entities and packages across all files
        set allEntities {}
        set allPackages {}
        set allHierarchy {}
        set allParseDicts {}

        # Build entity/package to source file mappings
        set entityToFile [dict create]
        set entityToDesc [dict create]
        set packageToFile [dict create]
        set packageToDesc [dict create]

        set fileCount 0
        dict for {filekey fileinfo} $allFiles {
            if {[dict get $fileinfo type] ne "vhdl"} continue

            set filepath [dict get $fileinfo fullpath]
            incr fileCount
            if {$verbosity > 1} { puts "  Parsing: [file tail $filepath]" }

            if {[catch {
                set parseDict [::aurig::core::analyze::vhdlscan -in $filepath -verbosity 0]
                dict set allParseDicts $filepath $parseDict

                # Get file-level description if available
                set fileDesc ""
                if {[dict exists $parseDict metadata description]} {
                    set fileDesc [dict get $parseDict metadata description]
                }

                # Collect entities
                set entities [::aurig::core::analyze::q_entity_names $parseDict]
                foreach e $entities {
                    # Store entity → file mapping
                    dict set entityToFile $e $filepath
                    if {$fileDesc ne ""} {
                        dict set entityToDesc $e $fileDesc
                    }

                    if {[lsearch -exact $allEntities $e] < 0} {
                        lappend allEntities $e
                        # Defer page emission until after source viewers are created
                    }
                }

                # Collect packages
                foreach p [::aurig::core::analyze::q_packages $parseDict] {
                    if {[dict exists $p name]} {
                        set pname [dict get $p name]

                        # Store package → file mapping
                        dict set packageToFile $pname $filepath
                        if {$fileDesc ne ""} {
                            dict set packageToDesc $pname $fileDesc
                        }

                        if {[lsearch -exact $allPackages $pname] < 0} {
                            lappend allPackages $pname
                            # Defer page emission until after source viewers are created
                        }
                    }
                }

                # Build hierarchy
                set H [::aurig::doc::_build_hierarchy $parseDict]
                dict for {parent children} $H {
                    if {![dict exists $allHierarchy $parent]} {
                        dict set allHierarchy $parent $children
                    } else {
                        # Merge children
                        set existing [dict get $allHierarchy $parent]
                        foreach c $children {
                            if {[lsearch -exact $existing $c] < 0} {
                                lappend existing $c
                            }
                        }
                        dict set allHierarchy $parent $existing
                    }
                }
            } err]} {
                if {$verbosity > 0} { puts "  WARNING: Failed to parse $filepath: $err" }
            }
        }

        if {$verbosity > 0} {
            puts "Processed $fileCount VHDL files"
            puts "Found [llength $allEntities] entities, [llength $allPackages] packages"
        }

        # Generate source code viewer pages for all parsed files
        if {$verbosity > 0} { puts "Generating source code viewer pages..." }
        set sourceViewerMap [dict create]
        dict for {filepath fileinfo} $allFiles {
            if {[dict get $fileinfo type] ne "vhdl"} continue
            set fullpath [dict get $fileinfo fullpath]
            if {$verbosity > 1} { puts "  Creating viewer for: [file tail $fullpath]" }
            set viewerPage [::aurig::doc::_emit_source_viewer $fullpath $outdir $includeLogo]
            if {$viewerPage ne ""} {
                dict set sourceViewerMap $fullpath $viewerPage
            }
        }
        if {$verbosity > 0} { puts "Generated [dict size $sourceViewerMap] source viewer pages" }

        # Build reverse hierarchy for "who uses this entity" display
        set reverseHierarchy [::aurig::doc::_build_reverse_hierarchy $allHierarchy]

        # Now emit entity and package pages with source viewer links
        if {$verbosity > 0} { puts "Generating entity and package documentation pages..." }
        dict for {filepath parseDict} $allParseDicts {
            foreach e [::aurig::core::analyze::q_entity_names $parseDict] {
                if {[lsearch -exact $allEntities $e] >= 0} {
                    ::aurig::doc::_emit_entity_page $parseDict $outdir $fmt $e $sourceViewerMap $allHierarchy $reverseHierarchy $includeLogo
                }
            }
            foreach p [::aurig::core::analyze::q_packages $parseDict] {
                if {[dict exists $p name]} {
                    set pname [dict get $p name]
                    if {[lsearch -exact $allPackages $pname] >= 0} {
                        ::aurig::doc::_emit_package_page $parseDict $outdir $fmt $p $includeLogo
                    }
                }
            }
        }

        # Collect missing entities for report
        set missingEntities [list]
        dict for {parent children} $allHierarchy {
            foreach child $children {
                # Check if this child entity was documented
                if {[lsearch -exact $allEntities $child] < 0} {
                    # Try stripping library prefix for checking
                    set simpleName $child
                    if {[string match "*.*" $child]} {
                        set simpleName [lindex [split $child "."] end]
                    }
                    if {[lsearch -exact $allEntities $simpleName] < 0} {
                        lappend missingEntities $child
                    }
                }
            }
        }
        set missingEntities [lsort -unique $missingEntities]

        # Emit index with all entities and packages
        set topEntity [expr {[llength $allEntities] > 0 ? [lindex $allEntities 0] : ""}]
        ::aurig::doc::_emit_index $outdir $fmt $projectName $topEntity $allHierarchy $allEntities $allPackages $configData $entityToFile $entityToDesc $packageToFile $packageToDesc $includeLogo

        # Generate file list page
        ::aurig::doc::_emit_file_list $outdir $allFiles $entityToFile $packageToFile $sourceViewerMap $includeLogo

        # Generate text report (flat scan mode)
        set reportFile [file join $outdir "documentation_report.txt"]
        set fp [open $reportFile w]
        fconfigure $fp -translation lf

        puts $fp "================================================================"
        puts $fp "  DOCUMENTATION GENERATION REPORT (Flat Scan Mode)"
        puts $fp "================================================================"
        puts $fp "Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
        puts $fp "Project: $projectName"
        puts $fp "Mode: All files scanned (no top entity specified)"
        puts $fp ""

        puts $fp "----------------------------------------------------------------"
        puts $fp "  FILES ANALYZED"
        puts $fp "----------------------------------------------------------------"
        puts $fp "Total VHDL files scanned: $fileCount"
        puts $fp ""

        puts $fp "----------------------------------------------------------------"
        puts $fp "  ENTITIES DOCUMENTED"
        puts $fp "----------------------------------------------------------------"
        puts $fp "Total entities: [llength $allEntities]"
        puts $fp ""
        foreach e [lsort $allEntities] {
            set srcFile "unknown"
            if {[dict exists $entityToFile $e]} {
                set srcFile [file tail [dict get $entityToFile $e]]
            }
            puts $fp "  - $e (from $srcFile)"
        }
        puts $fp ""

        puts $fp "----------------------------------------------------------------"
        puts $fp "  PACKAGES DOCUMENTED"
        puts $fp "----------------------------------------------------------------"
        puts $fp "Total packages: [llength $allPackages]"
        puts $fp ""
        foreach p [lsort $allPackages] {
            set srcFile "unknown"
            if {[dict exists $packageToFile $p]} {
                set srcFile [file tail [dict get $packageToFile $p]]
            }
            puts $fp "  - $p (from $srcFile)"
        }
        puts $fp ""

        if {[llength $missingEntities] > 0} {
            puts $fp "----------------------------------------------------------------"
            puts $fp "  MISSING ENTITIES (Instantiated but not documented)"
            puts $fp "----------------------------------------------------------------"
            puts $fp "Total missing: [llength $missingEntities]"
            puts $fp ""
            puts $fp "The following entities are instantiated in the design hierarchy"
            puts $fp "but were not found in the specified file_sets:"
            puts $fp ""
            foreach e [lsort $missingEntities] {
                puts $fp "  - $e"
            }
            puts $fp ""
        }

        puts $fp "----------------------------------------------------------------"
        puts $fp "  SUMMARY"
        puts $fp "----------------------------------------------------------------"
        puts $fp "Files analyzed:        $fileCount"
        puts $fp "Entities documented:   [llength $allEntities]"
        puts $fp "Packages documented:   [llength $allPackages]"
        puts $fp "Missing entities:      [llength $missingEntities]"
        puts $fp ""
        puts $fp "Documentation output:  $outdir"
        puts $fp "Index page:            [file join $outdir index.$fmt]"
        puts $fp "This report:           $reportFile"
        puts $fp "================================================================"

        close $fp

        if {$verbosity > 0} {
            puts "project_documenter: wrote docs to $outdir (format=$fmt)"
            puts "project_documenter: wrote report to $reportFile"
            if {[llength $missingEntities] > 0} {
                puts "  WARNING: [llength $missingEntities] entities instantiated but not documented (see report)"
            }
        }
        return $outdir
    }

    # Original single-file mode: top-level specified
    # Collect all files from the project manifest. This runs BEFORE top
    # resolution: entity-name mode resolves the top entity against this
    # list, then the recursive scan reuses it.
    if {$verbosity > 1} { puts "Collecting project files for recursive scan..." }

    if {[catch {
        set allFiles [::aurig::core::util::collect_project_files -from $config -format $cfgFormat]
    } err errOpts]} {
        if {$verbosity > 0} {
            puts "ERROR: Failed to collect project files: $err"
            puts "ErrorInfo: [dict get $errOpts -errorinfo]"
        }
        set allFiles [dict create]
    }

    if {$verbosity > 2} {
        puts "  collect_project_files returned [dict size $allFiles] entries"
        if {[dict size $allFiles] > 0} {
            puts "  Sample entries:"
            set count 0
            dict for {k v} $allFiles {
                if {$count < 3} {
                    puts "    $k: [dict get $v fullpath]"
                    incr count
                }
            }
        }
    }

    # Fallback: if collect_project_files returned nothing, manually parse file_sets
    # (YAML only: $Y is set exclusively by the YAML branch above, and INI
    # manifests have no file_sets section to parse)
    if {[dict size $allFiles] == 0 && $cfgFormat eq "yaml"} {
        if {$verbosity > 1} { puts "  Fallback: manually parsing file_sets from YAML..." }

        if {[dict exists $Y file_sets]} {
            set idx 0
            dict for {fsName entries} [dict get $Y file_sets] {
                foreach entry $entries {
                    set lib [dict get $entry lib]
                    set srcGlobs [expr {[dict exists $entry src] ? [dict get $entry src] : {}}]

                    foreach g $srcGlobs {
                        set gabs $g
                        if {[file pathtype $gabs] ne "absolute"} {
                            set gabs [file normalize [file join $projectRoot $g]]
                        }

                        foreach f [glob -nocomplain $gabs] {
                            set full [file normalize $f]
                            set ext  [string tolower [file extension $full]]
                            set type [expr {$ext in {.vhd .vhdl} ? "vhdl" : "other"}]

                            set rec [dict create \
                                name [file tail $full] \
                                ext  $ext \
                                type $type \
                                lib      $lib \
                                fullpath $full]

                            dict set allFiles f$idx $rec
                            incr idx

                            if {$verbosity > 2} { puts "    Added: $full (lib=$lib)" }
                        }
                    }
                }
            }
            if {$verbosity > 1} { puts "  Manually collected [dict size $allFiles] files" }
        }
    }

    # Build a map: entity_name -> file_path AND collect all package files
    set entityFileMap [dict create]
    set packageFiles [list]
    set fileCount 0
    dict for {filekey fileinfo} $allFiles {
        if {[dict get $fileinfo type] ne "vhdl"} continue
        set filepath [dict get $fileinfo fullpath]
        incr fileCount

        if {$verbosity > 2} { puts "  Scanning for entities: [file tail $filepath]" }

        # Quick scan to get entity names and check for packages
        if {[catch {
            set pd [::aurig::core::analyze::vhdlscan -in $filepath -verbosity 0]
            foreach ename [::aurig::core::analyze::q_entity_names $pd] {
                # Store the file path for this entity (allow library-qualified names)
                dict set entityFileMap $ename $filepath
                if {$verbosity > 2} { puts "    Found entity: $ename -> [file tail $filepath]" }

                # Also store with library prefix if available
                if {[dict exists $fileinfo lib]} {
                    set lib [dict get $fileinfo lib]
                    dict set entityFileMap "${lib}.${ename}" $filepath
                    if {$verbosity > 2} { puts "    Also mapped: ${lib}.${ename}" }
                }
            }

            # Check if this file has packages
            set pkgs [::aurig::core::analyze::q_packages $pd]
            if {[llength $pkgs] > 0 && [lsearch -exact $packageFiles $filepath] < 0} {
                lappend packageFiles $filepath
                if {$verbosity > 2} { puts "    Contains [llength $pkgs] package(s)" }
            }
        } err]} {
            if {$verbosity > 0} { puts "  WARNING: Could not scan $filepath: $err" }
        }
    }

    if {$verbosity > 1} {
        puts "Built entity map from $fileCount VHDL files, [dict size $entityFileMap] entity mappings"
        puts "Found [llength $packageFiles] files containing packages"
    }

    if {$verbosity > 2} {
        puts "  Entity map contents:"
        dict for {ent path} $entityFileMap {
            puts "    $ent -> [file tail $path]"
        }
    }

    # Resolve top source path if relative
    set topPath $top
    set found 0

    # Determine if 'top' is a file path (contains / or \) or just an entity name
    set isFilePath [expr {[string match "*/*" $top] || [string match "*\\*" $top]}]

    # If it's a file path, check with and without common extensions
    if {$isFilePath} {
        # Check if already has extension
        set hasExt [expr {[string match "*.vhd" $top] || [string match "*.vhdl" $top]}]
        set extensions [expr {$hasExt ? [list ""] : [list "" ".vhd" ".vhdl"]}]

        foreach ext $extensions {
            set tryPath "${top}${ext}"
            # Try as-is (relative to current directory or absolute)
            if {[file exists $tryPath]} {
                set topPath $tryPath
                set found 1
                break
            }
            # Try relative to project_root
            if {$projectRoot ne ""} {
                set candidate [file join $projectRoot $tryPath]
                if {[file exists $candidate]} {
                    set topPath $candidate
                    set found 1
                    if {$verbosity > 1} { puts "  Found top-level file: $candidate" }
                    break
                }
            }
        }
    } else {
        # Entity name mode: resolve against the manifest-driven entity map
        # first, with the same three-tier matching used for child entities
        # during the recursive scan: exact, lib-stripped, case-insensitive.
        if {[dict exists $entityFileMap $top]} {
            set topPath [dict get $entityFileMap $top]
            set found 1
            if {$verbosity > 1} { puts "  Found top-level file via entity map: $topPath" }
        } else {
            set simpleName $top
            if {[string match "*.*" $top]} {
                set simpleName [lindex [split $top "."] end]
                if {[dict exists $entityFileMap $simpleName]} {
                    set topPath [dict get $entityFileMap $simpleName]
                    set found 1
                    if {$verbosity > 1} { puts "  Found top-level file via entity map ($simpleName): $topPath" }
                }
            }
            if {!$found} {
                foreach key [dict keys $entityFileMap] {
                    if {[string equal -nocase $key $top] || [string equal -nocase $key $simpleName]} {
                        set topPath [dict get $entityFileMap $key]
                        set found 1
                        if {$verbosity > 1} { puts "  Found top-level file via entity map ($key): $topPath" }
                        break
                    }
                }
            }
        }

        # Filesystem fallback: probe for a file named after the entity.
        set extensions [list "" ".vhd" ".vhdl"]

        # Try in project root
        if {!$found} {
            foreach ext $extensions {
                set tryPath "${top}${ext}"
                if {[file exists $tryPath]} {
                    set topPath $tryPath
                    set found 1
                    break
                }
                # Try relative to project_root
                if {$projectRoot ne ""} {
                    set candidate [file join $projectRoot $tryPath]
                    if {[file exists $candidate]} {
                        set topPath $candidate
                        set found 1
                        if {$verbosity > 1} { puts "  Found top-level file: $candidate" }
                        break
                    }
                }
            }
        }

        # If not found, try in libraries
        if {!$found && $libs ne ""} {
            foreach lib [dict keys $libs] {
                set libroot [dict get $libs $lib]
                if {$projectRoot ne "" && [file pathtype $libroot] ne "absolute"} {
                    set libroot [file join $projectRoot $libroot]
                }
                foreach ext $extensions {
                    set candidate [file join $libroot "${top}${ext}"]
                    if {[file exists $candidate]} {
                        set topPath $candidate
                        set found 1
                        if {$verbosity > 1} { puts "  Found top-level file in library '$lib': $candidate" }
                        break
                    }
                }
                if {$found} break
            }
        }
    }

    if {!$found} {
        if {$isFilePath} {
            error "project_documenter: cannot locate top-level file '$top' (tried relative to current dir and project_root)"
        } else {
            error "project_documenter: cannot locate top-level file matching entity '$top' (tried .vhd, .vhdl extensions in project_root and libraries)"
        }
    }

    # Parse starting from top and recursively scan instantiated entities
    set allParseDicts [dict create]
    set allEntities [list]
    set allPackages [list]
    set allHierarchy [dict create]
    set toScan [list $topPath]
    set scanned [dict create]

    # Build entity/package to source file mappings
    set entityToFile [dict create]
    set entityToDesc [dict create]
    set packageToFile [dict create]
    set packageToDesc [dict create]

    # Also queue all package files for scanning
    foreach pkgFile $packageFiles {
        if {[lsearch -exact $toScan $pkgFile] < 0} {
            lappend toScan $pkgFile
            if {$verbosity > 2} { puts "  Queued package file: [file tail $pkgFile]" }
        }
    }

    while {[llength $toScan] > 0} {
        set filepath [lindex $toScan 0]
        set toScan [lrange $toScan 1 end]

        # Skip if already scanned
        if {[dict exists $scanned $filepath]} continue
        dict set scanned $filepath 1

        if {$verbosity > 1} { puts "  Parsing: [file tail $filepath]" }

        if {[catch {
            set parseDict [::aurig::core::analyze::vhdlscan -in $filepath -verbosity 0]
            dict set allParseDicts $filepath $parseDict

            # Get file-level description if available
            set fileDesc ""
            if {[dict exists $parseDict metadata description]} {
                set fileDesc [dict get $parseDict metadata description]
            }

            # Collect entities
            foreach e [::aurig::core::analyze::q_entity_names $parseDict] {
                # Store entity → file mapping
                dict set entityToFile $e $filepath
                if {$fileDesc ne ""} {
                    dict set entityToDesc $e $fileDesc
                }

                if {[lsearch -exact $allEntities $e] < 0} {
                    lappend allEntities $e
                    # Defer page emission until after source viewers are created
                }
            }

            # Collect packages
            foreach p [::aurig::core::analyze::q_packages $parseDict] {
                if {[dict exists $p name]} {
                    set pname [dict get $p name]

                    # Store package → file mapping
                    dict set packageToFile $pname $filepath
                    if {$fileDesc ne ""} {
                        dict set packageToDesc $pname $fileDesc
                    }

                    if {[lsearch -exact $allPackages $pname] < 0} {
                        lappend allPackages $pname
                        # Defer page emission until after source viewers are created
                    }
                }
            }

            # Build hierarchy and find new entities to scan
            set H [::aurig::doc::_build_hierarchy $parseDict]
            dict for {parent children} $H {
                if {$verbosity > 2} { puts "    Hierarchy: $parent -> [join $children {, }]" }

                if {![dict exists $allHierarchy $parent]} {
                    dict set allHierarchy $parent $children
                } else {
                    # Merge children
                    set existing [dict get $allHierarchy $parent]
                    foreach c $children {
                        if {[lsearch -exact $existing $c] < 0} {
                            lappend existing $c
                        }
                    }
                    dict set allHierarchy $parent $existing
                }

                # Queue children for scanning
                foreach child $children {
                    # Try to find the file for this child entity
                    set childFile ""

                    if {$verbosity > 2} { puts "    Looking for child entity: $child" }

                    # Try exact match first
                    if {[dict exists $entityFileMap $child]} {
                        set childFile [dict get $entityFileMap $child]
                        if {$verbosity > 2} { puts "      Found via exact match: [file tail $childFile]" }
                    } else {
                        # Try stripping library prefix (e.g., "ces_io_lib.ces_io_uart_rx" -> "ces_io_uart_rx")
                        set simpleName $child
                        if {[string match "*.*" $child]} {
                            set simpleName [lindex [split $child "."] end]
                            if {[dict exists $entityFileMap $simpleName]} {
                                set childFile [dict get $entityFileMap $simpleName]
                                if {$verbosity > 2} { puts "      Found via simple name ($simpleName): [file tail $childFile]" }
                            }
                        }

                        # Try case-insensitive match if still not found
                        if {$childFile eq ""} {
                            foreach key [dict keys $entityFileMap] {
                                if {[string equal -nocase $key $child] || [string equal -nocase $key $simpleName]} {
                                    set childFile [dict get $entityFileMap $key]
                                    if {$verbosity > 2} { puts "      Found via case-insensitive match ($key): [file tail $childFile]" }
                                    break
                                }
                            }
                        }
                    }

                    if {$childFile eq ""} {
                        if {$verbosity > 1} { puts "      WARNING: Could not find file for entity: $child" }
                    } else {
                        if {![dict exists $scanned $childFile]} {
                            if {[lsearch -exact $toScan $childFile] < 0} {
                                lappend toScan $childFile
                                if {$verbosity > 2} { puts "      Queued for scanning: [file tail $childFile]" }
                            }
                        }
                    }
                }
            }
        } err]} {
            if {$verbosity > 0} { puts "  WARNING: Failed to parse $filepath: $err" }
        }
    }

    if {$verbosity > 0} {
        puts "Processed [dict size $scanned] VHDL files"
        puts "Found [llength $allEntities] entities, [llength $allPackages] packages"
    }

    # Generate source code viewer pages for all scanned files
    if {$verbosity > 0} { puts "Generating source code viewer pages..." }
    set sourceViewerMap [dict create]
    dict for {filepath val} $scanned {
        if {$verbosity > 1} { puts "  Creating viewer for: [file tail $filepath]" }
        set viewerPage [::aurig::doc::_emit_source_viewer $filepath $outdir $includeLogo]
        if {$viewerPage ne ""} {
            dict set sourceViewerMap $filepath $viewerPage
        }
    }
    if {$verbosity > 0} { puts "Generated [dict size $sourceViewerMap] source viewer pages" }

    # Build reverse hierarchy for "who uses this entity" display
    set reverseHierarchy [::aurig::doc::_build_reverse_hierarchy $allHierarchy]

    # Now emit entity and package pages with source viewer links
    if {$verbosity > 0} { puts "Generating entity and package documentation pages..." }
    dict for {filepath parseDict} $allParseDicts {
        foreach e [::aurig::core::analyze::q_entity_names $parseDict] {
            if {[lsearch -exact $allEntities $e] >= 0} {
                ::aurig::doc::_emit_entity_page $parseDict $outdir $fmt $e $sourceViewerMap $allHierarchy $reverseHierarchy $includeLogo
            }
        }
        foreach p [::aurig::core::analyze::q_packages $parseDict] {
            if {[dict exists $p name]} {
                set pname [dict get $p name]
                if {[lsearch -exact $allPackages $pname] >= 0} {
                    ::aurig::doc::_emit_package_page $parseDict $outdir $fmt $p $includeLogo
                }
            }
        }
    }

    # Collect missing entities for report
    set missingEntities [list]
    dict for {parent children} $allHierarchy {
        foreach child $children {
            # Check if this child entity was documented
            if {[lsearch -exact $allEntities $child] < 0} {
                # Try stripping library prefix for checking
                set simpleName $child
                if {[string match "*.*" $child]} {
                    set simpleName [lindex [split $child "."] end]
                }
                if {[lsearch -exact $allEntities $simpleName] < 0} {
                    lappend missingEntities $child
                }
            }
        }
    }
    set missingEntities [lsort -unique $missingEntities]

    # Emit index with complete hierarchy
    set topEntity [lindex $allEntities 0]
    ::aurig::doc::_emit_index $outdir $fmt $projectName $topEntity $allHierarchy $allEntities $allPackages $configData $entityToFile $entityToDesc $packageToFile $packageToDesc $includeLogo

    # Build file info dict for file list page (convert scanned dict to proper structure)
    set fileInfoDict [dict create]
    dict for {filepath val} $scanned {
        dict set fileInfoDict $filepath [dict create fullpath $filepath lib ""]
    }
    # Try to add library info from entity and package maps
    dict for {entity filepath} $entityToFile {
        if {[dict exists $fileInfoDict $filepath]} {
            dict set fileInfoDict $filepath lib "futurama_lib"
        }
    }

    # Generate file list page
    ::aurig::doc::_emit_file_list $outdir $fileInfoDict $entityToFile $packageToFile $sourceViewerMap $includeLogo

    # Generate text report
    set reportFile [file join $outdir "documentation_report.txt"]
    set fp [open $reportFile w]
    fconfigure $fp -translation lf

    puts $fp "================================================================"
    puts $fp "  DOCUMENTATION GENERATION REPORT"
    puts $fp "================================================================"
    puts $fp "Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fp "Project: $projectName"
    if {$topEntity ne ""} {
        puts $fp "Top Entity: $topEntity"
    }
    puts $fp ""

    puts $fp "----------------------------------------------------------------"
    puts $fp "  FILES ANALYZED"
    puts $fp "----------------------------------------------------------------"
    puts $fp "Total VHDL files scanned: [dict size $scanned]"
    puts $fp ""
    set count 0
    dict for {filepath val} $scanned {
        incr count
        puts $fp "  [format %3d $count]. [file tail $filepath]"
        if {$verbosity > 1} {
            puts $fp "       $filepath"
        }
    }
    puts $fp ""

    puts $fp "----------------------------------------------------------------"
    puts $fp "  ENTITIES DOCUMENTED"
    puts $fp "----------------------------------------------------------------"
    puts $fp "Total entities: [llength $allEntities]"
    puts $fp ""
    foreach e [lsort $allEntities] {
        set srcFile "unknown"
        if {[dict exists $entityToFile $e]} {
            set srcFile [file tail [dict get $entityToFile $e]]
        }
        puts $fp "  - $e (from $srcFile)"
    }
    puts $fp ""

    puts $fp "----------------------------------------------------------------"
    puts $fp "  PACKAGES DOCUMENTED"
    puts $fp "----------------------------------------------------------------"
    puts $fp "Total packages: [llength $allPackages]"
    puts $fp ""
    foreach p [lsort $allPackages] {
        set srcFile "unknown"
        if {[dict exists $packageToFile $p]} {
            set srcFile [file tail [dict get $packageToFile $p]]
        }
        puts $fp "  - $p (from $srcFile)"
    }
    puts $fp ""

    if {[llength $missingEntities] > 0} {
        puts $fp "----------------------------------------------------------------"
        puts $fp "  MISSING ENTITIES (Instantiated but not documented)"
        puts $fp "----------------------------------------------------------------"
        puts $fp "Total missing: [llength $missingEntities]"
        puts $fp ""
        puts $fp "The following entities are instantiated in the design hierarchy"
        puts $fp "but were not found in the specified file_sets:"
        puts $fp ""
        foreach e [lsort $missingEntities] {
            puts $fp "  - $e"
        }
        puts $fp ""
        puts $fp "Possible reasons:"
        puts $fp "  1. Files not included in YAML file_sets glob patterns"
        puts $fp "  2. Entity names don't match file names"
        puts $fp "  3. Files are in subdirectories not covered by patterns"
        puts $fp "  4. Vendor/library entities (can be ignored)"
        puts $fp ""
    } else {
        puts $fp "----------------------------------------------------------------"
        puts $fp "  ALL INSTANTIATED ENTITIES DOCUMENTED"
        puts $fp "----------------------------------------------------------------"
        puts $fp "All entities in the hierarchy were successfully documented."
        puts $fp ""
    }

    puts $fp "----------------------------------------------------------------"
    puts $fp "  SUMMARY"
    puts $fp "----------------------------------------------------------------"
    puts $fp "Files analyzed:        [dict size $scanned]"
    puts $fp "Entities documented:   [llength $allEntities]"
    puts $fp "Packages documented:   [llength $allPackages]"
    puts $fp "Missing entities:      [llength $missingEntities]"
    puts $fp ""
    puts $fp "Documentation output:  $outdir"
    puts $fp "Index page:            [file join $outdir index.$fmt]"
    puts $fp "This report:           $reportFile"
    puts $fp "================================================================"

    close $fp

    if {$verbosity > 0} {
        puts "project_documenter: wrote docs to $outdir (format=$fmt)"
        puts "project_documenter: wrote report to $reportFile"
        if {[llength $missingEntities] > 0} {
            puts "  WARNING: [llength $missingEntities] entities instantiated but not documented (see report)"
        }
    }
    return $outdir
}
