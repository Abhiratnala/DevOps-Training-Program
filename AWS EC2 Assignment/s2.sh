#!/bin/bash

set -e

# ===== Guest configuration =====
GUEST_USER="ubuntu"
GUEST_IP="13.236.91.2"
SCRIPT_NAME="setup-nginx-guest.sh"

echo "==> Creating guest setup script..."

cat > "/tmp/$SCRIPT_NAME" <<'EOF'
#!/bin/bash

set -e

echo "==> Updating system..."
sudo apt-get update -y

echo "==> Installing Nginx and curl..."
sudo apt-get install -y nginx curl

echo "==> Enabling and starting Nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "==> Checking Nginx status..."
sudo systemctl --no-pager status nginx

echo "==> Testing Nginx on localhost..."
curl -I http://localhost

echo "==> Guest setup completed successfully."
EOF

chmod +x "/tmp/$SCRIPT_NAME"

echo "==> Copying script to guest..."
scp "/tmp/$SCRIPT_NAME" "$GUEST_USER@$GUEST_IP:/tmp/$SCRIPT_NAME"

echo "==> Running setup on guest..."
ssh "$GUEST_USER@$GUEST_IP" \
    "chmod +x /tmp/$SCRIPT_NAME && sudo /tmp/$SCRIPT_NAME"

echo "==> Checking Nginx from host..."
curl -I "http://$GUEST_IP"

echo "==> Nginx is working on $GUEST_IP"
