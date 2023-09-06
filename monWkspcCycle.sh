#!/bin/bash
#this script is completely unrelated to the other one.
#However, it is very nice.
#when you run it, it moves the current workspace to the next monitor in the list.
#Add a keybind to this script in ~/.i3/config so that you can do it with a keypress
currentWkspc="$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused==true).num')"
currentMon="$(i3-msg -t get_outputs | jq -r ".[] | select(.current_workspace == \"$currentWkspc\") | .name")"
readarray -t activeMons <<< "$(xrandr --listactivemonitors | awk '{print($4)}' | tail -n +2)"
activeMons+=( "${activeMons[0]}" )
found="false"
for mon in "${activeMons[@]}"; do
    [[ "$found" == "true" && "$mon" != "$currentMon" ]] && exec i3-msg "workspace number $currentWkspc, move workspace to output $mon"
    [[ "$mon" == "$currentMon" ]] && found="true" && bash -c "i3-msg \"workspace number $currentWkspc\"" 
    #selecting current workspace will swap focus to the previous workspace you focused temporarily, because you cannot move focused windows. If there was only 1 monitor, on the next iteration, the exec will not trigger, and we will switch it back.
done
