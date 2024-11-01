#!/bin/bash

border_color=$(tput setaf 4)
name_color=$(tput setaf 2)
reset_color=$(tput sgr0)

containers=$(docker ps --format "{{.Names}}|{{.Status}}|{{.Ports}}")

max_name_len=$(echo "$containers" | awk -F '|' '{print length($1)}' | sort -nr | head -n1)
max_status_len=$(echo "$containers" | awk -F '|' '{print length($2)}' | sort -nr | head -n1)
max_ports_len=$(echo "$containers" | awk -F '|' '{print $3}' | grep -oE '[0-9]{2,5}' | sort -u | tr '\n' ' ' | wc -c)

name_width=$((max_name_len > 20 ? max_name_len : 20))
status_width=$((max_status_len > 15 ? max_status_len : 15))
ports_width=$((max_ports_len > 10 ? max_ports_len : 10))

printf "${border_color}+%-$((name_width + 2))s+%-$((status_width + 2))s+%-$((ports_width + 2))s+${reset_color}\n" | tr ' ' '-'
printf "${border_color}| %-*s | %-*s | %-*s |${reset_color}\n" "$name_width" "Container Name" "$status_width" "Status" "$ports_width" "Ports"
printf "${border_color}+%-$((name_width + 2))s+%-$((status_width + 2))s+%-$((ports_width + 2))s+${reset_color}\n" | tr ' ' '-'

while IFS= read -r container; do
    container_name=$(echo "$container" | awk -F '|' '{print $1}')
    container_status=$(echo "$container" | awk -F '|' '{print $2}')
    
    container_ports=$(echo "$container" | awk -F '|' '{print $3}' | grep -oE '[0-9]{2,5}' | sort -u | tr '\n' ' ')

    printf "${border_color}| ${name_color}%-*s${reset_color} ${border_color}|${reset_color} %-*s ${border_color}|${reset_color} %-*s ${border_color}|${reset_color}\n" \
        "$name_width" "$container_name" "$status_width" "$container_status" "$ports_width" "$container_ports"

    printf "${border_color}+%-$((name_width + 2))s+%-$((status_width + 2))s+%-$((ports_width + 2))s+${reset_color}\n" | tr ' ' '-'
done <<< "$containers"
