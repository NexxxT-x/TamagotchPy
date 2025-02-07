#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# System Update
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update -qq && apt-get upgrade -y -qq

# Install Dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get install -y -qq \
  git \
  curl \
  build-essential \
  libssl-dev \
  mongodb \
  redis-server \
  nginx \
  certbot \
  python3-certbot-nginx

# Install Node.js 18.x
echo -e "${YELLOW}Installing Node.js...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y -qq nodejs

# Verify Installations
echo -e "${YELLOW}Verifying versions...${NC}"
node -v
npm -v
mongod --version
redis-server --version

# Database Setup
echo -e "${YELLOW}Configuring MongoDB...${NC}"
systemctl enable mongodb
systemctl start mongodb

# Create MongoDB User
echo -e "${YELLOW}Creating database user...${NC}"
mongo admin --eval "db.createUser({
  user: 'tamagotchi_admin',
  pwd: 'strongpassword123',
  roles: [{ role: 'readWrite', db: 'tamagotchi' }]
})"

# Redis Configuration
echo -e "${YELLOW}Configuring Redis...${NC}"
sed -i 's/supervised no/supervised systemd/' /etc/redis/redis.conf
systemctl restart redis

# Clone Repository
echo -e "${YELLOW}Cloning project repository...${NC}"
cd /opt
git clone https://github.com/your-username/tamagotchi-server.git
cd tamagotchi-server

# Install NPM Dependencies
echo -e "${YELLOW}Installing Node modules...${NC}"
npm install --production

# Environment Setup
echo -e "${YELLOW}Creating environment file...${NC}"
cat > .env <<EOL
MONGODB_URI=mongodb://tamagotchi_admin:strongpassword123@localhost:27017/tamagotchi?authSource=admin
JWT_SECRET=$(openssl rand -hex 32)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
NODE_ENV=production
PORT=3000
EOL

# PM2 Setup
echo -e "${YELLOW}Configuring PM2 process manager...${NC}"
npm install -g pm2
pm2 start server.js --name tamagotchi-server
pm2 save
pm2 startup

# Firewall Configuration
echo -e "${YELLOW}Configuring firewall...${NC}"
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw allow 3000
ufw allow 5000
ufw --force enable

# SSL Certificate (Replace with your domain)
echo -e "${YELLOW}Setting up SSL certificate...${NC}"
certbot --nginx -d your-domain.com --non-interactive --agree-tos -m admin@your-domain.com

# Nginx Configuration
echo -e "${YELLOW}Setting up Nginx reverse proxy...${NC}"
cat > /etc/nginx/sites-available/tamagotchi <<EOL
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOL

ln -s /etc/nginx/sites-available/tamagotchi /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Final Checks
echo -e "${YELLOW}Verifying services...${NC}"
systemctl status mongodb
systemctl status redis
systemctl status nginx
pm2 status

echo -e "${GREEN}Installation complete!${NC}"
echo -e "Access your server at: https://your-domain.com"
