#!/bin/bash
apt update -y
apt install -y curl
curl http://${backend_ip}
