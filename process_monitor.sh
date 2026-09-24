#!/bin/bash

############################################################################################
## Description: Script to identify if the input process is running on the system or not
##              Supports alias and user filtering. It shows also a JSON output
##
##              List of standard processes typically found on Linux:
##                 - Cron: /usr/sbin/cron, /usr/sbin/crond
##                 - SSH: /usr/sbin/sshd (note: /usr/bin/ssh is the client)
##                 - Syslog: /usr/sbin/syslogd, /usr/sbin/rsyslogd, /usr/sbin/syslog-ng
##
## Author: Matteo Z.
############################################################################################

print_usage() {
    cat << EOF

DESCRIPTION:
    Script to identify if the input process is running on the system or not
    Supports alias and user filtering. It shows also a JSON output

USAGE:
    $0 [<options>]

OPTIONS:
    -F <file>     Specifies the file containing processes to monitor
    -P <list>     Specifies processes directly from command line
    -J            Shows output in JSON format
    -h            Shows this help message

PROCESS FORMAT:

    proc=process_name[,alternative_name]:alias=label:user=username:ppid=parent_pid:min=<min>:max=<max>

    - proc=    : process name to search for (required)
                 Can be simple name: proc=nginx
                 Can be full command with arguments: proc=sapstart pf=/path/to/profile
                 Multiple comma-separated names search for alternatives (e.g., proc=cron,crond)
    - alias=   : alternative label for the process (optional)
    - user=    : filters by this specific user (optional)
    - ppid=    : filters by this specific Parent PID (optional)
    - min=     : set a minimum of process (optional)
    - max=     : set a maximum of process (optional)

EXAMPLES:

    # From file
    $0 -F /tmp/processes.txt

    # From command line (processes separated by %)
    $0 -P "proc=nginx%proc=mysql:alias=database:user=mysql%proc=apache2:alias=webserver:ppid=1"

    # With alternative processes
    $0 -P "proc=syslogd,rsyslogd,syslog-ng:alias=syslog"

    # With full command line (for processes with specific arguments)
    $0 -P "proc=sapstart pf=/usr/sap/SMA/SYS/profile/SMA_ASCS01:alias=sap_ascs01:user=smaadm:min=2:max=3"

    # Multiple parameters - empty segments (%%) are automatically ignored
    $0 -P "proc=nginx" -P "proc=mysql%%%proc=sshd"

    # Both sources with JSON output
    $0 -F /tmp/processes.txt -P "proc=redis:alias=cache" -J

FILE FORMAT (-F):

    Each line must contain a process in the format:
    proc=name[:alias=label[:user=username]]

    Example file:
    
        proc=nginx
        proc=mysql:alias=database:user=mysql:max=3
        proc=apache2:alias=webserver
        proc=redis:alias=cache:user=redis:ppid=1
        proc=cron,crond:alias=cron_service:min=2
        proc=syslogd,rsyslogd,syslog-ng:alias=syslog

EOF
    exit 1
}


print_error() {
    echo "ERROR!! $1"; exit 1
}


clean_process_string() {
    # function to clean the process string by removing empty segments
    input="$1"

    # to remove multiple consecutive '%'
    input="$(echo "$input" | sed 's/%%\+/%/g')"

    # to remove leading and trailing '%'
    input="$(echo "$input" | sed 's/^%//; s/%$//')"

    # to remove spaces after '%'
    input="$(echo "$input" | sed 's/%[[:space:]]*/%/g')"

    # echo -n "Cleaned string -> "
    echo "$input"
}


parse_process_string() {
    # function to parse the process string: extracts the values of process name, alias, user and PPID. It prints them in the format proc|alias|user
    input="$1"
    proc_name="$(echo "$input" | sed -n 's/.*proc=\([^:]*\).*/\1/p')"
    proc_alias="$(echo "$input" | sed -n 's/.*alias=\([^:]*\).*/\1/p')"
    proc_user="$(echo "$input" | sed -n 's/.*user=\([^:]*\).*/\1/p')"
    proc_ppid="$(echo "$input" | sed -n 's/.*ppid=\([^:]*\).*/\1/p')"
    proc_min="$(echo "$input" | sed -n 's/.*min=\([^:]*\).*/\1/p')"
    proc_max="$(echo "$input" | sed -n 's/.*max=\([^:]*\).*/\1/p')"

    [[ -z "$proc_min" ]] && proc_min=1
    [[ -z "$proc_max" ]] && proc_max=1

    # echo -e "Process string parsed:\nProc name -> $proc_name - Alias -> $proc_alias - User -> $proc_user - PPID -> $proc_ppid - Min -> $proc_min - Max -> $proc_max"

    [[ -z "$proc_name" ]] && return 1

    echo "$proc_name|$proc_alias|$proc_user|$proc_ppid|$proc_min|$proc_max"
}


