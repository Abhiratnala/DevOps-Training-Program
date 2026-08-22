#!/bin/bash
REGION=$(aws configure get region)

KEY_NAME="ubuntu-key"
KEY_FILE="${KEY_NAME}.pem"

SECURITY_GROUP_NAME="ubuntu-security-group"
INSTANCE_NAME="ubuntu-server"
INSTANCE_TYPE="t3.micro"
if [ -z "$REGION" ]; then
    echo "ERROR: AWS region is not configured."
    echo "Run: aws configure"
    exit 1
fi

echo "AWS Region: $REGION"
echo "Getting default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: Default VPC not found."
    exit 1
fi
echo "VPC ID: $VPC_ID"
SUBNET_ID=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --output text)

echo "Subnet ID: $SUBNET_ID"
echo "Creating EC2 key pair: $KEY_NAME"
# Remove old local key file if it exists
if [ -f "$KEY_FILE" ]; then
    echo "Removing existing local key file: $KEY_FILE"
    rm -f "$KEY_FILE"
fi
aws ec2 create-key-pair \
    --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query "KeyMaterial" \
    --output text > "$KEY_FILE"

chmod 400 "$KEY_FILE"

echo "Key pair created."
echo "Private key downloaded to: $KEY_FILE"
echo "Permissions:"
ls -l "$KEY_FILE"
echo
echo "Creating security group: $SECURITY_GROUP_NAME"

SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Allow SSH inbound and all outbound traffic" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" \
    --output text)

echo "Security Group ID: $SECURITY_GROUP_ID"
echo "Allowing SSH inbound on port 22..."

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

echo "Allowing all outbound traffic..."

aws ec2 authorize-security-group-egress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol -1 \
    --cidr 0.0.0.0/0 2>/dev/null || true

echo
echo "Getting latest Ubuntu 24.04 LTS AMI..."

AMI_ID=$(aws ssm get-parameter \
    --region "$REGION" \
    --name "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" \
    --query "Parameter.Value" \
    --output text)

echo "Ubuntu AMI: $AMI_ID"
echo
echo "Launching EC2 instance..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to start..."

aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID"

PUBLIC_DNS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicDnsName" \
    --output text)
echo "=============================================================="
echo "                  EC2 INSTANCE DETAILS"
echo "=============================================================="

printf "%-25s %-55s %-25s\n" \
    "INSTANCE ID" "PUBLIC DNS" "NAME"

printf "%-25s %-55s %-25s\n" \
    "-------------------------" \
    "-------------------------------------------------------" \
    "-------------------------"

printf "%-25s %-55s %-25s\n" \
    "$INSTANCE_ID" "$PUBLIC_DNS" "$INSTANCE_NAME"

echo
echo "Key Pair       : $KEY_NAME"
echo "Private Key    : $KEY_FILE"
echo "Security Group : $SECURITY_GROUP_ID"
echo "AMI ID         : $AMI_ID"
echo "Region         : $REGION"
echo
echo "SSH command:"
echo "ssh -i $KEY_FILE ubuntu@$PUBLIC_DNS"
echo "=============================================================="


