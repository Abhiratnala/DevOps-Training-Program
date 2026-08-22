#!/bin/bash
set -e

REGION="ap-southeast-2"
AZ1="ap-southeast-2a"
AZ2="ap-southeast-2b"
KEY_NAME="lab-key"
INSTANCE_TYPE="t3.micro"
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
AMI_ID=$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query "Parameters[0].Value" --output text)
  # Ubuntu 22.04 LTS, verify for your region
VPC_CIDR="10.1.0.0/16"
SUBNET1_CIDR="10.1.1.0/24"
SUBNET2_CIDR="10.1.2.0/24"
########################################

# ---- VPC ----
VPC_ID=$(aws ec2 create-vpc --region "$REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=connectivity-demo-vpc}]" \
  --query "Vpc.VpcId" --output text)

aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"
echo ">> VPC created: $VPC_ID"

# ---- Two subnets in two different AZs ----
SUBNET1_ID=$(aws ec2 create-subnet --region "$REGION" \
  --vpc-id "$VPC_ID" --cidr-block "$SUBNET1_CIDR" --availability-zone "$AZ1" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=subnet-a}]" \
  --query "Subnet.SubnetId" --output text)

SUBNET2_ID=$(aws ec2 create-subnet --region "$REGION" \
  --vpc-id "$VPC_ID" --cidr-block "$SUBNET2_CIDR" --availability-zone "$AZ2" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=subnet-b}]" \
  --query "Subnet.SubnetId" --output text)

aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$SUBNET1_ID" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$SUBNET2_ID" --map-public-ip-on-launch

echo ">> Subnet A: $SUBNET1_ID | Subnet B: $SUBNET2_ID"

# ---- Internet Gateway + routing (so we can SSH in from outside) ----
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=connectivity-demo-igw}]" \
  --query "InternetGateway.InternetGatewayId" --output text)

aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

RT_ID=$(aws ec2 create-route-table --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=connectivity-demo-rt}]" \
  --query "RouteTable.RouteTableId" --output text)

aws ec2 create-route --region "$REGION" \
  --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_ID" --subnet-id "$SUBNET1_ID"
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_ID" --subnet-id "$SUBNET2_ID"

echo ">> IGW and route table set up: $IGW_ID / $RT_ID"

# ---- Security group: SSH from your IP, and SSH+ICMP from within the VPC itself ----
SG_ID=$(aws ec2 create-security-group --region "$REGION" \
  --group-name connectivity-demo-sg \
  --description "Intra-VPC connectivity demo" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP"

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$VPC_CIDR"

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol icmp --port -1 --cidr "$VPC_CIDR"

echo ">> Security group created: $SG_ID"

# ---- Launch instance in subnet A ----
INSTANCE1_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" --subnet-id "$SUBNET1_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=instance-a}]" \
  --query "Instances[0].InstanceId" --output text)

# ---- Launch instance in subnet B ----
INSTANCE2_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" --subnet-id "$SUBNET2_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=instance-b}]" \
  --query "Instances[0].InstanceId" --output text)

echo ">> instance-a: $INSTANCE1_ID | instance-b: $INSTANCE2_ID"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE1_ID" "$INSTANCE2_ID"

PUBLIC_IP1=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE1_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
PRIVATE_IP1=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE1_ID" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
PRIVATE_IP2=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE2_ID" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

echo ""
echo "=================================================="
echo "instance-a  public IP:  $PUBLIC_IP1"
echo "instance-a  private IP: $PRIVATE_IP1"
echo "instance-b  private IP: $PRIVATE_IP2"
echo ""
echo "To prove they can communicate within the VPC:"
echo "1. SSH into instance-a:"
echo "   ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP1"
echo "2. From inside instance-a, ping instance-b:"
echo "   ping $PRIVATE_IP2"
echo "3. From inside instance-a, SSH into instance-b (copy your .pem there first, or use agent forwarding):"
echo "   ssh -i lab-key.pem ubuntu@$PRIVATE_IP2"
echo "=================================================="
