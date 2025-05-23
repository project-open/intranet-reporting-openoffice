# /packages/intranet-reporting-openoffice/www/intranet-reporting-openoffice-procs.tcl
#
# Copyright (C) 2003 - 2011 ]project-open[
#
# All rights reserved. Please check
# https://www.project-open.com/license/ for details.

ad_library {
    @author frank.bergmann@project-open.com
}


# ----------------------------------------------------------------------
# Add links to the list of menus in /intranet/projects/index
# ----------------------------------------------------------------------

ad_proc -public im_oo_cmd_executable_p { } {
    Returns the path of the executable OpenOffice binary
    of "" if there is no such executable
} {
    set oo_cmd [parameter::get_from_package_key -package_key "intranet-core" -parameter "OpenOfficeCmd" -default "loffice"]
    set oo_cmd_executable_p [util_memoize [list file executable $oo_cmd]]
    return $oo_cmd_executable_p
}

# ----------------------------------------------------------------------
# Auxillary Functions
# ----------------------------------------------------------------------

ad_proc im_oo_tdom_explore {
    {-level 0}
    -node:required
} {
    Returns a hierarchical representation of a tDom tree
    representing the content of an OOoo document in this case.
} {
    set name [$node nodeName]
    set type [$node nodeType]

    set indent ""
    for {set i 0} {$i < $level} {incr i} { append indent "    " }

    set result "${indent}$name"
    if {$type == "TEXT_NODE"} { return "$result=[$node nodeValue]\n" }
    if {$type != "ELEMENT_NODE"} { return "$result\n" }

    # Create a key-value list of attributes behind the name of the tag
    ns_log Notice "im_oo_tdom_explore: name=$name, type=$type, attributes=[$node attributes]"
    set attribute_list {}
    foreach attrib [$node attributes] {
        # Pull out the attributes identified by name:namespace.
        set attrib_name [lindex $attrib 0]
	ns_log Notice "im_oo_tdom_explore: attrib_name='$attrib_name'"
	if {"xmlns" eq $attrib_name} { continue } else { ns_log Notice "im_oo_tdom_explore: attrib_name='$attrib_name' != 'xmsns'" }
	set value [$node getAttribute $attrib]
        lappend attribute_list "$attrib_name=$value"
    }
    if {"" != $attribute_list} { append result " ([join $attribute_list ", "])" }
    append result "\n"

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        append result [im_oo_tdom_explore -node $child -level [expr $level + 1]]
    }
    return $result
}


ad_proc im_oo_to_text {
    -node:required
} {
    Returns all text contained in the node and its children.
    This is useful for example to extract the text contained
    in the "notes" section of a slide.
} {
    set name [$node nodeName]
    set type [$node nodeType]

    set result ""
    if {$name == "text:tab"} { set result "\t" }
    if {$type == "TEXT_NODE"} { return "[$node nodeValue]\n" }

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        append result [im_oo_to_text -node $child]
    }
    return $result
}

ad_proc im_oo_to_title {
    -node:required
} {
    Returns the title(s) of the node and its children.
    This is useful in order to identify specific elments
    in a template.
} {
    set title_nodes [im_oo_select_nodes $node "svg:title"]
    set titles {}
    foreach node $title_nodes {
	if {"" == $node} { continue }
	set title [string trim [im_oo_to_text -node $node]]
	set titles [concat $titles $title]
    }
    return $titles
}



ad_proc im_oo_page_notes {
    -page_node:required
} {
    Returns the "notes" from a slide page.
    The notes are used to store parameters.
} {
    # Go through all <text:p> nodes in all "presentation:notes" sections
    # (there should be only one)

    set notes_nodes [im_oo_select_nodes $page_node "presentation:notes"]
    set notes ""
    foreach notes_node $notes_nodes {
	append notes [im_oo_to_text -node $notes_node]
    }
    return $notes
}


ad_proc im_oo_select_nodes {
    node
    xpath
} {
    Returns a list of nodes that match the xpath.
} {
    set result [list]
    set name [$node nodeName]
    if {$name == $xpath} { lappend result $node }

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        set sub_result [im_oo_select_nodes $child $xpath]
	set result [concat $result $sub_result]
    }
    return $result
}


ad_proc im_oo_substitute {
    -page_name:required
    -node:required
    -parameters:required
} {
    Returns a new tDom node with with a copy of $node
    with template expressions substituted. The returned
    node is suitable to be inserted into a table.

    This functions work similar to template::adp_compile,
    but also allows the user to modify the XML structure
    around the substitution text.
} {
    ns_log Notice "im_oo_substitute_descend: page_name=$page_name"

    # Create a clone of the node
    set clone [$node cloneNode -deep]

    # Replace @varname@ expressions by the respective var value
    im_oo_substitute_descend -node_stack {} -parameters $parameters -node $clone

    return $clone
}


