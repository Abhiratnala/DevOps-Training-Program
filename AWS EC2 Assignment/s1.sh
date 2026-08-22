#!/bin/bash
# ===== Guest details =====
GUEST_USER="ubuntu"
GUEST_IP="13.236.91.2"
GUEST_PATH="/home/$GUEST_USER/setup_nginx.sh"

echo "===================================="
echo " Starting Nginx deployment"
echo "===================================="

echo "[1] Checking SSH connection..."
ssh -o ConnectTimeout=10 "$GUEST_USER@$GUEST_IP" "echo 'SSH connection successful'"

if [ $? -ne 0 ]; then
    echo "ERROR: Cannot connect to guest!"
    echo "Check GUEST_USER and GUEST_IP."
    exit 1
fi

echo "[2] Creating Nginx setup script..."

cat > /tmp/setup_nginx.sh <<'EOF'
#!/bin/bash

set -x

echo "=== Updating system ==="
sudo apt update -y

echo "=== Installing Nginx and curl ==="
sudo apt install -y nginx curl

echo "=== Starting Nginx ==="
sudo systemctl enable nginx
sudo systemctl start nginx

echo "=== Checking Nginx status ==="
sudo systemctl is-active nginx

echo "=== Testing localhost ==="
curl -I http://localhost

echo "=== Nginx setup completed ==="
EOF

chmod +x /tmp/setup_nginx.sh

echo "[3] Sending script to guest..."

scp -v /tmp/setup_nginx.sh "$GUEST_USER@$GUEST_IP:$GUEST_PATH"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to copy script to guest!"
    exit 1
fi

echo "[4] Running script on guest..."

ssh -t "$GUEST_USER@$GUEST_IP" \
    "chmod +x $GUEST_PATH && sudo $GUEST_PATH"

if [ $? -ne 0 ]; then
    echo "ERROR: Script failed on guest!"
    exit 1
fi

echo "===================================="
echo " Deployment completed successfully"
echo "===================================="


