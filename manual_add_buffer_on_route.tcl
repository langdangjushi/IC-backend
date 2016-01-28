#========= vars declare =========
# Recommend you to open console in layout window(you have already seem it in main window)
# set drive_pin [list ] ; please note this var is the drive pins of your nets which violate \
# transition , recommend you to set it in another file; list type

set buf_ref BUFH_X11M_A9TR_C34 ; #your buf reference name 
# do not touch following vars  !!!!!!!!!!!!!!!!!!!!!!!!
# to keep things simple(I dont want to use namespace), use some global vars to maintain state;  
# but global vars are easy to cause bugs 
set i 0 ; # drive_pin list iterator index 
set j 1 ; # buffer suffix and port name suffix
set driver "" ;# current driver pin ; string type
set net "" ;# net of current driver pin; collection type
set shape "" ;# net shape of current net; collection type
set via "" ;# via of current net ; collection type
set loader "" ; # load pin of current net ; collection type
array unset point2pin 
array set point2pin {dummy 0} ;# a map of pin points to pin name
set polygon "" ;# whole bunch of shape,via,pin,polygon 
set buffering_pin "" ;# loader pin that need buffering; list type
set buffering_polygon "" ;# Em.. I dont know how to explain this, 
set date [sh date +%m%d] ;# used for cell name and port name
set buf_prefix "fix_tran$date" ;# cell prefix
set die_polygon [get_attribute [get_die_area] boundary]
set center_point "" ;# buffer insertion point
set allwindow [gui_get_window_ids]
set index [lsearch -glob $allwindow Layout.*]
set layoutwindow [lindex $allwindow $index]

#=========== end vars declare ====================

#================= key binding ===============================
set_gui_stroke_binding Graphics 159 -tcl {find_buffering_pins %rect}
set_gui_stroke_binding Graphics 5 -tcl {manual_add_buffer_on_route }
set_gui_stroke_binding Graphics ss:5 -tcl {next}
#====end key binding,for details see the command man page===== 
#
dehighlight ; initialize ; # for first drive pin 

#=========== begin proc definition ==============
#=========================================
# initialization prepare all sorts of data
#==========================================
proc initialize {} {
    global net shape via drive_pin driver loader i layoutwindow
    set driver [lindex $drive_pin $i]
    set net [get_flat_nets -of [get_pins $driver]]
    set shape [get_net_shapes -of $net]
    set via [get_vias -of $net]
    set loader [get_flat_pins -of $net -fil direction==in]
    highlight
    create_map
    change_selection $net
    gui_zoom -window $layoutwindow -selection
} ;# end proc
#=====================================
# interate to next driver pin 
#=====================================
proc next {} {
    global drive_pin shape via i driver net loader 
    incr i
    dehighlight 
    initialize
}

#====================================================
# proc of creating a map between pin points and pin names
# ===================================================
proc create_map {} {
    global point2pin 
    global driver 
    global loader
    array unset point2pin "* *" ;# remove previous point element
    foreach_in_collection pin [get_pins "$driver $loader"] {
        set name   [get_attribute $pin full_name]
        puts $name
        set points [convert_to_polygon [get_pin_shapes -of $pin]]
        foreach point [join $points] {
            set point2pin($point) $name
        } ;# end inner foreach
    } ;# end outter foreach 
} ;# end proc

#=======================================
# highlight objects: net driver loader
#=======================================
proc highlight {} {
    global driver loader net  via
    set driver_cel [get_cells -of [get_pins $driver]]
    set loader_cel [get_cells -of [get_pins $loader]]
    gui_change_highlight -color red -collection $driver_cel
    gui_change_highlight -color blue -collection $loader_cel
    gui_change_highlight -color orange -collection [get_nets $net]
}

#======================================
# remove highlight 
#======================================
proc dehighlight {} {
    gui_change_highlight -all_colors -remove
}

