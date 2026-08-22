#!/bin/bash
apt update -y
apt install -y nginx
echo "Hello from Backend Server" > /var/www/html/index.html
systemctl restart nginx
systemctl enable nginx
