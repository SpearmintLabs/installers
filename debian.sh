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

if [[ "$OS_NAME" != "debian" ]]; then
    echo "Warning: This script is designed to run on Debian. Please use the deployer to install the correct version."
    exit 1
fi

# Check if deployment file exists
if [ ! -f "/srv/spearmint/sprmnt.txt" ]; then
    echo "Deployment file sprmnt.txt not found in /srv/spearmint."
    exit 1
fi

WIP=$(curl -s ifconfig.me)
clear
echo "#####################################################################"
echo "#                      Lets get things set up!                      #"
echo "#####################################################################"
echo ""
echo ""
echo "         Please make sure your domains are pointed at $WIP!         "
echo "Peppermint will not work out of the box if your domains are not set up!"
echo "    Please ensure your records are 'A' records, not AAAA or SRV!    "
echo ""
echo ""
echo ""
read -p "Enter Main Domain: " MAIN_DOMAIN
read -p "Enter API Domain: " API_DOMAIN
read -p "Enter the a valid email for SSL: " SSL_EMAIL
read -p "Enter SECRET (press Enter to auto-generate): " SECRET
SECRET=${SECRET:-$(openssl rand -hex 16)}
read -p "Enter POSTGRES_PASSWORD (press Enter to auto-generate): " POSTGRES_PASSWORD
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}
read -p "Do you want the containers to be updated automatically or manually when a new version is released (automatic/manual): " AUTO_UPDATE

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
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Install prerequisites
echo "Installing prerequisites for Docker..."
apt-get update
apt-get install -y ca-certificates curl

# Firewall Rules
apt install -y iptables
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Add Docker's Official GPC key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.as

# Add repo to apt srcs
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install latest docker version
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Confirm Docker installation
docker --version
docker compose version

# Set up Peppermint directory and download docker-compose file
mkdir -p /srv/spearmint
cd /srv/spearmint

wget https://i.spearmint.sh/utilities/prettifier.sh
chmod +x prettifier.sh

if [ "$AUTO_UPDATE" == "manual" ]; then
    wget https://deploy.spearmint.sh/manual/docker-compose.yml
    wget https://deploy.spearmint.sh/manual/diun.yml
    touch diun.key
else
    wget https://deploy.spearmint.sh/auto/docker-compose.yml
    touch watchtower.key
fi

# Replace variables in docker-compose.yml
sed -i "s|MAIN_DOMAIN|$MAIN_DOMAIN|g" docker-compose.yml
sed -i "s|API_DOMAIN|$API_DOMAIN|g" docker-compose.yml
sed -i "s|POSTGRES_PASSWORD: .*|POSTGRES_PASSWORD: $POSTGRES_PASSWORD|g" docker-compose.yml
sed -i "s|SECRET: .*|SECRET: $SECRET|g" docker-compose.yml
sed -i "s|DB_PASSWORD: .*|DB_PASSWORD: $POSTGRES_PASSWORD|g" docker-compose.yml

# Install NGINX and configure firewall
apt install -y nginx

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

clear
echo "#####################################################################"
echo "#                 Installing Certbot Dependencies~                  #"
echo "#####################################################################"
echo ""
echo ""
echo ""

# Install Certbot and dependencies
apt install -y python3 python3-venv libaugeas0
python3 -m venv /opt/certbot/
sudo /opt/certbot/bin/pip install --upgrade pip
sudo /opt/certbot/bin/pip install certbot certbot-nginx
ln -s /opt/certbot/bin/certbot /usr/bin/certbot

clear
echo "#####################################################################"
echo "#           Setting up SSL certificates for your domains!           #"
echo "#####################################################################"
echo ""
echo ""
echo ""
certbot --nginx --non-interactive --agree-tos -d $MAIN_DOMAIN -d $API_DOMAIN -m $SSL_EMAIL

# Set up Certbot auto-renewal
echo "0 0,12 * * * root /opt/certbot/bin/python -c 'import random; import time; time.sleep(random.random() * 3600)' && sudo certbot renew -q" | tee -a /etc/crontab > /dev/null

clear
echo "#####################################################################"
echo "#             Downloading & Starting Docker containers.             #"
echo "#####################################################################"
echo ""
echo ""
echo ""
docker compose up -d

clear
echo -e "\e[92m _____                                 _       _   "
echo -e "\e[92m/  ___|                               (_)     | |  "
echo -e "\e[92m\ \`--. _ __   ___  __ _ _ __ _ __ ___  _ _ __ | |_ "
echo -e "\e[92m \`--. \ '_ \ / _ \/ _\` | '__| '_ \` _ \| | '_ \| __|"
echo -e "\e[92m/\__/ / |_) |  __/ (_| | |  | | | | | | | | | | |_ "
echo -e "\e[92m\____/| .__/ \___|\__,_|_|  |_| |_| |_|_|_| |_|\__|"
echo -e "\e[92m      | |                                          "
echo -e "\e[92m      |_|                                          \e[0m"
echo "#####################################################################"
echo -e "#       \e[1mCongrats! Peppermint is now installed on your server!\e[0m       #"
echo "#####################################################################"
echo
echo "Domain: https://$MAIN_DOMAIN"
echo "Username: admin@admin.com"
echo "Password: 1234"
echo
echo "Spearmint Website: https://spearmint.sh"
echo "Peppermint Discord: https://discord.gg/rhYDuSeeag"
echo ""
echo ""
echo ""

if [ -f /srv/spearmint/diun.key ]; then
    echo "Please configure Diun by using spearmint diun"
elif [ -f /srv/spearmint/watchtower.key ]; then
    echo "Watchtower is now up!"
else
    echo "Installer Error! Please contact sydmae on Discord! Code: NO_AUTOUPDATE_CONT"
fi

echo ""
echo ""
echo ""
echo -e "You can see the credits for this script by running \e[27mspearmint credits\e[27m!"
echo ""
echo ""

spearmint status