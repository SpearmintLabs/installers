#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Detect OS and Version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    OS_VERSION_ID=$(echo "$VERSION_ID" | cut -d. -f1)
else
    echo "Unable to detect operating system. Exiting."
    exit 1
fi

if [[ "$OS_NAME" != "ubuntu" ]]; then
    echo "Warning: This script is designed to run on Ubuntu. Please use the deployer to install the correct version."
    exit 1
fi

# Check if deployment file exists
if [ ! -f "/srv/peppermint/sprmnt.txt" ]; then
    echo "Deployment file sprmnt.txt not found in /srv/peppermint."
    exit 1
fi

# Prompt for user input
read -p "Enter Main Domain: " MAIN_DOMAIN
read -p "Enter API Domain: " API_DOMAIN
read -p "Enter SECRET (press Enter to auto-generate): " SECRET
SECRET=${SECRET:-$(openssl rand -hex 16)}
read -p "Enter POSTGRES_PASSWORD (press Enter to auto-generate): " POSTGRES_PASSWORD
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}

# Check if domain is pointed to server IP
echo "Checking domain DNS settings..."
IP_ADDRESS=$(curl -s ifconfig.me)
if ! host "$MAIN_DOMAIN" | grep -q "$IP_ADDRESS"; then
    echo "Warning: $MAIN_DOMAIN does not appear to be pointed to this server's IP ($IP_ADDRESS)."
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ "$CONTINUE" != "y" ]]; then
        exit 1
    fi
fi

# Docker Installation Steps
echo "Removing old/conflicting Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y $pkg
done

# Install prerequisites
echo "Installing prerequisites for Docker..."
apt-get install -y ca-certificates curl

# Add Docker's official GPG key and repository
echo "Setting up Docker's repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install Docker
echo "Updating and installing Docker..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Confirm Docker installation
docker --version
docker compose version

# Set up Peppermint directory and download docker-compose file
mkdir -p /srv/peppermint
cd /srv/peppermint
wget https://raw.githubusercontent.com/Peppermint-Lab/Peppermint/master/docker-compose.yml

# Replace variables in docker-compose.yml
sed -i "s|MAIN_DOMAIN|$MAIN_DOMAIN|g" docker-compose.yml
sed -i "s|API_DOMAIN|$API_DOMAIN|g" docker-compose.yml
sed -i "s|POSTGRES_PASSWORD: .*|POSTGRES_PASSWORD: $POSTGRES_PASSWORD|g" docker-compose.yml
sed -i "s|SECRET: .*|SECRET: $SECRET|g" docker-compose.yml
sed -i "s|DB_PASSWORD: .*|DB_PASSWORD: $POSTGRES_PASSWORD|g" docker-compose.yml
sed -i "s|1000:3000|3000:3000|g" docker-compose.yml
sed -i "s|1001:5003|5003:5003|g" docker-compose.yml

# Install NGINX and configure firewall
apt install -y nginx
ufw allow 'Nginx Full'

# Create NGINX client proxy config
cat <<EOF > /etc/nginx/conf.d/peppermint-client.conf
server {
    listen 80;
    listen [::]:80;
    server_name $MAIN_DOMAIN;
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forward-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        proxy_read_timeout 5m;
    }
    client_max_body_size 10M;
}
EOF

# Create NGINX API proxy config
cat <<EOF > /etc/nginx/conf.d/peppermint-api.conf
server {
    listen 80;
    listen [::]:80;
    server_name $API_DOMAIN;
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:5003;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forward-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_redirect off;
        proxy_read_timeout 5m;
    }
    client_max_body_size 10M;
}
EOF

# Restart NGINX
systemctl restart nginx

# Install Certbot and dependencies
apt install -y python3 python3-venv libaugeas0
python3 -m venv /opt/certbot/
sudo /opt/certbot/bin/pip install --upgrade pip
sudo /opt/certbot/bin/pip install certbot certbot-nginx
ln -s /opt/certbot/bin/certbot /usr/bin/certbot

clear
echo "#####################################################################"
echo "#         User Intervention Required! SSL Setup via CertBot         #"
echo "#####################################################################"
echo ""
echo ""
echo ""
certbot --nginx

# Set up Certbot auto-renewal
echo "0 0,12 * * * root /opt/certbot/bin/python -c 'import random; import time; time.sleep(random.random() * 3600)' && sudo certbot renew -q" | tee -a /etc/crontab > /dev/null

docker compose up -d

clear

# Show completion message
echo " _____                                 _       _   "
echo "/  ___|                               (_)     | |  "
echo "\ \`--. _ __   ___  __ _ _ __ _ __ ___  _ _ __ | |_ "
echo " \`--. \ '_ \ / _ \/ _\` | '__| '_ \` _ \| | '_ \| __|"
echo "/\__/ / |_) |  __/ (_| | |  | | | | | | | | | | |_ "
echo "\____/| .__/ \___|\__,_|_|  |_| |_| |_|_|_| |_|\__|"
echo "      | |                                          "
echo "      |_|                                          "
echo "#####################################################################"
echo "#       Congrats! Peppermint is now installed on your server!       #"
echo "#####################################################################"
echo
echo "Domain: $MAIN_DOMAIN"
echo "Username: admin@admin.com"
echo "Password: 1234"
echo
echo "Spearmint Website: https://spearmint.sh"
echo "Spearmint Support: https://spearmint.sh/discord"
echo "Peppermint Discord: https://discord.gg/rhYDuSeeag"
echo
echo "#####################################################################"
echo "#        Thank you for using the Spearmint script by SydMae!        #"
echo "#####################################################################"
