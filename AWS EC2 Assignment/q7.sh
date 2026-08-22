#!/bin/bash
set -e

REGION="ap-southeast-2"
KEY="lab-key"
SG_ID="sg-00f70404cbd6421d1"     # existing security group
INSTANCE_TYPE="t3.micro"

# Find latest Ubuntu 22.04 AMI
AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)
echo "AMI ID: $AMI"

# Launch instance
INSTANCE=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY \
  --security-group-ids $SG_ID \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance ID: $INSTANCE"

# Wait until running
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE
echo "Instance is running."

# ---- Check if an Elastic IP is associated with this instance ----
EIP=$(aws ec2 describe-addresses \
  --region $REGION \
  --filters "Name=instance-id,Values=$INSTANCE" \
  --query 'Addresses[0].PublicIp' \
  --output text)

if [ "$EIP" == "None" ] || [ -z "$EIP" ]; then
  echo "No Elastic IP is assigned to this instance."

  # Show the auto-assigned public IP instead (not an Elastic IP, just ephemeral)
  AUTO_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  echo "Current (non-Elastic) public IP: $AUTO_IP"
else
  echo "Elastic IP is assigned: $EIP"
fi
