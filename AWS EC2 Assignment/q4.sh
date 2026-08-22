#!/bin/bash
set -e

REGION="ap-southeast-2"
KEY="lab-key"
KEY_FILE="/home/abhignya/Desktop/2341001003/aws/ec2/ec2_assignment/lab-key.pem"
SG_NAME="nginx-sg"

# ---- Security group: open port 22 (SSH) and 80 (HTTP) ----
SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "Creating security group..."
  SG_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name $SG_NAME \
    --description "Allow SSH and HTTP" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

  aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
fi
echo "Security Group ID: $SG_ID"

# ---- Find latest Ubuntu 22.04 AMI ----
AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)
echo "AMI ID: $AMI"

# ---- User-data: installs nginx automatically on first boot ----
USER_DATA='#!/bin/bash
apt update -y
apt install -y nginx
systemctl enable nginx
systemctl start nginx'

# ---- Launch instance ----
INSTANCE=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type t3.micro \
  --key-name $KEY \
  --security-group-ids $SG_ID \
  --user-data "$USER_DATA" \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance ID: $INSTANCE"

aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE
echo "Instance is running."

IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $INSTANCE \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Public IP: $IP"

chmod 400 "$KEY_FILE"

echo "Waiting for SSH..."
until nc -z "$IP" 22 2>/dev/null; do
    sleep 5
done
sleep 5
echo "SSH is available."

# ---- SSH in, wait for user-data (cloud-init) to finish, then check nginx ----
echo "Waiting for instance setup (cloud-init) to finish..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$IP \
  "sudo cloud-init status --wait"

echo "Checking nginx status..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$IP \
  "sudo systemctl status nginx --no-pager"

echo ""
echo "Done. Access the nginx welcome page at: http://$IP"
