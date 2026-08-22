#!/bin/bash
REGION="ap-southeast-2"
AZ="${REGION}a"
KEY="lab-key"
KEY_FILE="./${KEY}.pem"
INSTANCE_TYPE="t3.micro"

VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"    # bastion + NAT Gateway live here
PRIVATE_SUBNET_CIDR="10.0.2.0/24"   # target instance lives here, no public IP

AMI=$(aws ec2 describe-images \
  --region $REGION --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' --output text)
echo "Using AMI: $AMI"
VPC_ID=$(aws ec2 create-vpc --region $REGION --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=NAT-Lab-VPC}]" \
  --query 'Vpc.VpcId' --output text)
aws ec2 wait vpc-available --region $REGION --vpc-ids $VPC_ID
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"
echo "VPC ID: $VPC_ID"
PUB_SUBNET_ID=$(aws ec2 create-subnet --region $REGION --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_CIDR --availability-zone $AZ \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet}]" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $PUB_SUBNET_ID --map-public-ip-on-launch
echo "Public Subnet ID: $PUB_SUBNET_ID"
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=NAT-Lab-IGW}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region $REGION --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
PUB_RT_ID=$(aws ec2 create-route-table --region $REGION --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region $REGION --route-table-id $PUB_RT_ID \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID >/dev/null
aws ec2 associate-route-table --region $REGION --route-table-id $PUB_RT_ID --subnet-id $PUB_SUBNET_ID >/dev/null
PRIV_SUBNET_ID=$(aws ec2 create-subnet --region $REGION --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_CIDR --availability-zone $AZ \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet}]" \
  --query 'Subnet.SubnetId' --output text)
echo "Private Subnet ID: $PRIV_SUBNET_ID"
EIP_ALLOC_ID=$(aws ec2 allocate-address --region $REGION --domain vpc \
  --query 'AllocationId' --output text)
echo "Elastic IP for NAT Gateway: $EIP_ALLOC_ID"

NAT_GW_ID=$(aws ec2 create-nat-gateway --region $REGION \
  --subnet-id $PUB_SUBNET_ID --allocation-id $EIP_ALLOC_ID \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=NAT-Lab-NATGW}]" \
  --query 'NatGateway.NatGatewayId' --output text)
echo "NAT Gateway ID: $NAT_GW_ID (provisioning, this takes a few minutes)..."
aws ec2 wait nat-gateway-available --region $REGION --nat-gateway-ids $NAT_GW_ID
echo "NAT Gateway is available."
PRIV_RT_ID=$(aws ec2 create-route-table --region $REGION --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Private-RT}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region $REGION --route-table-id $PRIV_RT_ID \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID >/dev/null
aws ec2 associate-route-table --region $REGION --route-table-id $PRIV_RT_ID --subnet-id $PRIV_SUBNET_ID >/dev/null
echo "Private route table -> 0.0.0.0/0 via NAT Gateway $NAT_GW_ID"
BASTION_SG_ID=$(aws ec2 create-security-group --region $REGION \
  --group-name "Bastion-SG" --description "Bastion SG" --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $BASTION_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
PRIVATE_SG_ID=$(aws ec2 create-security-group --region $REGION \
  --group-name "Private-Instance-SG" --description "Private instance SG" --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $PRIVATE_SG_ID --protocol tcp --port 22 --cidr $PUBLIC_SUBNET_CIDR >/dev/null
BASTION_ID=$(aws ec2 run-instances --region $REGION \
  --image-id $AMI --instance-type $INSTANCE_TYPE --key-name $KEY \
  --subnet-id $PUB_SUBNET_ID --security-group-ids $BASTION_SG_ID \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Bastion}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --region $REGION --instance-ids $BASTION_ID
BASTION_PUB_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $BASTION_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Bastion ID: $BASTION_ID   Public IP: $BASTION_PUB_IP"
PRIVATE_INSTANCE_ID=$(aws ec2 run-instances --region $REGION \
  --image-id $AMI --instance-type $INSTANCE_TYPE --key-name $KEY \
  --subnet-id $PRIV_SUBNET_ID --security-group-ids $PRIVATE_SG_ID \
  --no-associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Private-Instance}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --region $REGION --instance-ids $PRIVATE_INSTANCE_ID
PRIVATE_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $PRIVATE_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
echo "Private Instance ID: $PRIVATE_INSTANCE_ID   Private IP: $PRIVATE_IP (no public IP)"
echo "Waiting for bastion SSH..."
until nc -z -w 3 "$BASTION_PUB_IP" 22 2>/dev/null; do sleep 5; done
sleep 5
echo "Copying key to bastion (needed to hop into the private instance)..."
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no "$KEY_FILE" ubuntu@"$BASTION_PUB_IP":~/lab-key.pem
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$BASTION_PUB_IP" "chmod 400 ~/lab-key.pem"
echo "Waiting a bit longer for the private instance's SSH + network to be ready..."
sleep 20
echo ""
echo "===== Testing internet access from the PRIVATE instance via NAT Gateway ====="
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$BASTION_PUB_IP" \
  "ssh -i ~/lab-key.pem -o StrictHostKeyChecking=no ubuntu@$PRIVATE_IP 'curl -s -m 10 https://checkip.amazonaws.com && echo \"  -> Internet reachable via NAT Gateway\"'"

