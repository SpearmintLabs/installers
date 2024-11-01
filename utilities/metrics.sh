#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    OS_VERSION_ID=$(echo "$VERSION_ID" | cut -d. -f1)
else
    echo "Unable to detect operating system. Exiting."
    exit 1
fi

apt install -y net-tools

# Collect OS information
os_info="${OS_NAME} ${OS_VERSION_ID}"

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
