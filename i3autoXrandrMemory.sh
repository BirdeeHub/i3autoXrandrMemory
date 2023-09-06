#!/bin/bash
#######################################################################

################################
##requires jq for json parsing##
################################
## Behaviour: 
#it will deal with any conflicts when saving by defaulting to the newest location of workspaces

#When you unplug a monitor, it saves the workspaces on it, and xrandr --auto will
#move it to the primary.
#it will then run the script at XRANDR_ALWAYSRUN_CONFIG

#When you plug in a monitor, it searches cache for what workspaces to move to it,
#it then runs the script at XRANDR_NEWMON_CONFIG for each new monitor
#it then moves the workspaces
#it then runs the script at XRANDR_ALWAYSRUN_CONFIG


##Usage:
## 1. Ensure that you have 'jq' installed on your system.
## 2. Customize the monitor configuration scripts:
##    - Set 'XRANDR_NEWMON_CONFIG' path and write a script containing the only required command, and whatever else you want.
##    - Set 'XRANDR_ALWAYSRUN_CONFIG' to the path of the script for everything else (optional).
## 3. Set the location of the .json file that caches the workspace info.
## 4. Configure the udev rule

#Instructions for the above usage steps below:

##XRANDR_NEWMON_CONFIG gets run 1 time per monitor plugged in,
## with the xrandr output of the monitor as the argument

XRANDR_NEWMON_CONFIG=/home/<your_username>/.i3/configXrandrByOutput.sh

##an example config might look like this:

### #!/bin/bash
### if [[ $1 == "HDMI-1" ]]; then
###     ##required command that specifies the new display should extend, rather than duplicate.
###     xrandr --output HDMI-1 --left-of eDP-1
### fi

## notice that the output name is passed in as argument $1
## the only thing you must put in this config rather than the other one is
# a command to tell i3 that the new monitor is to extend this one, not duplicate it.

#######################################################################

#keep in mind that it will only run the above script on displays it registers as new.
#i.e. it now shows up after the script runs xrandr --auto, and it did not before.

#This script is provided the final list of active display output names as arguments, 
#for you to run any other config it is run at the end after the moving has completed.

XRANDR_ALWAYSRUN_CONFIG=/home/<your_username>/.i3/configPrimaryDisplay.sh

##an example config might look like this:

### #!/bin/bash
### for mon in "$@"; do
###     if [[ $mon == "HDMI-1" ]]; then
###         xrandr --output HDMI-1 --mode 1920x1080
###         xrandr --output HDMI-1 --rate 50.00
###     fi
### done

#######################################################################

#the script makes and uses this .json file. set it to an appropriate directory
json_cache_path=/home/<your_username>/.i3/monwkspc.json

#######################################################################
#sudo nano /etc/udev/rules.d/95-monitor-hotplug.rules

#put the following in the file (i only have 1 monitor port, so only 1 device for me)
#you may need to edit display and/or the card number to suit your needs, as well as the usernames and/or path to script

#KERNEL=="card0", SUBSYSTEM=="drm", ENV{DISPLAY}=":0", ENV{XAUTHORITY}="/home/<your_username>/.Xauthority", RUN+="/home/<your_username>/.i3/i3autoXrandrMemory.sh"

#(replace the thing after RUN with the path to your i3autoXrandrMemory.sh copy)

#then run:
#sudo udevadm control --reload
#######################################################################
#######################################################################
# And here is the script:
#######################################################################


