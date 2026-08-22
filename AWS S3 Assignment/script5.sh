#!/bin/bash

REGION="ap-southeast-2"

echo "Fetching AWS resources..."

# Get the first available Key Pair
KEY_NAME=$(aws ec2 describe-key-pairs \
    --query "KeyPairs[0].KeyName" \
    --output text \
    --region $REGION)

# Get the default Security Group
SECURITY_GROUP=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=default \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region $REGION)

# Get the first available subnet
SUBNET_ID=$(aws ec2 describe-subnets \
    --query "Subnets[0].SubnetId" \
    --output text \
    --region $REGION)

# Get the latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query "sort_by(Images,&CreationDate)[-1].ImageId" \
    --output text \
    --region $REGION)

echo "Key Pair      : $KEY_NAME"
echo "Security Group: $SECURITY_GROUP"
echo "Subnet ID     : $SUBNET_ID"
echo "AMI ID        : $AMI_ID"

# Launch EC2
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --associate-public-ip-address \
    --query "Instances[0].InstanceId" \
    --output text \
    --region $REGION)

echo "Instance ID: $INSTANCE_ID"

# Wait until the instance is running
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region $REGION

# Get Public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text \
    --region $REGION)

echo "Public IP: $PUBLIC_IP"

# Wait a bit for SSH service
sleep 30

# Copy remote script
scp -o StrictHostKeyChecking=no \
    -i ${KEY_NAME}.pem \
    remote_script.sh ec2-user@$PUBLIC_IP:/home/ec2-user/

# Execute remote script
ssh -o StrictHostKeyChecking=no \
    -i ${KEY_NAME}.pem \
    ec2-user@$PUBLIC_IP \
    "chmod +x remote_script.sh && ./remote_script.sh"

