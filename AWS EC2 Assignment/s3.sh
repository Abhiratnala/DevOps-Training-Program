#!/bin/bash
REGION=$(aws configure get region)
INSTANCE_NAME="ubuntu-server"
SECURITY_GROUP_NAME="ubuntu-ssh-sg"
INSTANCE_TYPE="t3.micro"
KEY_NAME="lab-key"
if [ -z "$REGION" ]; then
    echo "ERROR: AWS region is not configured."
    echo "Run: aws configure"
    exit 1
fi
echo "Using AWS Region: $REGION"
echo
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: No default VPC found in region $REGION."
    exit 1
fi
echo "VPC ID: $VPC_ID"
SUBNET_ID=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --output text)
if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: No subnet found."
    exit 1
fi
echo "Subnet ID: $SUBNET_ID"
AMI_ID=$(aws ssm get-parameter \
    --region "$REGION" \
    --name "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" \
    --query "Parameter.Value" \
    --output text)
echo "Ubuntu AMI ID: $AMI_ID"
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Allow SSH inbound and all outbound traffic" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" \
    --output text 2>/dev/null || true)
if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" = "None" ]; then
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters \
            "Name=group-name,Values=$SECURITY_GROUP_NAME" \
            "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[0].GroupId" \
        --output text)
fi
echo "Security Group ID: $SECURITY_GROUP_ID"
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 2>/dev/null || true
aws ec2 authorize-security-group-egress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --ip-permissions \
        IpProtocol=-1,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    2>/dev/null || true
echo "Launching Ubuntu EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID"
INSTANCE_INFO=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].[InstanceId,PublicDnsName,Tags[?Key=='Name']|[0].Value]" \
    --output text)
echo
echo "============================================================"
echo "                 EC2 INSTANCE DETAILS"
echo "============================================================"

printf "%-25s %-45s %-25s\n" "INSTANCE ID" "PUBLIC DNS" "NAME"
printf "%-25s %-45s %-25s\n" "-------------------------" "---------------------------------------------" "-------------------------"

echo "$INSTANCE_INFO" | awk '{
    printf "%-25s %-45s %-25s\n", $1, $2, $3
}'

echo
echo "Security Group : $SECURITY_GROUP_ID"
echo "AMI ID         : $AMI_ID"
echo "Region         : $REGION"
echo "============================================================"
