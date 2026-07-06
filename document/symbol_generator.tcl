# SPDX-License-Identifier: Apache-2.0
# Copyright 2024-2026 LogiMentor S.r.l.

#############################################
# SVG Symbol Generator for VHDL Entities
# Generates visual block diagrams with ports and generics
#############################################

# Parser/util closure this layer builds on (::aurig::core::analyze::* and
# ::aurig::core::util::*). aurig-doc does not bundle core, so declare the
# dependency explicitly (idempotent under the package index).
package require aurig::core

namespace eval ::aurig::doc {

# Helper to extract vector range from type and format it
# Returns [MSB:LSB] if vector, empty string otherwise
proc _extract_vector_range {type_str} {
    # Match patterns like (N downto 0), (0 to N), (15 downto 0), etc.
    if {[regexp -nocase {\(\s*([0-9]+)\s+downto\s+([0-9]+)\s*\)} $type_str -> msb lsb]} {
        return "\[$msb:$lsb\]"
    } elseif {[regexp -nocase {\(\s*([0-9]+)\s+to\s+([0-9]+)\s*\)} $type_str -> lsb msb]} {
        return "\[$msb:$lsb\]"
    }
    return ""
}

# Generate SVG symbol for an entity
# Returns inline SVG markup
proc _generate_entity_symbol {entity_name generics_list ports_list} {

    # Configuration
    set port_pitch 20
    set arrow_size 5
    set port_line_length 40
    set active_low_circle_radius 3
    set header_height 45
    set footer_height 35
    set min_block_width 180
    set margin_left 200
    set margin_right 200
    set font_size 13
    set port_font_size 10

    # Separate ports by direction
    set inputs {}
    set outputs {}
    set inouts {}

    foreach p $ports_list {
        set mode [expr {[dict exists $p mode] ? [dict get $p mode] : "in"}]
        set name [expr {[dict exists $p name] ? [dict get $p name] : ""}]
        set type [expr {[dict exists $p type] ? [dict get $p type] : ""}]

        if {$mode eq "in"} {
            lappend inputs [list $name $type]
        } elseif {$mode eq "out"} {
            lappend outputs [list $name $type]
        } elseif {$mode eq "inout"} {
            lappend inouts [list $name $type]
            lappend inputs [list $name $type]
            lappend outputs [list $name $type]
        }
    }

    set num_left [llength $inputs]
    set num_right [llength $outputs]
    set max_ports [expr {max($num_left, $num_right)}]

    # Adjust port pitch for entities with many ports
    if {$max_ports > 25} {
        set port_pitch 16
    } elseif {$max_ports > 40} {
        set port_pitch 14
    }

    # Calculate dimensions
    set block_height [expr {$max_ports * $port_pitch + $header_height + $footer_height}]
    if {$block_height < 80} { set block_height 80 }

    # Calculate max label width for inputs and outputs (including vector ranges)
    set max_input_width 0
    foreach port $inputs {
        lassign $port pname ptype
        set vector_range [_extract_vector_range $ptype]
        set display_name "$pname$vector_range"
        set len [string length $display_name]
        if {$len > $max_input_width} { set max_input_width $len }
    }

    set max_output_width 0
    foreach port $outputs {
        lassign $port pname ptype
        set vector_range [_extract_vector_range $ptype]
        set display_name "$pname$vector_range"
        set len [string length $display_name]
        if {$len > $max_output_width} { set max_output_width $len }
    }

    # Adjust margins based on actual port name lengths (7px per character approximately)
    set needed_left_margin [expr {$max_input_width * 7 + 10}]
    if {$needed_left_margin > $margin_left} {
        set margin_left $needed_left_margin
    }

    set needed_right_margin [expr {$max_output_width * 7 + 10}]
    if {$needed_right_margin > $margin_right} {
        set margin_right $needed_right_margin
    }

    # Block width based on entity name and generic text
    set block_width [expr {[string length $entity_name] * 8 + 60}]
    if {$block_width < $min_block_width} { set block_width $min_block_width }

    set total_width [expr {$block_width + $margin_left + $margin_right}]
    set total_height [expr {$block_height + 20}]

    # Start SVG
    set svg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$total_width\" height=\"$total_height\" viewBox=\"0 0 $total_width $total_height\">\n"

    # Define styles
    append svg "<defs>\n"
    append svg "<style>\n"
    append svg ".block-rect \{ fill: #f9f9f9; stroke: #942c13; stroke-width: 2; \}\n"
    append svg ".entity-name \{ font-family: 'Oswald', sans-serif; font-size: ${font_size}px; font-weight: 600; fill: #2f2a25; \}\n"
    append svg ".generic-text \{ font-family: 'Roboto', sans-serif; font-size: ${port_font_size}px; fill: #666; \}\n"
    append svg ".port-label \{ font-family: 'Roboto', sans-serif; font-size: ${port_font_size}px; fill: #2f2a25; \}\n"
    append svg ".port-type \{ font-family: 'Roboto', monospace; font-size: ${port_font_size}px; fill: #666; \}\n"
    append svg ".port-arrow \{ fill: #942c13; stroke: #942c13; stroke-width: 1; \}\n"
    append svg ".port-line \{ stroke: #942c13; \}\n"
    append svg ".active-low-circle \{ fill: none; stroke: #942c13; stroke-width: 1.5; \}\n"
    append svg "</style>\n"
    append svg "</defs>\n"

    set block_x $margin_left
    set block_y 10

    # Draw main block rectangle
    append svg "<rect class=\"block-rect\" x=\"$block_x\" y=\"$block_y\" width=\"$block_width\" height=\"$block_height\" rx=\"4\"/>\n"

    # Entity name at top center
    set name_x [expr {$block_x + $block_width / 2}]
    set name_y [expr {$block_y + 20}]
    append svg "<text class=\"entity-name\" x=\"$name_x\" y=\"$name_y\" text-anchor=\"middle\">$entity_name</text>\n"

    # Generics at bottom if any (one per line)
    if {[llength $generics_list] > 0} {
        set gen_start_y [expr {$block_y + $block_height - 15 - ([llength $generics_list] * 12)}]
        set gen_y $gen_start_y
        foreach g $generics_list {
            set gname [expr {[dict exists $g name] ? [dict get $g name] : ""}]
            set ginit [expr {[dict exists $g init] ? [dict get $g init] : ""}]
            set gen_text "$gname"
            if {$ginit ne ""} { append gen_text " = $ginit" }
            # Truncate individual generic if too long
            if {[string length $gen_text] > 30} {
                set gen_text "[string range $gen_text 0 27]..."
            }
            append svg "<text class=\"generic-text\" x=\"$name_x\" y=\"$gen_y\" text-anchor=\"middle\">$gen_text</text>\n"
            set gen_y [expr {$gen_y + 12}]
        }
    }

    # Draw input ports on left side
    set port_start_y [expr {$block_y + $header_height}]
    set y_pos $port_start_y
    foreach port $inputs {
        lassign $port pname ptype

        # Check if it's a bus (vector type) and if it's active low
        set is_bus [regexp -nocase {std_logic_vector|unsigned|signed} $ptype]
        set is_active_low [regexp -nocase {_n$|_n_i$} $pname]

        # Extract vector range and append to port name
        set vector_range [_extract_vector_range $ptype]
        set display_name "$pname$vector_range"

        # Port line into block (thicker for bus)
        set line_x1 [expr {$block_x - $port_line_length}]
        set line_x2 $block_x
        set line_width [expr {$is_bus ? 2.5 : 1.0}]
        append svg "<line class=\"port-line\" stroke-width=\"$line_width\" x1=\"$line_x1\" y1=\"$y_pos\" x2=\"$line_x2\" y2=\"$y_pos\"/>\n"

        # Active low indicator (empty circle inside block at pin)
        if {$is_active_low} {
            set circle_x [expr {$block_x + $active_low_circle_radius + 2}]
            append svg "<circle class=\"active-low-circle\" cx=\"$circle_x\" cy=\"$y_pos\" r=\"$active_low_circle_radius\"/>\n"
        }

        # Arrow pointing into block
        set arrow_x $block_x
        set arrow_y $y_pos
        set arrow_left [expr {$arrow_x - $arrow_size}]
        set arrow_top [expr {$arrow_y - $arrow_size}]
        set arrow_bottom [expr {$arrow_y + $arrow_size}]
        append svg "<polygon class=\"port-arrow\" points=\"$arrow_x,$arrow_y $arrow_left,$arrow_top $arrow_left,$arrow_bottom\"/>\n"

        # Port label (name with range) - outside on the left
        set label_x [expr {$line_x1 - 5}]
        set label_y [expr {$y_pos + 4}]
        append svg "<text class=\"port-label\" x=\"$label_x\" y=\"$label_y\" text-anchor=\"end\">$display_name</text>\n"

        set y_pos [expr {$y_pos + $port_pitch}]
    }

    # Draw output ports on right side
    set y_pos $port_start_y
    foreach port $outputs {
        lassign $port pname ptype

        # Check if it's a bus (vector type) and if it's active low
        set is_bus [regexp -nocase {std_logic_vector|unsigned|signed} $ptype]
        set is_active_low [regexp -nocase {_n$|_n_i$} $pname]

        # Extract vector range and append to port name
        set vector_range [_extract_vector_range $ptype]
        set display_name "$pname$vector_range"

        # Port line out of block (thicker for bus)
        set line_x1 [expr {$block_x + $block_width}]
        set line_x2 [expr {$line_x1 + $port_line_length}]
        set line_width [expr {$is_bus ? 2.5 : 1.0}]
        append svg "<line class=\"port-line\" stroke-width=\"$line_width\" x1=\"$line_x1\" y1=\"$y_pos\" x2=\"$line_x2\" y2=\"$y_pos\"/>\n"

        # Active low indicator (empty circle inside block at pin)
        if {$is_active_low} {
            set circle_x [expr {$line_x1 - $active_low_circle_radius - 2}]
            append svg "<circle class=\"active-low-circle\" cx=\"$circle_x\" cy=\"$y_pos\" r=\"$active_low_circle_radius\"/>\n"
        }

        # Arrow pointing out of block
        set arrow_x $line_x1
        set arrow_y $y_pos
        set arrow_right [expr {$arrow_x + $arrow_size}]
        set arrow_top [expr {$arrow_y - $arrow_size}]
        set arrow_bottom [expr {$arrow_y + $arrow_size}]
        append svg "<polygon class=\"port-arrow\" points=\"$arrow_x,$arrow_y $arrow_right,$arrow_top $arrow_right,$arrow_bottom\"/>\n"

        # Port label (name with range) - outside on the right
        set label_x [expr {$line_x2 + 5}]
        set label_y [expr {$y_pos + 4}]
        append svg "<text class=\"port-label\" x=\"$label_x\" y=\"$label_y\">$display_name</text>\n"

        set y_pos [expr {$y_pos + $port_pitch}]
    }

    append svg "</svg>\n"

    return $svg
}

}
