
#!/bin/bash

REGION="ap-southeast-2"
KEY="lab-key"

# Ubuntu 22.04 AMI
AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)

# Create first instance
INSTANCE1=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type t3.micro \
  --key-name $KEY \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "First Instance: $INSTANCE1"

# Wait for instance
aws ec2 wait instance-running \
  --region $REGION \
  --instance-ids $INSTANCE1

# Get Availability Zone
AZ=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $INSTANCE1 \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
  --output text)

# Create EBS volume
VOLUME=$(aws ec2 create-volume \
  --region $REGION \
  --availability-zone $AZ \
  --size 10 \
  --volume-type gp3 \
  --query VolumeId \
  --output text)

echo "EBS Volume: $VOLUME"

# Wait for volume
aws ec2 wait volume-available \
  --region $REGION \
  --volume-ids $VOLUME

# Attach EBS to first instance
aws ec2 attach-volume \
  --region $REGION \
  --volume-id $VOLUME \
  --instance-id $INSTANCE1 \
  --device /dev/sdf

# Terminate first instance
aws ec2 terminate-instances \
  --region $REGION \
  --instance-ids $INSTANCE1

aws ec2 wait instance-terminated \
  --region $REGION \
  --instance-ids $INSTANCE1

# Create new instance
INSTANCE2=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI \
  --instance-type t3.micro \
  --key-name $KEY \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "New Instance: $INSTANCE2"

# Wait for new instance
aws ec2 wait instance-running \
  --region $REGION \
  --instance-ids $INSTANCE2

# Attach EBS to new instance
aws ec2 attach-volume \
  --region $REGION \
  --volume-id $VOLUME \
  --instance-id $INSTANCE2 \
  --device /dev/sdf

echo "New Instance ID: $INSTANCE2"