#Helper functions for getting and parsing info
check_intersection() {
    local arr1=("$1")  # First argument is array1
    local arr2=("$2")  # Second argument is array2
    for item1 in "${arr1[@]}"; do
        for item2 in "${arr2[@]}"; do
            if [[ "$item1" == "$item2" ]]; then
                return 0  # Element found, return success
            fi
        done
    done
    return 1  # No intersection, return failure
}
remove_by_mon() {
    local input="$1"
    local mon="$2"
    local result
    result="$(echo "$input" | jq --arg mon "$mon" -e 'map(select(.mon != $mon))')"
    if [ $? -eq 0 ]; then
        echo "$result"
        return 0  # Return success (0) since jq command succeeded
    else
        return 1  # Return non-zero value (indicating an error) since jq command failed
    fi
}
replace_json_nums() {
    local json="$1"
    local mon="$2"
    local -a new_nums=("${@:3}")
    # Convert the Bash array to a JSON array
    local new_nums_json=$(printf '%s,' "${new_nums[@]}")
    new_nums_json="[${new_nums_json%,}]"
    # Use jq to replace the "nums" array for the specified "mon"
    updated_json=$(jq --arg mon "$mon" --argjson new_nums "$new_nums_json" '
        map(if .mon == $mon then .nums = $new_nums else . end)
    ' <<< "$json")
    echo "$updated_json"
}
remove_elements() { # remove_elements in _______ from _________
    local -n array1="$1"  # Reference to the first array
    local -n array2="$2"  # Reference to the second array
    local result=()       # Resulting array without matching elements
    for item2 in "${array2[@]}"; do
        local found=false
        for item1 in "${array1[@]}"; do
            if [[ "$item2" == "$item1" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            result+=("$item2")
        fi
    done
    echo "${result[@]}"
}

#gather info before and after xrandr --auto
i3msgOUT="$(i3-msg -t get_workspaces)"
initial_mons=()
while read -r line; do
    initial_mons+=("$line")
done <<< "$(xrandr --listactivemonitors | awk '{print($4)}' | tail -n +2)"
xrandr --auto
final_mons=()
while read -r line; do
    final_mons+=("$line")
done <<< "$(xrandr --listactivemonitors | awk '{print($4)}' | tail -n +2)"
gonemon=()
for initmon in "${initial_mons[@]}"; do
    found=false
    for finmon in "${final_mons[@]}"; do
        if [[ "$initmon" == "$finmon" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == "false" ]]; then
        gonemon+=("$initmon")
    fi
done
newmon=()
for finmon in "${final_mons[@]}"; do
    found=false
    for initmon in "${initial_mons[@]}"; do
        if [[ "$finmon" == "$initmon" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == "false" ]]; then
        newmon+=("$finmon")
    fi
done
#re-format info to appropriate json for turning into commands when needed
for mon in "${gonemon[@]}"; do
    filtered_data=$(echo "$i3msgOUT" | jq -M "map(select(.output == \"$mon\"))")
    nums=$(echo "$filtered_data" | jq -r '[.[].num]')
    result+='{ "mon": "'$mon'", "nums": '"$nums"' }'
done
result=$(echo "$result" | jq -s -c)
#Filter the cache, then append it and save it.
if [[ -e $json_cache_path && -s $json_cache_path ]]; then
    cacheresult="$(cat $json_cache_path)"
    if [[ -n "$cacheresult" ]]; then
        #old monitor cache for newly closed windows? Remove them from cache before we add new info for it later.
        for mon in "${gonemon[@]}"; do
            cacheresult="$(remove_by_mon "$cacheresult" "$mon")"
        done
    fi
    if [[ -n $cacheresult ]]; then
        readarray -t mons_array <<< "$(echo "$cacheresult" | jq -r '.[].mon')"
        if [[ -n "${mons_array[@]}" ]]; then
            for mon in "${mons_array[@]}"; do
                #also, if the workspace was moved to a different monitor, and then you unplug it, 
                #remove the workspace from the lists for other windows to avoid conflicts
                readarray -t cachenums_array <<< "$(echo "$cacheresult" | jq -r ".[] | select(.mon == \"$mon\") | .nums[]")"
                readarray -t nums_array <<< "$(echo "$result" | jq -r '.[].nums[]')"
                if [[ "${#nums_array[@]}" -gt 0 && "${nums_array[0]}" != "" && "${#cachenums_array[@]}" -gt 0 && "${cachenums_array[0]}" != "" ]]; then
                    if [[ $(check_intersection "${cachenums_array[@]}" "${nums_array[@]}") -eq 0 ]]; then
                        newnums_array=($(remove_elements nums_array cachenums_array))
                        cacheresult=$(replace_json_nums "$cacheresult" "$mon" "${newnums_array[@]}")
                    fi
                fi
            done
        fi
    fi
    #Combine result and cache appropriately
    cacheresult=${cacheresult%']'}
    cacheresult=${cacheresult#'['}
    result=${result%']'}
    result=${result#'['}
    [[ -n  "$result" && -n "$cacheresult" ]] && result+=","
    [[ -n "$cacheresult" ]] && result+=$cacheresult
    result="$(echo "[$result]" | jq -c)"
fi
#save the new cache
echo "$result" > $json_cache_path
#and now to move them back.
#using newmon and monwkspc.json, do extra monitor setups and then workspace moves for each newmon
workspace_commands=()
currentWkspc="$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num')"
workspaceChanged="false"
for mon in "${newmon[@]}"; do
    [[ -e $XRANDR_NEWMON_CONFIG && -s $XRANDR_NEWMON_CONFIG ]] && bash -c "$XRANDR_NEWMON_CONFIG \"$mon\""
    readarray -t nums_array <<< "$(echo "$result" | jq -r ".[] | select(.mon == \"$mon\") | .nums[]")"
    for num in "${nums_array[@]}"; do
        workspace_commands+=("$(echo "i3-msg \"workspace number $num, move workspace to output $mon\";")") 
    done
    #if we are focusing the very first workspace moved, change that so we can move it.
    if [[ "$currentWkspc" == "${nums_array[0]}" && "$workspaceChanged" == "false" ]]; then
        workspaceChanged="true"
        bash -c "i3-msg \"workspace number "${nums_array[0]}"\""
    fi
done

for cmd in "${workspace_commands[@]}"; do
    echo "$cmd" 
    bash -c "$cmd"
done
[[ -e $XRANDR_ALWAYSRUN_CONFIG && -s $XRANDR_ALWAYSRUN_CONFIG ]] && bash -c "$XRANDR_ALWAYSRUN_CONFIG ${final_mons[@]}"