check_cmd_processes() {
    # function to check the processes from command line
    for element in "${cmd_procs[@]}"; do
        # echo "CMD element -> $element"
        proc_string="$(clean_process_string "$element")"

        # to check that the string is not empty after cleanup
        [[ -z "$proc_string" ]] && continue

        # to split processes using '%' as delimiter
        IFS='%' read -ra proc_array <<< "$proc_string"

        for el in "${proc_array[@]}"; do
            # echo "Single element -> $el"

            if parsed="$(parse_process_string "$el")"; then
                procsToCheck+=( "$parsed" )
                # echo "Process string to check: ${procsToCheck[@]}"
            else
                if [[ "$json_flag" == false ]];then
                    echo -e "\e[1;33mWARNING!!\e[0m Process ignored (invalid format): $el"
                fi
            fi
        done
    done
}


check_file_processes() {
    # function to check the processes from the specified file
    count=0

    if [[ ! -f "$file_procs" ]]; then
        print_error "The file \"$file_procs\" does not exist!!"
    fi

    # to check that the file is readable
    if [[ ! -r "$file_procs" ]]; then
        print_error "The file \"$file_procs\" is not readable!!"
    fi

    # to read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # echo "Line $count -> $line"
        ((count++))

        # to ignore empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            if parsed="$(parse_process_string "$line")"; then
                procsToCheck+=( "$parsed" )
                # echo "Procs string to check: ${procsToCheck[@]}"
            else
                if [[ "$json_flag" == false ]];then
                    echo -e "\e[1;33mWARNING!!\e[0m Line $count ignored (invalid format): $line"
                fi
            fi
        fi
    done < "$file_procs"
}


check_process_existence() {
    # function to check if the process is running on the system (0 if process exists, 1 otherwise)
    proc_name="$1"; proc_user="$2"; proc_ppid="$3"; all_matches=""; count=0; found=false

    # to split processes name using ',' as delimiter (because there can be multiple alternatives)
    IFS=',' read -ra proc_array <<< "$proc_name"

    for el in "${proc_array[@]}"; do
        # echo "Checking process -> $el"

        # Search all matching lines. Full commands are matched as literal strings;
        # simple process names keep word matching to avoid partial matches.
        if [[ "$el" =~ [[:space:]/=] ]]; then
            match="$(printf '%s\n' "$ps_info" | grep -F -- "$el")"
        else
            match="$(printf '%s\n' "$ps_info" | grep -F -w -- "$el")"
        fi

        # if nothing found, continue with the next process name
        [[ -z "$match" ]] && continue

        # iterate over all matching lines (there can be multiple identical processes)
        while IFS=',' read -r ps_user ps_ppid ps_cmd; do
            [[ -n "$proc_user" && "$proc_user" != "$ps_user" ]] && continue
            [[ -n "$proc_ppid" && "$proc_ppid" != "$ps_ppid" ]] && continue

            ((count++))
            found=true
            ps_cmd="$(echo "$ps_cmd" | sed 's/"//g')"
            all_matches+="${all_matches:+, }$ps_cmd"
        done < <(printf '%s\n' "$match")

        if [[ "$found" == true ]]; then
            echo "$el|$all_matches|$count"; break
        fi
    done

    if [[ "$found" == true ]]; then
        return 0
    else
        return 1
    fi
}


is_count_in_range() {
    count="$1"; min="$2"; max="$3"

    [[ "$min" =~ ^[0-9]+$ ]] || min=1
    [[ "$max" =~ ^[0-9]+$ ]] || max=1

    (( count >= min && count <= max ))
}


