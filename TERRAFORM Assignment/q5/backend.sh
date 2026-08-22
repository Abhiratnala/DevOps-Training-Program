#!/bin/bash
apt update -y
apt install -y nginx
echo "<h1>Backend Server</h1><p>Hello from Backend</p>" > /var/www/html/index.html
systemctl enable nginx
systemctl restart nginx
