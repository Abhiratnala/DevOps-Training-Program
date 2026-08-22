#!/bin/bash
REGION="ap-southeast-2"
KEY="lab-key"
KEY_FILE="/home/abhignya/Desktop/2341001003/aws/ec2/ec2_assignment/lab-key.pem"
AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)
echo "AMI ID: $AMI"
INSTANCE=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type t3.micro \
  --key-name $KEY \
  --query 'Instances[0].InstanceId' \
  --output text)
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
echo "SSH is available."
sleep 5
echo "Connecting to EC2..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$IP