extract_process_alias() {
    # function to extract the process alias from the string process name (e.g. 'nginx -g daemon off;' -> 'nginx'; '/usr/sbin/sshd -D' -> 'sshd')
    input="$1"
    # to removes all leading whitespace and trims everything after the first whitespace
    input="$(echo "$input" | sed 's/^[[:space:]]*//')"
    input="${input%%[[:space:]]*}"
    # echo "New input: $input"

    if [[ "$input" == */* ]]; then
        basename "$input"
    else
        echo "$input"
    fi
}


json_escape() {
    input="$1"
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    input="${input//$'\t'/\\t}"
    printf '%s' "$input"
}


json_output() {
    # function to show the output in JSON format
    json_data="["
    flag=true

    for element in "${procsToCheck[@]}"; do
        IFS='|' read -r proc_name proc_alias proc_user proc_ppid proc_min proc_max <<< "$element"
        status=0
        proc_found=""; all_matches=""; count=0

        if proc_info="$(check_process_existence "$proc_name" "$proc_user" "$proc_ppid")"; then
            IFS='|' read -r proc_found all_matches count <<< "$proc_info"
            if is_count_in_range "$count" "$proc_min" "$proc_max"; then
                status=1
            fi
        fi

        if [[ -z "$proc_alias" ]]; then
            if [[ -n "$proc_found" ]]; then
                proc_alias="$(extract_process_alias "$proc_found")"
            else
                proc_alias="$(extract_process_alias "$proc_name")"
            fi
        fi

        # to add a comma if not the first element
        if [[ "$flag" == false ]]; then
            json_data+=","
        fi

        flag=false
        json_data+="{\"ALIAS\":\"$(json_escape "$proc_alias")\""
        json_data+=",\"USER\":\"$(json_escape "$proc_user")\""
        json_data+=",\"STATUS\":\"$status\""
        json_data+=",\"PROCESSES\":\"$(json_escape "$all_matches")\""
        json_data+=",\"COUNT\":\"$count\""
        json_data+=",\"MIN\":\"$(json_escape "$proc_min")\""
        json_data+=",\"MAX\":\"$(json_escape "$proc_max")\"}"
    done

    json_data+="]"
    echo "$json_data"
}


standard_output() {
    # function to show output in standard format
    echo -e "\n\e[1;35m==========================================="
    echo "         PROCESS MONITORING REPORT"
    echo -e "===========================================\e[0m"

    count_ok=0; count_ko=0

    for element in "${procsToCheck[@]}"; do
        echo
        IFS='|' read -r proc_name proc_alias proc_user proc_ppid proc_min proc_max <<< "$element"
        
        [[ -z "$proc_alias" ]] && proc_alias="$proc_name"

        if proc_info="$(check_process_existence "$proc_name" "$proc_user" "$proc_ppid")"; then
            IFS='|' read -r proc_found all_matches count <<< "$proc_info"

            if is_count_in_range "$count" "$proc_min" "$proc_max"; then
                echo -e "\e[0;32m[OK] $proc_alias: ACTIVE\e[0m"
                ((count_ok++))
            else
                echo -e "\e[0;31;1m[KO] $proc_alias: OUT OF RANGE\e[0m"
                ((count_ko++))
            fi

            echo -e "    - Process count: $count"
            echo -e "    - Command: $all_matches"

            [[ "$proc_name" == *,* ]] && echo -e "    - Process found: $proc_found"
            [[ -n "$proc_user" ]] && echo -e "    - User: $proc_user"
            [[ -n "$proc_ppid" ]] && echo -e "    - PPID: $proc_ppid"

            echo -e "    - Min: $proc_min"
            echo -e "    - Max: $proc_max"
        else
            echo -e "\e[0;31;1m[KO] $proc_alias: NOT FOUND\e[0m"

            [[ "$proc_name" == *,* ]] && echo -e "    - Processes searched: $proc_name"
            [[ -n "$proc_user" ]] && echo -e "    - Searched for user: $proc_user"
            [[ -n "$proc_ppid" ]] && echo -e "    - Searched for PPID: $proc_ppid"

            ((count_ko++))
        fi
    done

    echo
    echo -e "\e[1;35m==========================================="
    echo "      SUMMARY: $count_ok active - $count_ko not found"
    echo -e "===========================================\e[0m\n"
}


########## MAIN ##########

script_name="$(basename "$0")"
json_flag=false
cmd_procs=()
procsToCheck=()
# to list all system processes without the used commands to filtered ('ps' and 'awk') and the script name
ps_info="$(ps -ww -eo user,ppid,args --no-headers 2> /dev/null | awk -v script="$script_name" '{
    for (i=3; i<=NF; i++) cmd=(i==3 ? $i : cmd" "$i);
    if (cmd~/^ps / || cmd~/^awk / || index(cmd, script) > 0) next;
    printf "%s,%s,%s\n", $1,$2,cmd;
    cmd="";
}')"
# echo -e "SYSTEM PROCESSES:\n$ps_info\n"

while getopts ":P:F:Jh" opt; do
    case "$opt" in
        P)  cmd_procs+=( "${OPTARG}" ) ;;
        F)  file_procs="${OPTARG}" ;;
        J)  json_flag=true ;;
        h)  print_usage ;;
        *)  print_error "You have done something wrong!! Use \"-h\" for help" ;;
    esac
done

if [[ $# -eq 0 ]]; then
    print_usage
fi

if [[ ${#cmd_procs[@]} -gt 0 ]]; then
    check_cmd_processes
fi

if [[ -n "$file_procs" ]]; then
    check_file_processes
fi

# if there are no processes to monitor ...
if [[ ${#procsToCheck[@]} -eq 0 ]]; then
    if [[ "$json_flag" == true ]]; then
        echo "[]"; exit 0
    else
        print_error "No processes to monitor found!"
    fi
fi

# to show the output in the required format
if [[ "$json_flag" == true ]]; then
    json_output
else
    standard_output
fi