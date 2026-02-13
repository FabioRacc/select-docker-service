#!/bin/bash

ORIGINAL_STTY_SETTINGS=$(stty -g)

function select_option {
    ESC=$( printf "\033")
    cursor_blink_on()           { printf "$ESC[?25h"; }
    cursor_blink_off()          { printf "$ESC[?25l"; }
    cursor_to()                 { printf "$ESC[$1;${2:-1}H"; }
    print_option()              { printf "  $1"; }
    print_selected()            { printf "\033[32;1m▶ $1\033[0m"; }
    get_cursor_row()            { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    key_input()                 { read -s -n3 key 2>/dev/null >&2
                                  if [[ $key = $ESC[A ]]; then echo up;    fi
                                  if [[ $key = $ESC[B ]]; then echo down;  fi
                                  if [[ $key = ""     ]]; then echo enter; fi; }
    restore_terminal_settings() { printf "\n"
                                  stty $ORIGINAL_STTY_SETTINGS 
                                  cursor_blink_on; }
    for opt; do printf "\n"; done

    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - $#))

    trap "restore_terminal_settings; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
        local idx=0
        for opt; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$opt"
            else
                print_option "$opt"
            fi
            ((idx++))
        done

        case `key_input` in
            enter) break;;
            up)    ((selected--));
                   if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
            down)  ((selected++));
                   if [ $selected -ge $# ]; then selected=0; fi;;
        esac
    done

    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $selected
}

function draw_rectangle() {
    local text="$1"
    local visible_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')

    local text_len=${#visible_text}
    local total_len=$(( text_len + 4 ))

    local line=""
    local i

    for (( i=0; i < $total_len; i++ )); do
        line="${line}═"
    done
    local upper_line="╔${line}╗"
    local botton_line="╚${line}╝"
    
    echo "$upper_line"
    echo -e "║  ${text}  ║" 
    echo "$botton_line"
}

function cleanup() {
    tput cuu $(($# + ${!#:-0}))
    tput ed
}

function select_opt {
    select_option "$@" 1>&2
    local selected_index=$?
    local temp_options=("$@")

    if [ "$selected_index" -lt "${#temp_options[@]}" ]; then
        echo "${temp_options[$selected_index]}"
    else
        echo ""
    fi

    return $selected_index
}

if docker compose version >/dev/null 2>&1; then
    docker_command="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    docker_command="docker-compose"
else
    echo "Error: Docker Compose not installed."
    exit 1
fi

# Check for the right command based on docker compose version
if docker compose version >/dev/null 2>&1; then
    docker_command="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    docker_command="docker-compose"
else
    echo "Error: Docker Compose not installed."
    exit 1
fi

# Select Service
draw_rectangle "Select Service"
mapfile -t services < <($docker_command config --services)
selected_service=$(select_opt "${services[@]}")
num_services=${#services[@]}

# Select User
cleanup $num_services 4
draw_rectangle "Log into [$selected_service] as:"
users=("user" "root")
selected_user_label=$(select_opt "${users[@]}")
num_users=${#users[@]}

# Build final command
if [[ "$selected_user_label" == "root" ]]; then
    final_command="${docker_command} exec -it $selected_service bash"
    user_name="root"
else
    final_command="${docker_command} exec -it -u 1000 $selected_service bash"
    user_name="user"
fi

# Clear and print
cleanup $num_users 4
draw_rectangle "Logged as \e[1;36m${user_name}\e[0m in ${selected_service}"

# Create temp file to save errors
error_log=$(mktemp)
# Run the Command
eval $final_command 2> "$error_log"
exit_status=$?

# Get error message
error_message=$(cat "$error_log")

# Check for errors during the command run
if [ $exit_status -ne 0 ]; then
    # Check if error message is empty, could be forced exit
    if [ -s "$error_log" ]; then
        draw_rectangle "\e[31mCONNECTION FAILED\e[0m"
        echo -e "Details Docker Error:"
        echo -e "\e[2m$error_message\e[0m"
    else
        echo -e "\n\e[33mSession closed (Exit code: $exit_status)\e[0m"
    fi
fi
