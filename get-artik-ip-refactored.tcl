#!/usr/bin/env tclsh

namespace eval ::Deployer::Artik {

    array set cli_defaults {
        device          "/dev/ttyUSB0"
        iface           "eth0"
        is_interactive	0
    }
    array set cli_opts {}

    # -- refactor this --
    variable baud 115200
    variable opts "cs8 ixoff"

    variable login_params {}
    variable tizen_prompts {}
    variable reverse_prompt {}

    variable re_os_info ""
    variable re_prompt {(%|#\s*|\$)$}

    variable str {}

    array set sid {}
    # -- end refactor --

    # -- new --
    variable screen_cli_args {}
    variable os_specific     {}
    # -- end new --

    # Parsing command-line options
    proc parse_cli_opts {} {
        foreach a [list argv argc] {
            upvar 0 ::$a $a
        }
        foreach a [list cli_opts cli_defaults] {
            upvar 0 ::Deployer::Artik::$a $a
        }

        foreach opt $argv {
            if {[string equal $opt --interactive]} {
                set argv [lsearch -all -inline -not -exact $argv $opt]
                set cli_opts(is_interactive) 1
                incr argc -1
            } elseif {[regexp -- {^(?:--device|-d)$} $opt]} {
                set cli_opts(device) [lindex $argv [expr [lsearch $argv $opt] + 1]]
            	set argv [lsearch -all -inline -not -exact $argv $opt]
                incr argc -1
            } elseif {[regexp -- {^(?:--iface|-i)$} $opt]} {
            	set cli_opts(iface)  [lindex $argv [expr [lsearch $argv $opt] + 1]]
            	set argv [lsearch -all -inline -not -exact $argv $opt]
                incr argc -1
            }
        }

        foreach key [array names cli_defaults] {
            if {![info exists cli_opts($key)]} {
                set cli_opts($key) [lindex [array get cli_defaults $key] 1]
            }
        }
    }

    proc do {} {
        upvar 0 ::Deployer::Artik::cli_opts cli_opts
        foreach {key value} [array get cli_opts] {
            puts [format "%-20s %-20s" $key $value]
            if {[string equal $key "device"]} {
                if {[file exists $value]} {
                    puts "tty device exists!"
                } else {
                    puts "Error! Device $value doesn't exist. Aborting..."
                    exit 1
                }
            }
        }
    }

    proc setup {} {
        variable tizen_prompts
        variable login_params
        variable reverse_prompt

        variable re_os_info
        variable re_prompt

        dict set tizen_prompts {Tizen 3.0m3} "root:~> "

        # -- new --
        dict set os_specific {Tizen} {
            {Tizen 3.0m2} {
                {login_prompt}  ""
                {login_params}  {
                    {user}      "root"
                    {password}  "tizen"
                }
                {prompt}        "root:~> "
            }
        }

        dict set os_specific {Fedora} {
            {Fedora 24} {
                {login_prompt}  ""
                {login_params}  {
                    {user}      "root"
                    {password}  "root"
                }
                {prompt}        ""

            }
        }
        # -- end new --

        regsub {(.*?)(?:\)\$)$} $re_prompt {\1} re_prompt
        dict for {prompt_name prompt} $tizen_prompts {
            append re_prompt "|$prompt"
        }
        append re_prompt ")$"

        set login_params {}
        dict set login_params "Tizen 3.0" { user "root" pass "tizen" }
        dict set login_params "Fedora 24" { user "root" pass "root"  }

        set reverse_prompt {}
        dict set reverse_prompt "localhost" "Fedora 24"
        dict set reverse_prompt "artik"     "Tizen 3.0"

        append re_os_info {(?s)[\n\s.]*?(}
        foreach {os_name} [dict keys $login_params] {
            if {![string equal $os_name "Tizen 3.0"]} {
                append re_os_info "$os_name|"
            }
        }
        regsub {(.*?)\|$} $re_os_info {\1)[\n\s.]*} re_os_info

        log_user 0
    }
}

namespace eval ::Deployer::Artik::RegexpBuilder {

    namespace export re_logined_prompt

    proc re_logined_prompt {{prompt ""} {dist_prompts ""} args} {
        # Retrieve optional switches
        while {[string equal [string index [lindex $args 0] 0] "-"]}
            set switch_str [lindex $args 0]
            set args [lreplace $args 0 0]
            switch $switch_str {
                "-defaults" {
                    set use_default 
                }
            }
        }
        # Test whether proc is called with default parameters
        if {[string length $prompt] > 0} {
            # Test whether prompt is not prompt's regexp
            if {![regexp -expanded {^ .* \( .* \)\$ $} $prompt]} {
                # If it is not
                if {[uplevel 1 [info exists $dist_prompts]]} {
                    set prompt_name $prompt
                    unset prompt
                    upvar 1 $prompt_name prompt
                } else {
                    return -code error "Expected regexp string for prompt or\
                                        varname at caller stack level"
                }
            }
            # Test whether dist_prompts contains name of variable or it is not
            # a list.In second case we return create list from values of
            # ::Deployer::Artik re_prompt dict (os -> os_version -> prompt)
            if {
                (
                    ![string is list $dist_prompts] ||
                    ([llength $dist_prompts] == 1)
                ) &&
                [uplevel 1 [info exists $dist_prompts]]
            } then {
                set dist_prompts_name $dist_prompts
                unset dist_prompts
                upvar 1 $dist_prompts_name dist_prompts
            } elseif {
                !(
                    [string is list $dist_prompts] &&
                    ([llength $dist_prompts] > 1)
                )
            } then {

            }
        } else {
            unset prompt
            unset dist_prompts
            set dist_prompts {}
            variable ::Deployer::Artik::os_specific
            namespace upvar ::Deployer::Artik re_prompt prompt
            dict for {os os_dict} $::Deployer::Artik::os_specific {
                dict for {os_version os_version_dict} $os_dict {
                    dict for {os_param os_value} $os_version_dict {
                        if {[string equal $os_param "prompt"] &&
                            [string length $os_value] > 0} {
                            lappend dist_prompts $os_value
                        }
                    }
                }
            }
        }
    }

}

if {[info exists argv0] && [file tail [info script]] eq [file tail $argv0]} {
    Deployer::Artik::parse_cli_opts
    Deployer::Artik::do
}