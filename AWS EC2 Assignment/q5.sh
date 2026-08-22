#!/bin/bash
set -e

REGION="ap-southeast-2"
KEY="lab-key"
KEY_FILE="./${KEY}.pem"
SG_NAME="lab-sg"
INSTANCE_TYPE="t3.micro"

# ---- 1. Create key pair ----
if aws ec2 describe-key-pairs --region $REGION --key-names $KEY >/dev/null 2>&1; then
  echo "Key pair '$KEY' already exists, skipping creation."
else
  echo "Creating key pair: $KEY"
  aws ec2 create-key-pair \
    --region $REGION \
    --key-name $KEY \
    --query 'KeyMaterial' \
    --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "Saved private key to $KEY_FILE"
fi

# ---- 2. Create security group ----
SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "Creating security group: $SG_NAME"
  SG_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name $SG_NAME \
    --description "Allow SSH access" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress \
    --region $REGION \
    --group-id $SG_ID \
    --protocol tcp --port 22 --cidr 0.0.0.0/0
else
  echo "Security group already exists: $SG_ID"
fi
echo "Security Group ID: $SG_ID"

# ---- 3. Find latest Ubuntu 22.04 AMI ----
AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)
echo "AMI ID: $AMI"

# ---- 4. Launch instance using the key pair and security group ----
INSTANCE=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY \
  --security-group-ids $SG_ID \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance ID: $INSTANCE"

aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE
echo "Instance is running."

IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $INSTANCE \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo ""
echo "Done."
echo "Instance ID : $INSTANCE"
echo "Public IP   : $IP"
echo "SSH command : ssh -i $KEY_FILE ubuntu@$IP"
