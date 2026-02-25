#!/usr/bin/env bash
# Harden and prepare an Ubuntu 22.04 host for OpenClaw
# Requirements: run as root (sudo -i), provide env vars before launch:
#   ADMIN_USER=openc
#   ADMIN_SSH_KEY="ssh-ed25519 AAAA... user@host"
#   DOMAIN=your.domain.tld
#   ADMIN_EMAIL=you@example.com  (for Let's Encrypt)
#   SSH_PORT=22                  (optional)

set -euo pipefail

command -v lsb_release >/dev/null && lsb_release -a 2>/dev/null | grep -qi "22.04" || {
  echo "This script targets Ubuntu 22.04 LTS." >&2
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required variable: $name" >&2
    exit 1
  fi
}

require_var ADMIN_USER
require_var ADMIN_SSH_KEY
SSH_PORT="${SSH_PORT:-22}"

export DEBIAN_FRONTEND=noninteractive

echo "[1/9] Mise à jour du système..."
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release software-properties-common \
  ufw fail2ban nginx certbot python3-certbot-nginx \
  python3.11 python3.11-venv python3-pip build-essential \
  git jq unzip apt-transport-https

echo "[2/9] Installation de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "[3/9] Installation de Node.js LTS (20.x) ..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "[4/9] Création de l'utilisateur admin non-root..."
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$ADMIN_USER"
fi
usermod -aG sudo,docker "$ADMIN_USER"
mkdir -p /home/"$ADMIN_USER"/.ssh
echo "$ADMIN_SSH_KEY" > /home/"$ADMIN_USER"/.ssh/authorized_keys
chmod 700 /home/"$ADMIN_USER"/.ssh
chmod 600 /home/"$ADMIN_USER"/.ssh/authorized_keys
chown -R "$ADMIN_USER":"$ADMIN_USER" /home/"$ADMIN_USER"/.ssh
passwd -l "$ADMIN_USER" || true

echo "[5/9] Sécurisation SSH..."
SSHD_CONFIG=/etc/ssh/sshd_config
sed -i "s/^#\\?Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
sed -i "s/^#\\?PasswordAuthentication .*/PasswordAuthentication no/" "$SSHD_CONFIG"
sed -i "s/^#\\?PermitRootLogin .*/PermitRootLogin no/" "$SSHD_CONFIG"
sed -i "s/^#\\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/" "$SSHD_CONFIG"
sed -i "s/^#\\?UsePAM .*/UsePAM yes/" "$SSHD_CONFIG"
systemctl restart sshd

echo "[6/9] Pare-feu UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}"/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable
ufw status verbose

echo "[7/9] Fail2ban configuration..."
cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ${SSH_PORT}
maxretry = 4
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban

echo "[8/9] Swap 2G (si absent)..."
if ! swapon --show | grep -q "^/swapfile"; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "[9/9] Nginx reverse proxy + TLS..."
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /var/www
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%s)

# Deploy site config if DOMAIN provided
if [ -n "${DOMAIN:-}" ]; then
  cat >/etc/nginx/sites-available/openclaw.conf <<EOF
limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;

server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript application/xml text/xml;

    limit_req zone=one burst=20 nodelay;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/openclaw.conf /etc/nginx/sites-enabled/openclaw.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl restart nginx
  if [ -n "${ADMIN_EMAIL:-}" ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true
    systemctl reload nginx
  else
    echo "Certbot non exécuté (ADMIN_EMAIL manquant)."
  fi
else
  echo "DOMAIN non fourni, configuration Nginx générique non déployée."
fi

echo "Installation terminée. Connectez-vous en SSH sur le port ${SSH_PORT} avec l'utilisateur ${ADMIN_USER}."