#======================================================================
# combine a consecutive polygon, that is to say: remove holes in polygon 
#======================================================================
proc remove_holes_in_polygon {}  { ;# remove holes in our global polygon
    global polygon driver loader shape via  die_polygon
    set polygon ""
    set pin_shape [get_pin_shapes -of [get_pins "$driver $loader"]]
    set pin_shape_polygon [convert_to_polygon $pin_shape]
    set via_polygon [convert_via_to_polygon $via]
    set net_shape_polygon [convert_to_polygon $shape]
    set polygon [compute_polygons -bool or $pin_shape_polygon $via_polygon]
    set polygon [compute_polygons -bool or $net_shape_polygon $polygon]
    set hole_polygon [compute_polygons -bool not $die_polygon $polygon]
    set holes ""
    if { [llength $hole_polygon] > 1 } {
        foreach poly $hole_polygon {
            if { [is_polygon_area_less_10 $poly] == "true" } {
                lappend holes $poly
            } ;# end inner if
        } ;# end foreach
        #set holes [resize_polygon -size  0.002 $holes]
        set polygon [compute_polygons -bool or $polygon $holes]
    } ;# end outter if
} ;# end proc
#================================================================
# split polygon to two parts and find the pins that need buffering
#================================================================
proc find_buffering_pins { rect } {
    global driver loader polygon point2pin buffering_pin buffering_polygon
    global center_point
    # get mid point and cut polygon; note a bug exists in ICC
    puts $rect
    scan [join $rect] "%f %f %f %f" llx ury urx lly
    set midx [expr ($urx + $llx) /2]; set midy [expr ($ury + $lly)/2]
    set point [list $midx $midy]
    set center_point $point
    puts "center point $point"
    set cut_polygon "{$llx $lly} {$urx $lly} {$urx $ury} {$llx $ury} {$llx $lly}"
    # end create polygon 
    # compute consecutive net_shape via pin_shape polygon
    remove_holes_in_polygon
    if { [llength $polygon] > 1 } { 
        puts "\033\[31mError: I cann't insert buffer for you!\033\[0m"
        puts "write pin name to file .tmp_tricky_pin"
        echo $driver >> .tmp_tricky_pin.rpt
        change_selection
        return false
    } else {
        puts "Succeed! I \033\[31mmay\033\[0m insert buffer for you!"
    }
    # now use cut_polygon to cut polygon :) 
    set two_parts [compute_polygons -bool not $polygon $cut_polygon]
    # then find which part need inserting buffer, obvious the part that contains no\
    # driver pin, so we traverse both parts
    set flag 0 ; # flag that indicate driver
    foreach part $two_parts {
        set buffering_pin ""
        foreach point $part {
            set pin [lindex [array get point2pin $point] 1]
            if { $pin != "" } {
                if { [string compare $pin $driver] == 0 } {
                    set flag 1 ;# find drive
                    break
                } ;# end inner if 
                lappend buffering_pin $pin
            } ;# end outter if 
        } ;# end inner foreach 
        if { $flag == 0 } { break } ;# driver in second part
    } ;# end  outter foreach 
    set buffering_pin [lsort -unique $buffering_pin]
    set buffering_polygon [lindex $two_parts $flag]
    set cels [get_cells -of [get_pins $buffering_pin]]
    change_selection $cels 
    gui_change_highlight -color purple -collection [get_selection]
}

#===============================
# insert buffer 
#===============================
proc manual_add_buffer_on_route { } {
    global i j net shape via driver point2pin loader polygon 
    global buffering_pin buffering_polygon buf_prefix buf_ref
    global center_point date
    # check if pins are in the same hierachi
    set pin_tmp [lindex $buffering_pin 0]
    set flag 0 ;# indicate whether pins are in the same hierarchy 
    foreach pin $buffering_pin {
        if { [string compare $pin_tmp $pin] != 0 } {
            set flag 1
            break
        } ;# end if 
    } ;# end foreach 
    set buf_basename ${buf_prefix}_${i}_$j
    if { $flag == 0 } {
        insert_buffer -location $center_point -new_cell_names $buf_basename $buffering_pin $buf_ref
        regsub {/\w+/\w+$} [lindex $buffering_pin 0] "" hie
    } else { ;# pins are in different  hierarchical
        foreach pin $buffering_pin {
            disconnect_net [get_nets -of [get_pins $pin]] $pin
        }
        regsub {/\w+/\w+$} $driver "" hie
        set cell $hie/$buf_basename
        create_cell $cell $buf_ref
        set buf_input_pin [get_object_name [get_pins -of [get_cells $cell] -fil direction==in]]
        connect_pin -from  $driver -to $buf_input_pin
        connect_pin -from [get_pins -of [get_cells $cell] -fil direction==out] -to $buffering_pin  -port_name p$date${i}_$j
        set_attribute $cell origin $center_point
    }
    puts "\033\[31m insert_buffer to pins \033\[0m"; print_list $buffering_pin
    set cell $hie/$buf_basename
    change_selection [get_cells $cell]
    change_selection [get_nets -of [get_cells $cell]] -add
    update_point2pin $buf_input_pin
    incr j
} ;# end proc
#==============================
# update data point2pin 
#==============================
proc update_point2pin { pin } {
    global point2pin buffering_polygon 
    foreach point $buffering_polygon {
        set pre_pin [lindex [array get point2pin $point] 1]
        if { $pre_pin != "" } {
            set point2pin($point) $pin
        } ;# end if
    } ;# end foreach 
} ;# end proc

#=========================
# compute rectangle area
#=========================
proc compute_rectangle_area { rect } {
    scan [join [join $rect]] "%f %f %f %f" llx lly urx ury
    return [expr ($ury - $lly) * ($urx - $llx)]
}

#==================================================
# compute if this polygon area is less than 10 um^2
#==================================================
proc is_polygon_area_less_10 { poly } {
    set total_area 0
    foreach rect [convert_from_polygon -format rectangle $poly] {
        set total_area [expr $total_area + [compute_rectangle_area $rect]]
        if { $total_area >= 10 } { return false }
    }
    return true
}
        
#=====================================================
# convert vias to polygon, why ICC cann't do this? Why? 
#=====================================================
proc convert_via_to_polygon { vias } {
    set via_polygon ""
    foreach_in_collection v [get_vias $vias] {
        set bbox [get_attribute $v bbox]
        scan [join $bbox] "%f %f %f %f" llx lly urx ury
        lappend via_polygon "{$llx $lly} {$urx $lly} {$urx $ury} {$llx $ury} {$llx $lly}"
    }
    return $via_polygon
}

#==================
# print list 
#==================
proc print_list { lst } {
    foreach e $lst {
        puts $e
    } ;# end foreach
} ;# end proc



