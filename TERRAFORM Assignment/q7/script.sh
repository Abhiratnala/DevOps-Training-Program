#!/bin/bash
MYSQL_ROOT_PASSWORD=$1

apt update -y
apt install -y docker.io
systemctl enable docker
systemctl start docker

docker pull nginx
docker pull httpd
docker pull mysql

docker run -d --name nginx-container -p 80:80 nginx
docker run -d --name apache-container -p 8080:80 httpd
docker run -d --name mysql-container -p 3306:3306 -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql
