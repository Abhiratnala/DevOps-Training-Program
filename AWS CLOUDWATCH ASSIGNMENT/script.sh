#!/bin/bash
# ==========================
# Configuration
# ==========================
REGION="ap-southeast-2"
INSTANCE_TYPE="t3.micro"
INSTANCE_NAME="ubuntu-server"
KEY_NAME="ubuntu-key-$(date +%s)"
SG_NAME="ubuntu-sg-$(date +%s)"

echo "Finding latest Ubuntu 24.04 LTS AMI..."

AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners 099720109477 \
    --filters \
        "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
        "Name=architecture,Values=x86_64" \
        "Name=virtualization-type,Values=hvm" \
        "Name=state,Values=available" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
    --output text)

echo "AMI ID: $AMI_ID"

# Get Default VPC

echo "Finding default VPC..."

VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" \
    --output text)

echo "VPC: $VPC_ID"
# Find AZ where t3.micro exists
echo "Finding available AZ for $INSTANCE_TYPE..."

AZ=$(aws ec2 describe-instance-type-offerings \
    --region "$REGION" \
    --location-type availability-zone \
    --filters Name=instance-type,Values="$INSTANCE_TYPE" \
    --query 'InstanceTypeOfferings[0].Location' \
    --output text)

echo "Using AZ: $AZ"

# Get subnet in that AZ
SUBNET_ID=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters \
        Name=vpc-id,Values="$VPC_ID" \
        Name=availability-zone,Values="$AZ" \
    --query "Subnets[0].SubnetId" \
    --output text)

echo "Subnet: $SUBNET_ID"

# Create Key Pair
echo "Creating key pair..."

aws ec2 create-key-pair \
    --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query "KeyMaterial" \
    --output text > "${KEY_NAME}.pem"

chmod 400 "${KEY_NAME}.pem"

# Create Security Group
echo "Creating security group..."

SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "Ubuntu EC2 security group" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" \
    --output text)

echo "Security Group: $SG_ID"

# Allow SSH
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0


# Allow HTTP
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

# Launch EC2
echo "Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --block-device-mappings '[
        {
            "DeviceName": "/dev/sda1",
            "Ebs": {
                "VolumeSize": 8,
                "VolumeType": "gp3",
                "DeleteOnTermination": true
            }
        }
    ]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)


echo "Instance ID: $INSTANCE_ID"
# Wait until running
echo "Waiting for instance..."

aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID"

# Get Public IP
# ==========================
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)


echo
echo "======================================"
echo "EC2 CREATED SUCCESSFULLY"
echo "======================================"
echo "Region      : $REGION"
echo "Instance ID : $INSTANCE_ID"
echo "AMI ID      : $AMI_ID"
echo "AZ          : $AZ"
echo "Public IP   : $PUBLIC_IP"
echo "Key         : ${KEY_NAME}.pem"
echo
echo "SSH Command:"
echo "ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo "======================================"

# ==========================
# Create SNS Topic
# ==========================

echo "Creating SNS topic..."

TOPIC_ARN=$(aws sns create-topic \
    --region "$REGION" \
    --name MyTopic \
    --query "TopicArn" \
    --output text)

echo "SNS Topic ARN: $TOPIC_ARN"

# Subscribe Email


aws sns subscribe \
    --region "$REGION" \
    --topic-arn "$TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "example@example.com"


echo "Email subscription created. Confirm the email."

# Create CloudWatch CPU Alarm

echo "Creating CloudWatch alarm..."


aws cloudwatch put-metric-alarm \
    --region "$REGION" \
    --alarm-name "${INSTANCE_NAME}-cpu-alarm" \
    --alarm-description "Alarm when EC2 CPU exceeds 70%" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 300 \
    --threshold 70 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --evaluation-periods 2 \
    --alarm-actions "$TOPIC_ARN" \
    --unit Percent


echo "CloudWatch alarm created"


