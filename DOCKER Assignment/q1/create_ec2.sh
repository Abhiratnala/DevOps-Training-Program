#!/bin/bash
set -e

REGION="ap-south-1"
KEY_NAME="lab-key"
KEY_PATH="${KEY_NAME}.pem"
SG_NAME="webapp-sg"
INSTANCE_TYPE="t2.micro"
DOCKER_IMAGE="yourusername/webapp:latest"

AMI_ID=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)

VPC_ID=$(aws ec2 describe-vpcs \
  --region $REGION \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SG_ID=$(aws ec2 create-security-group \
  --region $REGION \
  --group-name $SG_NAME \
  --description "Allow SSH and HTTP" \
  --vpc-id $VPC_ID \
  --query "GroupId" \
  --output text)

aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Instance $INSTANCE_ID launching, waiting for running state..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "Instance running at $PUBLIC_IP"
echo "Waiting 30s for SSH to become available..."
sleep 30

scp -o StrictHostKeyChecking=no -i $KEY_PATH provisional.sh ubuntu@$PUBLIC_IP:/home/ubuntu/provisional.sh

ssh -o StrictHostKeyChecking=no -i $KEY_PATH ubuntu@$PUBLIC_IP \
  "chmod +x provisional.sh && sudo ./provisional.sh $DOCKER_IMAGE"

echo "Done. App available at http://$PUBLIC_IP"
