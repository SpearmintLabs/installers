#!/bin/bash

# Collect OS information
os_info=$(uname -a)

# Collect System Specs
cpu_info=$(lscpu)
mem_info=$(free -h)
disk_info=$(df -h)
uptime_info=$(uptime -p)

# Optional: Collect other useful data, like network stats
network_info=$(ifconfig)

# URL of PHP script to send data to
url="https://spearmint.sh/dispatcher.php"

# Send collected data as a POST request
curl -X POST -d "os_info=$os_info&cpu_info=$cpu_info&mem_info=$mem_info&disk_info=$disk_info&uptime_info=$uptime_info&network_info=$network_info" "$url"