ad_proc im_oo_substitute_descend {
    -node:required
    -parameters:required
    -node_stack:required
} {
    Performes substitution on tDom nodes.
} {
    # Write the parameter list to a hash array
    array set params $parameters

    # Update the stack of nodes.
    # This way we can go upwards towards the parent node.
    set node_stack [linsert $node_stack 0 $node]
    
    # get the name and type of the node
    set name [$node nodeName]
    set type [$node nodeType]
    set text ""
    if {$type == "TEXT_NODE"} { 
	set text [$node nodeValue]
	set org_text $text

	# Loop through all @varname@ expressions and replaceReplace variable expressions
	set cnt 0
	while {[regexp {^(.*?)@([a-zA-Z0-9_]+)@(.*)$} $text match head var tail]} {
	    ns_log Notice "im_oo_substitute_descend: head=$head, var=$var, tail=$tail"
	    set val $var
	    if {[info exists params($var)]} { set val $params($var) }
	    set text "$head$val$tail"
	    incr cnt
	    if {$cnt > 10} { ad_return_complaint 1 "im_oo_substitute_descend: infinite loop: '$text':<br><pre>[ad_print_stack_trace]</pre>" }
	}
	ns_log Notice "im_oo_substitute_descend: result=$text"

        # Check for #tag=value expression
	set cnt 0
	while {[regexp {^(.*?)\s*#([a-zA-Z0-9_\:\-]+)=([a-zA-Z0-9_\:\-]+)\s*(.*)$} $text match head tag value tail]} {
	    ns_log Notice "im_oo_substitute_descend: node_name=$name, node_type=$type"
	    ns_log Notice "im_oo_substitute_descend: tag=$tag, value=$value"

	    # Walk through the list of parents and replace the attribute at the first matching parent
	    set break_p 0
	    foreach n $node_stack {
		set n_name [$n nodeName]
		set n_type [$n nodeType]
		if {"TEXT_NODE" != $n_type} {
		    if {[$n hasAttribute $tag]} {
			$n setAttribute $tag $value
			set break_p 1
		    }
		}
		if {$break_p} { break }
	    }

	    set text "$head$tail"
	    incr cnt
	    if {$cnt > 10} { ad_return_complaint 1 "im_oo_substitute_descend: infinite loop: '$text':<br><pre>[ad_print_stack_trace]</pre>" }
        }

	# Perform the substitution
        if {$text != $org_text} { $node nodeValue $text }

    }

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        im_oo_substitute_descend -node_stack $node_stack -parameters $parameters -node $child
    }
}


# -------------------------------------------------------
# Template Procs
# -------------------------------------------------------

ad_proc im_oo_page_delete {
    -page_node_list:required
} {
    Delete a list of pages
} {
    ns_log Notice "im_oo_page_delete: page_node_list=$page_node_list"

    foreach page_node $page_node_list {
	set len [llength $page_node]
	ns_log Notice "im_oo_page_delete: page_node=$page_node, len=$len"

	switch $len {
	    1 {
		ns_log Notice "im_oo_page_delete: About to delete node=$page_node"
		set page_container [$page_node parentNode]
		if {"" != $page_container} {
                        $page_container removeChild $page_node
		}
	    }
	    default {
                    im_oo_page_delete -page_node_list $page_node
	    }
	}
    }
}


ad_proc im_oo_page_delete_templates {
    -page_node:required
} {
    Delete template nodes from the given page.
} {
    foreach child [$page_node childNodes] {
	set titles [string tolower [im_oo_to_title -node $child]]
	ns_log Notice "im_oo_page_delete_templates: titles=$titles"
	foreach title $titles {
	    switch $title {
		green_bar - yellow_bar - red_bar {
		    ns_log Notice "im_oo_page_delete_templates: delete node title='$title'"
		    $page_node removeChild $child
		}
	    }
	}
    }
}

ad_proc im_oo_page_extract_templates {
    -page_node:required
} {
    Returns a key-value list of all "templates" on the specified page.
    Most templates are individual objects (without grouping), so looping
    through all these elements we should find all templates
} {
    array set hash {}
    foreach child [$page_node childNodes] {
	set titles [string tolower [im_oo_to_title -node $child]]
	ns_log Notice "im_oo_page_extract_templates: titles=$titles"
	foreach title $titles {
		switch $title {
		    green_square - yellow_square - red_square {
			# <draw:frame draw:style-name="gr4" svg:width="1.014cm" svg:height="1.267cm" svg:x="6cm" svg:y="16.9cm">
			# <draw:text-box><text:p><text:span text:style-name="T8">?</text:span></text:p></draw:text-box>
			# <svg:title>green_square</svg:title>
			# </draw:frame>
			set node_type "draw:text-box"
			set span_node [im_oo_select_nodes $child $node_type]
			if {"" eq $span_node} {
			    ns_log Warning "im_oo_page_extract_templates: $title=$title: Did not find node_type=$node_type"
			    continue
			}
			set hash($title) [$span_node asXML]
		    }
		    green_bar - yellow_bar - red_bar - today_bar {
			# Groupings used as templates for Gantt bars.
			# We need to move the groupings to 0/0 coordinates.
			ns_log Notice "im_oo_page_extract_templates: $title=$title"
			set x_y_offset [im_oo_page_type_gantt_grouping_x_y_offset -node $child]

			set x_offset [lindex $x_y_offset 0]
			set "${title}_x_offset" $x_offset
			set hash(${title}_x_offset) $x_offset

			set y_offset [lindex $x_y_offset 1]
			set "${title}_y_offset" $y_offset
			set hash(${title}_y_offset) $y_offset

			im_oo_page_type_gantt_grouping_move -node $child -offset_list [list [expr -$x_offset] [expr -$y_offset]]
			ns_log Notice "im_oo_page_extract_templates: $title=$child"
			set hash($title) $child
		    }
		    text_style {
			# Check for text styles. These are just a piece of text with a title.
			# In the example below we want to extract that text_style "red" corresponds to "T7"
			# <draw:frame draw:style-name...><draw:text-box><text:p text:style-name="P8">
			# <text:span text:style-name="T7">Red Text</text:span>
			# </text:p></draw:text-box><svg:title>text_style red</svg:title></draw:frame>
			set style_name [lindex $titles 1]
			if {"" == $style_name} { continue }
			set span_nodes [im_oo_select_nodes $child "text:span"]
			foreach span_node $span_nodes {
			    set text_style [$span_node getAttribute "text:style-name"]
			    ns_log Notice "im_oo_page_extract_templates: Text Styles: Found text style '$text_style' with title '$style_name'"
			    set hash($style_name) $text_style
			}
		    }
		    default {
			# Check for text styles. These are just a piece of text with a title.
			if {[regexp {^text_style(.*)} $title match style_title]} {
			    # <draw:frame draw:style-name...><draw:text-box><text:p text:style-name="P8">
			    # <text:span text:style-name="T7">Red Text</text:span>
			    # </text:p></draw:text-box><svg:title>style red</svg:title></draw:frame>
			    set span_nodes [im_oo_select_nodes $child "text:span"]
			    foreach span_node $span_nodes {
				set text_style [$span_node getAttribute "text:style-name"]
				ns_log Notice "im_oo_page_extract_templates: Text Styles: Found text style '$text_style' with title '$style_title' - $titles."
				ad_return_complaint 1 "im_oo_page_extract_templates: Text Styles: Found text style '$text_style' with title '$style_title' - $titles:<br><pre>[ad_print_stack_trace]</pre>"

			    }
			}
			# End of default section
		    }
		}
	    if {[catch {
	    } err_msg]} {
		ns_log Notice "im_oo_page_extract_templates: $err_msg"
	    }
	}
    }

    # Special logic to calculate the distance between the gantt bars
    if {[info exists hash(green_bar)] && [info exists hash(red_bar)]} {
	set y_dist [expr ($red_bar_y_offset - $green_bar_y_offset) / 2.0]
    } elseif {[info exists hash(green_bar)] && [info exists hash(yellow_bar)]} {
	set y_dist [expr ($yellow_bar_y_offset - $green_bar_y_offset) / 1.0]
    } else {
	set y_dist 1.5
    }
    set hash(y_dist) $y_dist

    # Return the hash as key-value list that will be written to 
    # local variables in the caller's environment
    return [array get hash]
}



# ---------------------------------------------------------------
# Execute a list of pages
# ---------------------------------------------------------------

ad_proc im_oo_page_list {
    -insert_node:required
    -page_node_list:required
    -parameters:required
} {
    "Execute" a list of pages.
    @param insert_node
		Node where the pages should be inserted.
		This is usually identical with the page_node.
    @param page_node_list 
		A list of nodes to be processed
    @param parameters A key-value list of variables used during
		template
} {
    ns_log Notice "im_oo_page_list: page_node_list={$page_node_list}, parameters=$parameters"

    set long_dash [format "%c" 8211]
    array set query_hash $parameters

    foreach page_node_tree $page_node_list {
  
	# The actual page node is located in the first position of the structure
	set page_node [lindex $page_node_tree 0]
	# The second position is a list of sub-pages for "repeat" pages
	set page_sub_nodes [lindex $page_node_tree 1]
	
	# Extract the "page name" from OOoo.
	# We use this field to determine the type of the page
	set page_name_list [$page_node getAttribute "draw:name"]
	set page_type [lindex $page_name_list 0]
	set page_name [lrange $page_name_list 1 end]
	
	set page_notes [im_oo_page_notes -page_node $page_node]
	set page_sql ""
	set list_sql ""
	set repeat_sql ""
	set counters ""
	for {set i 0} {$i < [llength $page_notes]} {incr i 2} {
	    set varname [string tolower [lindex $page_notes $i]]
	    set varvalue [lindex $page_notes [expr $i+1]]
	    # Substitute a "long dash" ("--") with a normal one
	    regsub -all $long_dash $varvalue "-" varvalue
	    switch $varname {
		page_sql { set page_sql $varvalue }
		list_sql { set list_sql $varvalue }
		repeat_sql { set repeat_sql $varvalue }
		default {
		    set query_hash($varname) $varvalue
		}
	    }
	}
	
	append debug "<li>$page_type=$page_type, page_name=$page_name, page_sql=$page_sql, list_sql=$list_sql\n"
	ns_log Notice "im_oo_page_list: Page: type=$page_type, name=$page_name, node=$page_node, sub_nodes=$page_sub_nodes"
	
	switch $page_type {
	    template {
		set result [im_oo_page_type_template \
				-page_node $page_node \
				-insert_node $insert_node \
				-page_name $page_name \
				-parameters [array get query_hash] \
				-list_sql $list_sql \
				-page_sql $page_sql \
			       ]
		# Add the templates to the query hash
		array set query_hash $result
	    }
	    constant {
		im_oo_page_type_constant \
		    -page_node $page_node \
		    -insert_node $insert_node \
		    -page_name $page_name \
		    -parameters [array get query_hash] \
		    -list_sql $list_sql \
		    -page_sql $page_sql
	    }
	    static {
		im_oo_page_type_static \
		    -page_node $page_node \
		    -insert_node $insert_node \
		    -page_name $page_name \
		    -parameters [array get query_hash] \
		    -list_sql $list_sql \
		    -page_sql $page_sql
	    }
	    repeat {
		im_oo_page_type_repeat \
		    -page_node $page_node \
		    -insert_node $insert_node \
		    -page_name $page_name \
		    -parameters [array get query_hash] \
		    -repeat_sql $repeat_sql \
		    -page_sub_nodes $page_sub_nodes
	    }
	    list {
		im_oo_page_type_list \
		    -page_node $page_node \
		    -insert_node $insert_node \
		    -page_name $page_name \
		    -parameters [array get query_hash] \
		    -list_sql $list_sql \
		    -page_sql $page_sql
	    }
	    gantt {
		im_oo_page_type_gantt \
		    -page_node $page_node \
		    -insert_node $insert_node \
		    -page_name $page_name \
		    -parameters [array get query_hash] \
		    -list_sql $list_sql \
		    -page_sql $page_sql
	    }
	    default {
		ad_return_complaint 1 "<b>Found unknown page type '$page_type' in page '$page_name':</b><br><pre>[ad_print_stack_trace]</pre>"
		ad_script_abort
	    }
	}
    }
}




# -------------------------------------------------------
# Page processession procs
# -------------------------------------------------------

ad_proc im_oo_page_type_constant {
    -page_node:required
    -insert_node:required
    -parameters:required
    {-list_sql ""}
    {-page_sql "" }
    {-page_name "undefined"}
} {
    A "constant" page contains only static contents.
    No substitution whatsoever will take place.

    @param page_node A tDom node for a draw:page node
    @param sqlAn SQL statement that should return a single row.
		The returned columns are available as variables
		in the template.
    @param repeat An optional SQL statement.
		The template will be repated for every "repeat"
		row with the repeat columns available as variables
		for the SQL statement.
    @param page_name The name of the slide 
		(for debugging purposes)

} {
    # Do nothing
}



ad_proc im_oo_page_type_template {
    -page_node:required
    -insert_node:required
    -parameters:required
    {-list_sql ""}
    {-page_sql "" }
    {-page_name "undefined"}
} {
    Takes as input a page node from the template with
    a list of templates on it. The page extracts the
    templates and returns them in a hash.
} {
    # Extract templates from the page and write to local variables
    set template_hash_list [im_oo_page_extract_templates -page_node $page_node]
    return $template_hash_list
}



ad_proc im_oo_page_type_static {
    -page_node:required
    -insert_node:required
    -parameters:required
    {-list_sql ""}
    {-page_sql "" }
    {-page_name "undefined"}
} {
    The procedure will replace the template's @varname@
    variables by the values returned from the SQL statement.
} {
    # Write global parameters into local variables
    array set param_hash $parameters
    foreach var [array names param_hash] { set $var $param_hash($var) }

    # Check the page_sql statement and perform substitutions
    if {"" == $page_sql} { set page_sql "select 1 as one from dual" }
    if {[catch {
	eval [template::adp_compile -string $page_sql]
	set page_sql $__adp_output
	set page_sql [eval "set a \"$page_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>Static: '$page_name': Error substituting variables in page_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Convert the tDom tree into XML for rendering
    set template_xml [$page_node asXML]

    if {[catch {
	db_foreach page_sql $page_sql {
	    # Replace placeholders in the OpenOffice template row with values
	    if {[catch {
		eval [template::adp_compile -string $template_xml]
		set xml $__adp_output
	    } err_msg]} {
		ad_return_complaint 1 "<b>Static: '$page_name': Error substituting variables</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
		ad_script_abort
	    }
	    
	    # Parse the new slide and insert into OOoo document
	    ns_log Notice "im_oo_page_type_static: xml=$xml"
	    set doc [dom parse $xml]
	    set doc_doc [$doc documentElement]

	    set doc_doc [im_oo_substitute -page_name $page_name -node $doc_doc -parameters $parameters]

	    # Insert the new slide before insert_node
	    set page_container [$insert_node parentNode]
	    $page_container insertBefore $doc_doc $insert_node
	    ns_log Notice "im_oo_page_type_static: Inserting new page before node=$doc_doc"
	}
    } err_msg]} {
        ad_return_complaint 1 "<b>Static: '$page_name': Error evaluating page_sql statement</b>:<pre>[ad_print_stack_trace]</pre>"
        ad_script_abort	
    }
}




ad_proc im_oo_page_type_repeat {
    -page_node:required
    -insert_node:required
    -page_sub_nodes:required
    -parameters:required
    -page_name:required
    -repeat_sql:required
} {
    Repeat the following N slides for all rows coming out
    of the repeat_sql statement
} {
    # Write parameters into hash and local variables
    array set param_hash $parameters
    foreach var [array names param_hash] { set $var $param_hash($var) }

    # Check the repeat_sql statement and perform substitutions
    if {"" == $repeat_sql} { set repeat_sql "select 1 as one from dual" }
    if {[catch {
	eval [template::adp_compile -string $repeat_sql]
	set repeat_sql $__adp_output
	set repeat_sql [eval "set a \"$repeat_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>Repeat: '$page_name': Error substituting variables in repeat_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    if {[catch {
	# Loop through the repeat_sql and write the results into param_hash
	db_with_handle repeat_sql_db {
	    set repeat_sql_selection [db_exec select $repeat_sql_db repeat_sql $repeat_sql 1]
	    set repeat_sql_columns [ad_ns_set_keys $repeat_sql_selection]
	    while {[db_getrow $repeat_sql_db $repeat_sql_selection]} {

		for {set i 0} {$i < [llength $repeat_sql_columns]} {incr i} {
		    set var [lindex $repeat_sql_columns $i]
		    set val [ns_set value $repeat_sql_selection $i]
		    set $var $val
		    set param_hash($var) $val
		}

		# "Execute" the list of pages
		im_oo_page_list \
		    -page_node_list $page_sub_nodes \
		    -insert_node $page_node \
		    -parameters [array get param_hash]

	    }
	}
    } err_msg]} {
        ad_return_complaint 1 "<b>Repeat: '$page_name': Error evaluating repeat_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort	
    }
}


ad_proc im_oo_page_type_list {
    -page_node:required
    -insert_node:required
    -parameters:required
    {-locale ""}
    {-list_sql ""}
    {-page_sql "" }
    {-page_name "undefined"}
} {
    Takes as input a page node from the template with
    a table and a sql parameter in the "notes".
    It interprets the second row of the first table as
    a template and replaces this row with lines for 
    each of the SQL results.<br>
    Expected data structures: The "sql_list" page type 
    requires a table with two rows:
    <ul>
    <li>The title row and
    <li>The data row with @var_name@ variables
    <li>The page also needs to provide a "list_sql" argument
        in the page comments that will be used to create
        the data to be shown.
    </ul>
} {
    # ------------------------------------------------------------------
    # Constants & Arguments

    # Default number of table rows per page, may be overwritten by list_max_rows parameter
    set list_max_rows 10

    # Initialize counters
    set counters {}

    # Number formatting
    if {"" == $locale} { set locale [lang::user::locale] }
    set rounding_precision 2
   
    array set param_hash $parameters
#    ad_return_complaint 1 "im_oo_page_type_list: <pre>[ns_quotehtml $parameters]</pre>"

    # fraber 120517: We expect that a template page went before...
    # array set param_hash [im_oo_page_extract_templates -page_node $page_node]
    foreach var [array names param_hash] { set $var $param_hash($var) }

    if {"" == $list_sql} {
        ad_return_complaint 1 "<b>'$page_name': No list_sql specified in list page</b>:<br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Check the page_sql statement and perform substitutions
    if {"" == $page_sql} { set page_sql "select 1 as one from dual" }
    if {[catch {
	eval [template::adp_compile -string $page_sql]
	set page_sql $__adp_output
	set page_sql [eval "set a \"$page_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>List: '$page_name': Error substituting variables in page_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Perform substitutions on the list_sql statement
    if {[catch {
	eval [template::adp_compile -string $list_sql]
	set list_sql $__adp_output
	set list_sql [eval "set a \"$list_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>List: '$page_name': Error substituting variables in SQL statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Make a copy of the entire page.
    # We may have to generate more then one page
    set template_xml [$page_node asXML]

    # Set the "content row" variable to default values.
    # Normally the content row should contain the table row to be repeated...
    set content_row_node ""
    set content_row_xml ""
    set page_total_node ""
    set list_total_node ""

    # ------------------------------------------------------------------
    # Start processing the template

    # Loop through all repetitions
    if {[catch {
	db_foreach page_sql $page_sql {
	    
	    # Reset counters
	    foreach counter $counters {
		set counter_var [lindex $counter 0]
		set counter_var_pretty "${counter_var}_pretty"
		set counter_var_sor "${counter_var}_sor"

		set $counter_var 0
		set $counter_var_pretty 0
		set $counter_var_sor 0
	    }

	    # Parse the template in order to create a "fresh" XML tree.
	    # We are going to use this tree to insert rows into the first list.
	    set page_doc [dom parse $template_xml]
	    set page_root [$page_doc documentElement]

	    set row_cnt 0
	    set first_page_p 1
	    if {[catch {
		# Loop through the list_sql and write the results into param_hash
		db_with_handle list_sql_db {
		    set list_sql_selection [db_exec select $list_sql_db list_sql $list_sql 1]
		    set list_sql_columns [ad_ns_set_keys $list_sql_selection]
		    while {[db_getrow $list_sql_db $list_sql_selection]} {
			for {set i 0} {$i < [llength $list_sql_columns]} {incr i} {
			    set var [lindex $list_sql_columns $i]
			    set val [ns_set value $list_sql_selection $i]
			    # ns_log Notice "im_oo_page_type_list: list_sql: $var=$val"
			    set $var $val
			    set param_hash($var) $val
			}

			# ------------------------------------------------------------------
			# Setup a new page.
			# Execute this code either if we are on the very first page or
			# if we have to start a new page because of a long table.
			if {$row_cnt >= $list_max_rows || $first_page_p} {
			    
			    # Close the previous page, add it to the Impress document and start a new one.
			    if {0 == $first_page_p} {
				
				# Remove the content_row
				if {"" != $content_row_node} { $table_node removeChild $content_row_node }
				
				# Remove the 4th line from the list in all but the last page
				if {"" != $list_total_node} { $table_node removeChild $list_total_node }
				
				# Render the new page with the additional table rows as XML
				# and apply the OpenACS template engine in order to replace variables.
				set page_xml [$page_root asXML -indent none]
				if {[catch {
				    eval [template::adp_compile -string $page_xml]
				    set xml $__adp_output
				} err_msg]} {
				    ad_return_complaint 1 "<b>List: '$page_name': Error substituting page variables</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
				    ad_script_abort
				}
				
				# Parse the new slide and insert into OOoo document
				set result_doc [dom parse $xml]
				set result_root [$result_doc documentElement]

				# Get the parent of the insert_node and insert before that node.
				set page_container [$insert_node parentNode]
				$page_container insertBefore $result_root $insert_node
			    }
			    
			    # Now we are not on the first page anymore...
			    set first_page_p 0
			    
			    # Create a fresh XML tree again for the next page and reset the row counter
			    set page_doc [dom parse $template_xml]
			    set page_root [$page_doc documentElement]
			    set row_cnt 0
			    
			    # Get the list of all tables in the page and count them
			    set table_nodes [im_oo_select_nodes $page_root "draw:frame"]
			    set table_node ""
			    foreach node $table_nodes {
				set node_text [string trim [im_oo_to_title -node $node]]
				ns_log Notice "im_oo_page_type_list: Searching for list node: text='$node_text'"
				if {"list" == $node_text} { 
				    # We found a draw:frame node with the right title.
				    # This node should have exactly one "table:table"
				    set table_frame_node $node
				    set table_node [lindex [im_oo_select_nodes $node "table:table"] 0]
				}
			    }
			    
			    if {"" == $table_node} {
				ad_return_complaint 1 "<b>im_oo_page_type_list '$page_name'</b>:<br>
			Didn't find a table with title 'list'.<br>
		        <pre>[ns_quotehtml [$page_root asXML]]</pre><br><pre>[ad_print_stack_trace]</pre>"
				ad_script_abort
			    }
			    
			    # Extract the 2nd row ("table:table-row" tag) that contains the 
			    # content row to be repeated for every row of the list_sql
			    set row_nodes [im_oo_select_nodes $table_node "table:table-row"]
			    set content_row_node [lindex $row_nodes 1]
			    set page_total_node [lindex $row_nodes 2]
			    set list_total_node [lindex $row_nodes 3]
			    set content_row_xml [$content_row_node asXML]
			    if {"" == $content_row_node} {
				ad_return_complaint 1 "<b>im_oo_page_type_list '$page_name': Table only has one row</b><br><pre>[ad_print_stack_trace]</pre>"
				ad_script_abort
			    }
			}
			
			# ------------------------------------------------------------------
			# Update Counters
			# Counters allow to sum up values in a list column.
			# A counter consists of a list with two values:
			#	- counter_var: The name of the counter variables
			#	- counter_expr: A numeric expression that defines 
			#	  the value to be added to the counter.
			# The counter expression may contain any parameters 
			# of the static page or values returned from the list_sql.
			# The counter value can be used in the page_total and 
			# total lines of a list just like a normal variable.
			#
			foreach counter $counters {
			    set counter_var [lindex $counter 0]
			    set counter_expr [lindex $counter 1]
			    set counter_var_pretty "${counter_var}_pretty"
			    set counter_var_sor "${counter_var}_sor"

			    if {![info exists $counter_var]} { set $counter_var 0 }
			    set val ""
			    if {[catch {
				set val [expr $counter_expr]
			    } err_msg]} {
				ad_return_complaint 1 "<b>im_oo_page_type_list '$page_name': Error updating counter</b>:<br>
			Counter name: '$counter_var'<br>
			Counter expressions: '$counter_expr'<br>
			Error:<br><pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
				ad_script_abort
			    }
			    if {"" != $val && [string is double $val]} {
				set $counter_var [expr "\$$counter_var + $val"]

				# Pretty formatting of sum
				set amount_zeros [im_numeric_add_trailing_zeros [expr "\$$counter_var"] $rounding_precision]
				set sum_pretty [lc_numeric $amount_zeros "" $locale]
				set $counter_var_pretty $sum_pretty
				
				# SOR formatting of sum: cut off decimals and use accounting "(...)" brackets for negative numbers
				if {[regexp {^(.+)\,.+$} $sum_pretty match sum]} { set sum_pretty $sum }
				if {[regexp {^\-(.+)$} $sum_pretty match sum]} { set sum_pretty "($sum)" }
				set $counter_var_sor $sum_pretty
			    }
			}
			
			# ------------------------------------------------------------------
			# Replace placeholders in the OpenOffice template row with values
			# !!!
			set new_row_node [im_oo_substitute -page_name $page_name -node $content_row_node -parameters [array get param_hash]]
			$table_node insertBefore $new_row_node $content_row_node
			
			incr row_cnt

			# End of the list_sql loop
		    }
		}

	    } err_msg]} {
		ad_return_complaint 1 "<b>List '$page_name': Error evaluating list_sql</b>:<br><pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
		ad_script_abort
	    }

	    # Deal with the case of zero rows returned:
	    # Extract the "content_row", so that we can delete this below
	    if {0 == $row_cnt} {

		# Create a fresh XML tree again for the next page and reset the row counter
		set page_doc [dom parse $template_xml]
		set page_root [$page_doc documentElement]
		set row_cnt 0

		# Get the list of all tables in the page and count them
		set table_nodes [im_oo_select_nodes $page_root "draw:frame"]
		set table_node ""
		foreach node $table_nodes {
		    set node_text [string trim [im_oo_to_title -node $node]]
		    ns_log Notice "im_oo_page_type_list: Searching for list node: text='$node_text'"
		    if {"list" == $node_text} {
			# We found a draw:frame node with the right title.
			# This node should have exactly one "table:table"
			set table_frame_node $node
			set table_node [lindex [im_oo_select_nodes $node "table:table"] 0]
		    }
		}
		
		if {"" == $table_node} {
		    ad_return_complaint 1 "<b>im_oo_page_type_list '$page_name'</b>:<br>
                        Didn't find a table with title 'list'.<br>
                        <pre>[ns_quotehtml [$page_root asXML]]</pre><br><pre>[ad_print_stack_trace]</pre>"
		    ad_script_abort
		}

		set row_nodes [im_oo_select_nodes $table_node "table:table-row"]
		set content_row_node [lindex $row_nodes 1]
	    }

	    # ------------------------------------------------------------------
	    # The last page of the list. This can also be the very first page with short lists.

	    # Remove the content_row
	    if {"" != $content_row_node} { 
		catch {
		    [$content_row_node parentNode] removeChild $content_row_node 
		}
	    }

	    # Apply the OpenACS template engine
	    set page_xml [$page_root asXML]
	    if {[catch {
		eval [template::adp_compile -string $page_xml]
		set xml $__adp_output
	    } err_msg]} {
		ad_return_complaint 1 "<b>List: '$page_name': Error substituting variables in last page</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
		ad_script_abort
	    }

	    # Parse the new slide ...
	    set result_doc [dom parse $xml]
	    set result_root [$result_doc documentElement]

	    # ... and insert before insert_node.
	    set page_container [$insert_node parentNode]
	    $page_container insertBefore $result_root $insert_node

	    # End looping through multiple pages
	}
    } err_msg]} {
        ad_return_complaint 1 "<b>List: '$page_name': Error executing page_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }
}




ad_proc im_oo_page_type_gantt_grouping_extract_x_y_offset_list {
    {-level 0}
    -node:required
} {
    Takes a grouping, extracts all x and all y coordinates of 
    objects and returns a list {min_x min_y}.
} {
    set name [$node nodeName]
    set type [$node nodeType]

    # Initialize the list of return values
    set x_list {}
    set y_list {}

    # Skipe text and element nodes
    if {$type == "TEXT_NODE" || $type != "ELEMENT_NODE"} { return [list $x_list $y_list] }

    ns_log Notice "im_oo_page_type_gantt_grouping_x_y_offset: name=$name, attrib=[$node attributes]"
    foreach attrib [$node attributes] {
	# Attributes sometimes are a list {attrib ns url}
	if {3 == [llength $attrib]} {
	    set attrib "[lindex $attrib 1]:[lindex $attrib 0]"
	    ns_log Notice "im_oo_page_type_gantt_grouping_x_y_offset: attrib from list: '$attrib'"
	}

	# Get the attribute value and remove possible "cm" after the value
	set value [$node getAttribute $attrib]
	if {[regexp {^([0-9\-\.]+)} $value match val]} { set value $val}

	# Append to the respective list
	if {"svg:x" == $attrib || "svg:x1" == $attrib} { lappend x_list $value }
	if {"svg:y" == $attrib || "svg:y1" == $attrib} { lappend y_list $value }
    }

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        set res [im_oo_page_type_gantt_grouping_extract_x_y_offset_list -node $child -level [expr $level + 1]]
	set x_list [concat $x_list [lindex $res 0]]
	set y_list [concat $y_list [lindex $res 1]]
    }
    return [list $x_list $y_list]
}

ad_proc im_oo_page_type_gantt_grouping_x_y_offset {
    {-level 0}
    -node:required
} {
    Takes a grouping, extracts all x and all y coordinates of 
    objects and returns a list {min_x min_y}.
} {
    # Extract the list of x and y values.
    set res [im_oo_page_type_gantt_grouping_extract_x_y_offset_list -node $node]
    set x_list [lindex $res 0]
    set y_list [lindex $res 1]

    # Calculate the minimum value
    set min_x 999.9
    set min_y 999.9
    foreach x $x_list { if {$x < $min_x} { set min_x $x } }
    foreach y $y_list { if {$y < $min_y} { set min_y $y } }

    return [list $min_x $min_y]
}


ad_proc im_oo_page_type_gantt_grouping_move {
    {-level 0}
    -node:required
    -offset_list:required
} {
    Move all svg:x and svg:y coordinates in a grouping by the specified offset.
    @param node: The tDom node of the grouping
    @param offset_list: {x_offset y_offset}
} {
    set name [$node nodeName]
    set type [$node nodeType]

    set x_offset [lindex $offset_list 0]
    set y_offset [lindex $offset_list 1]

    # Skipe text and element nodes
    if {$type == "TEXT_NODE" || $type != "ELEMENT_NODE"} { return }

    ns_log Notice "im_oo_page_type_gantt_grouping_move: name=$name, attrib=[$node attributes]"
    foreach attrib [$node attributes] {

	# Attributes sometimes are a list {attrib ns url}
	if {3 == [llength $attrib]} {
	    set attrib "[lindex $attrib 1]:[lindex $attrib 0]"
	    ns_log Notice "im_oo_page_type_gantt_grouping_move: attrib from list: '$attrib'"
	}

        # Get the attribute value and remove possible "cm" after the value
        set value [$node getAttribute $attrib]
        if {[regexp {^([0-9\-\.]+)(.*)$} $value match val unit]} { set value $val }

        # Apply the offset
	switch $attrib {
	    "svg:x" - "svg:x1" - "svg:x2" {
		set x [expr $value + $x_offset]
		$node setAttribute $attrib "$x$unit"
	    }
	    "svg:y" - "svg:y1" - "svg:y2" {
		set y [expr $value + $y_offset]
		$node setAttribute $attrib "$y$unit"		
	    }
	}
    }

    # Recursively descend to child nodes
    foreach child [$node childNodes] {
        im_oo_page_type_gantt_grouping_move \
	    -node $child \
	    -level [expr $level + 1] \
	    -offset_list $offset_list
    }
    return
}

ad_proc im_oo_page_type_gantt_move_scale {
    -grouping_node:required
    {-gantt_name ""}
    -page_name:required
    -base_x_offset:required
    -base_y_offset:required
    -start_date_x:required
    -end_date_x:required
    -start_date_epoch:required
    -end_date_epoch:required
    -main_project_start_date_epoch:required
    -main_project_end_date_epoch:required
    -row_cnt:required
    -y_dist:required
    -percent_completed:required
    -percent_expected:required
} {
    Move and scale a template bar according to start- and end date.
    @takes a <draw:g> group of elements with the following texts:
    - @percent_completed@: The bar representing the current completion level
    - @percent_expected@: The bar representing the expected completeion level now.
    All other elements are optional. Normal template formatting rules will apply.
} {
    ns_log Notice "im_oo_page_type_gantt_move_scale: Starting to process $gantt_name in page $page_name"
    set base_node ""
    set completed_node ""
    set expected_node ""
    set start_date_node ""
    set end_date_node ""
    set today_node ""

    if {"" == $percent_completed} { set percent_completed 0.0 }
    if {"" == $percent_expected} { set percent_expected 0.0 }

    foreach node [$grouping_node childNodes] {
	set text [string trim [im_oo_to_title -node $node]]
	# ns_log Notice "im_oo_page_type_gantt_move_scale: text=$text"
	switch $text {
	    "base_bar" { set base_node $node}
	    "completed_bar" { set completed_node $node }
	    "expected_bar" { set expected_node $node }
	    "start_date_bar" { set start_date_node $node }
	    "end_date_bar" { set end_date_node $node }
	}
    }
    if {"" == $base_node || "" == $completed_node || "" == $expected_node} {
	ad_return_complaint 1 "<b>im_oo_page_type_gantt_move_scale '$page_name'</b>:<br>
	The grouping doesn't contain the necessary three nodes:<br>
	<ul><li>base_node=$base_node<br><li>expected_node=$expected_node</br><li>completed_node=$completed_node</br></ul><br>
        <pre>[im_oo_tdom_explore -node $grouping_node]</pre><br><pre>[ad_print_stack_trace]</pre>"
    }

    # Extract the widths of the three bars
    regexp {([0-9\-\.]+)} [$base_node getAttribute "svg:width"] match base_width
    regexp {([0-9\-\.]+)} [$completed_node getAttribute "svg:width"] match completed_width
    regexp {([0-9\-\.]+)} [$expected_node getAttribute "svg:width"] match expected_width

    set epoch_per_x [expr ($main_project_end_date_epoch - $main_project_start_date_epoch) / ($end_date_x - $start_date_x)]

    # Advance the y postition y_dist for every row
    set y_offset [expr $base_y_offset + $row_cnt * $y_dist]
    set x_offset [expr $base_x_offset + ($start_date_epoch - $main_project_start_date_epoch) / $epoch_per_x]

    # Move the grouping to the x/y offset position
    foreach child [$grouping_node childNodes] {

	# Delete the "svg:title" tag. Tags are used to identify
	# template nodes, which need to be deleted afterwards
	set name [$child nodeName]
	if {"svg:title" == $name} { [$child parentNode] removeChild $child }

	# Move the element to the right x/y position
	im_oo_page_type_gantt_grouping_move -node $child -offset_list [list $x_offset $y_offset]
    }

    # Set the width of the bars
    set base_width [expr ($end_date_epoch - $start_date_epoch) / $epoch_per_x]
    $base_node setAttribute "svg:width" "${base_width}cm"

    set completed_width [expr $base_width * $percent_completed / 100.0]
    $completed_node setAttribute "svg:width" "${completed_width}cm"

    set expected_width [expr $base_width * $percent_expected / 100.0]
    $expected_node setAttribute "svg:width" "${expected_width}cm"

    ns_log Notice "im_oo_page_type_gantt_move_scale: end_date_node=$end_date_node"
    if {"" != $end_date_node} {
	regexp {([0-9\-\.]+)} [$end_date_node getAttribute "svg:width"] match end_date_width
	regexp {([0-9\-\.]+)} [$base_node getAttribute "svg:x"] match base_x
	set end_date_x [expr $base_x + $base_width - $end_date_width / 2]
	$end_date_node setAttribute "svg:x" "${end_date_x}cm"

	ns_log Notice "im_oo_page_type_gantt_move_scale: end_date: end_date_x=$end_date_x"


    }
}


ad_proc im_oo_page_type_gantt {
    -page_node:required
    -insert_node:required
    -parameters:required
    {-list_sql ""}
    {-page_sql "" }
    {-page_name "undefined"}
} {
    Takes as input a page node from the template with
    a table and a sql parameter in the "notes".
    It interprets the second row of the first table as
    a template and replaces this row with lines for 
    each of the SQL results.<br>
    Expected data structures: The "list" page requires 
    a table with two rows:
    <ul>
    <li>The title row and
    <li>The data row with @var_name@ variables
    <li>The page also needs to provide a "list_sql" argument
        in the page comments that will be used to create
        the data to be shown.
    </ul>
} {
    # ------------------------------------------------------------------
    # Constants & Arguments

    # Default number of table rows per page, may be overwritten by list_max_rows parameter
    set list_max_rows 10

    # Initialize the on_track_status (green, yellow, red)
    set on_track_status "green"
    set param_hash(on_track_status) $on_track_status

    # Write parameters to local variables
    array set param_hash $parameters
    # 120517 fraber: We expect that there was a template page before
    # set template_param_list [im_oo_page_extract_templates -page_node $page_node]
    # array set param_hash $template_param_list
    # ns_log Notice "im_oo_page_type_gantt: page_name='$page_name', template_params=$template_param_list"
    foreach var [array names param_hash] { set $var $param_hash($var) }

    # Make sure there is a SQL for the project phases/tasks
    if {"" == $list_sql} {
        ad_return_complaint 1 "<b>'$page_name': No list_sql specified in gantt page</b>:<br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Check the page_sql statement and perform substitutions
    if {"" == $page_sql} { set page_sql "select 1 as one from dual" }
    if {[catch {
	eval [template::adp_compile -string $page_sql]
	set page_sql $__adp_output
	set page_sql [eval "set a \"$page_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>Gantt: '$page_name': Error substituting variables in page_sql statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Perform substitutions on the list_sql statement
    if {[catch {
	eval [template::adp_compile -string $list_sql]
	set list_sql $__adp_output
	set list_sql [eval "set a \"$list_sql\""]
    } err_msg]} {
        ad_return_complaint 1 "<b>Gantt: '$page_name': Error substituting variables in SQL statement</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
        ad_script_abort
    }

    # Make a copy of the entire page.
    # We may have to generate more then one page
    set template_xml [$page_node asXML]

    # ------------------------------------------------------------------
    # Start processing the template

    # Loop through all repetitions
    db_foreach page_sql $page_sql {

	# Parse the template in order to create a "fresh" XML tree.
	# We are going to use this tree to insert rows into the first list.
        set page_doc [dom parse $template_xml]
        set page_root [$page_doc documentElement]

	set row_cnt 0
	set total_row_cnt 0
	set first_page_p 1
	if {[catch {
	    db_foreach list_sql $list_sql {
		ns_log Notice "im_oo_page_type_gantt: looping through list_sql"

		if {"" == $start_date_epoch || "" == $end_date_epoch} {
		    ns_log Error "im_oo_page_type_gantt: Found entry with empty start_date_epoch or $end_date_epoch"
		    continue
		}
		
		# ------------------------------------------------------------------
		# Setup a new page.
		# Execute this code either if we are on the very first page or
		# if we have to start a new page because of a long table.
		if {$row_cnt >= $list_max_rows || $first_page_p} {
		    
		    # Close the previous page, add it to the Impress document and start a new one.
		    if {0 == $first_page_p} {
			# Render the new page with the additional table rows as XML
			# and apply the OpenACS template engine in order to replace variables.
			set page_xml [$page_root asXML]
			if {[catch {
			    eval [template::adp_compile -string $page_xml]
			    set xml $__adp_output
			} err_msg]} {
			    ns_log Error "im_oo_page_type_gantt: '$page_name': Error substituting variables</b>: $err_msg"
			    ad_return_complaint 1 "<b>Gantt: '$page_name': Error substituting variables</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
			    ad_script_abort
			}
			
			# Parse the new slide and insert into OOoo document
			set result_doc [dom parse $xml]
			set result_root [$result_doc documentElement]

			# Get the parent of the insert_node and insert before that node.
			set page_container [$insert_node parentNode]
			$page_container insertBefore $result_root $insert_node
		    }
		    
		    # Now we are not on the first page anymore...
		    set first_page_p 0
		    
		    # Create a fresh XML tree again for the next page and reset the row counter
		    set page_doc [dom parse $template_xml]
		    set page_root [$page_doc documentElement]
		    set row_cnt 0
		    
		    # Check if the extract_template found the "green_bar" template
		    # This template will be used to render the gantt bars.
		    if {![info exists green_bar]} {
			ad_return_complaint 1 "<b>im_oo_page_type_gantt '$page_name'</b>:<br>
			The page should have at least one 'group' of objects with title 'green_bar'.<br>"
			ad_script_abort
		    }

		    # yellow_bar and red_bar are optional
		    if {![info exists yellow_bar]} { set yellow_bar $green_bar }
		    if {![info exists red_bar]} { set red_bar $green_bar }
		    
		    # Calculate some offsets in order to calculate Gantt bar position
		    set green_xml [$green_bar asXML]
		    set yellow_xml [$yellow_bar asXML]
		    set red_xml [$red_bar asXML]
		    
		    # Search for the start and end markers for the timeline
		    set text_box_list [im_oo_select_nodes $page_root "draw:frame"]
		    set left_box ""
		    set right_box ""
		    foreach node $text_box_list {
			set text [string trim [string tolower [im_oo_to_text -node $node]]]
			ns_log Notice "im_oo_page_type_gantt: text='$text'"
			switch $text {
			    "@main_project_start_date_pretty@" { set left_box $node }
			    "@main_project_end_date_pretty@" { set right_box $node }
			}
		    }
		    if {"" == $left_box || "" == $right_box} {
			ad_return_complaint 1 "<b>im_oo_page_type_gantt '$page_name'</b>:<br>
		    Could not find two text boxes with the text 'main_project_start_date_pretty'=$left_box and 'main_project_end_date_pretty'=$right_box.<br><pre>[ad_print_stack_trace]</pre>"
			ad_script_abort
		    }
		    set left_box_offset [im_oo_page_type_gantt_grouping_x_y_offset -node $left_box]
		    set right_box_offset [im_oo_page_type_gantt_grouping_x_y_offset -node $right_box]
		    set start_date_x [expr [lindex $left_box_offset 0] + 1.0]
		    set end_date_x [expr [lindex $right_box_offset 0] + 3.8]
		    set top_y [expr ([lindex $left_box_offset 1] + [lindex $right_box_offset 1]) / 2.0]
		    set epoch_per_x [expr ($main_project_end_date_epoch - $main_project_start_date_epoch) / ($end_date_x - $start_date_x)]
		    ns_log Notice "im_oo_page_type_gantt: epoch_per_x: $epoch_per_x = expr ($main_project_end_date_epoch - $main_project_start_date_epoch) / ($end_date_x - $start_date_x)"

		    # Show the today_bar at the right x-location
		    set line_node_list [im_oo_select_nodes $page_root "draw:g"]
		    foreach line_node $line_node_list {
                        set text [string trim [string tolower [im_oo_to_title -node $line_node]]]
                        ns_log Notice "im_oo_page_type_gantt: line_node: text='$text'"
                        switch $text {
                            "today_bar" { 
				set today_bar_base_x [lindex [im_oo_page_type_gantt_grouping_x_y_offset -node $line_node] 0]
				set today_bar_x [expr $today_bar_base_x + ($today_epoch - $main_project_start_date_epoch) / $epoch_per_x + 0.43]
				im_oo_page_type_gantt_grouping_move -node $line_node -offset_list [list $today_bar_x 0]
			    }
                        }
                    }
		}

		# ------------------------------------------------------------------
		# Replace placeholders in the OpenOffice template row with values
		
		# Pull out the right template according to "color"
		switch [string tolower $on_track_status] {
		    "yellow" { set gantt_bar_xml $yellow_xml }
		    "red" { set gantt_bar_xml $red_xml }
		    default { set gantt_bar_xml $green_xml }
		}
		
		if {[catch {
		    eval [template::adp_compile -string $gantt_bar_xml]
		    set grouping_xml $__adp_output
		} err_msg]} {
		    ad_return_complaint 1 "<b>'$page_name': Error substituting gantt template variables</b>:
		<pre>$err_msg\n$green_xml</pre><br><pre>[ad_print_stack_trace]</pre>"
		    ad_script_abort
		}
		
		# Parse the new grouping and insert into OOoo document
		set new_grouping_doc [dom parse $grouping_xml]
		set new_grouping_root [$new_grouping_doc documentElement]

		# Move the grouping into the correct x/y position.
		im_oo_page_type_gantt_move_scale \
		    -grouping_node $new_grouping_root \
		    -gantt_name $phase_name \
		    -page_name $page_name \
		    -base_x_offset $green_bar_x_offset \
		    -base_y_offset $green_bar_y_offset \
		    -start_date_x $start_date_x \
		    -end_date_x $end_date_x \
		    -start_date_epoch $start_date_epoch \
		    -end_date_epoch $end_date_epoch \
		    -main_project_start_date_epoch $main_project_start_date_epoch \
		    -main_project_end_date_epoch $main_project_end_date_epoch \
		    -row_cnt $row_cnt \
		    -y_dist $y_dist \
		    -percent_completed $percent_completed_pretty \
		    -percent_expected $percent_expected_pretty
		
		$page_root insertBefore $new_grouping_root [$page_root firstChild]

		
		incr row_cnt
		incr total_row_cnt
	    }
	} err_msg]} {
	    ad_return_complaint 1 "<b>Gantt '$page_name': Error evaluating list_sql</b>:<br><pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
	    ad_script_abort
	}

	# ------------------------------------------------------------------
	# The last page of the list. This can also be the very first page with short lists.

	# Delete the template nodes from the page
	im_oo_page_delete_templates -page_node $page_root

	# Apply the OpenACS template engine
	set page_xml [$page_root asXML]
        if {[catch {
            eval [template::adp_compile -string $page_xml]
            set xml $__adp_output
        } err_msg]} {
            ad_return_complaint 1 "<b>Gantt: '$page_name': Error substituting variables</b>:<pre>$err_msg</pre><br><pre>[ad_print_stack_trace]</pre>"
            ad_script_abort
        }

	# Skip the Gantt if there is no task
	if {0 != $total_row_cnt} {
	    # Parse the new slide and insert into OOoo document
	    set result_doc [dom parse $xml]
	    set result_root [$result_doc documentElement]
	    set page_container [$insert_node parentNode]
	    $page_container insertBefore $result_root $insert_node
	}

	# End looping through multiple pages
    }
}

