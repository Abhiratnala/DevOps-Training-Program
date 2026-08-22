#!/bin/bash
DOCKER_IMAGE=$1

apt update -y
apt install -y docker.io
systemctl enable docker
systemctl start docker

docker pull $DOCKER_IMAGE
docker run -d -p 80:80 $DOCKER_IMAGE
