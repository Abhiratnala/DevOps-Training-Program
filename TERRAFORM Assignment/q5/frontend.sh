#!/bin/bash
BACKEND_IP=$1

apt update -y
apt install -y nginx curl

BACKEND_RESPONSE=$(curl -s http://$BACKEND_IP)

cat > /var/www/html/index.html << EOF
<h1>Frontend Server</h1>
<p>Backend IP: $BACKEND_IP</p>
<p>Response from backend:</p>
<pre>$BACKEND_RESPONSE</pre>
EOF

systemctl enable nginx
systemctl restart nginx
