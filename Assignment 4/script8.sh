#!/bin/bash
set -e

#############################################
# CONFIG
#############################################

AWS_REGION="ap-southeast-2"

# Bastion EC2 Name tag
BASTION_NAME=""

# GET BASTION INSTANCE DETAILS

echo "Finding bastion instance..."

BASTION_INSTANCE_ID=$(aws ec2 describe-instances \
--region $AWS_REGION \
--filters \
"Name=tag:Name,Values=$BASTION_NAME" \
"Name=instance-state-name,Values=running" \
--query "Reservations[0].Instances[0].InstanceId" \
--output text)


BASTION_PUBLIC_IP=$(aws ec2 describe-instances \
--region $AWS_REGION \
--instance-ids $BASTION_INSTANCE_ID \
--query "Reservations[0].Instances[0].PublicIpAddress" \
--output text)


VPC_ID=$(aws ec2 describe-instances \
--region $AWS_REGION \
--instance-ids $BASTION_INSTANCE_ID \
--query "Reservations[0].Instances[0].VpcId" \
--output text)


BASTION_SG=$(aws ec2 describe-instances \
--region $AWS_REGION \
--instance-ids $BASTION_INSTANCE_ID \
--query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
--output text)


echo "Bastion ID: $BASTION_INSTANCE_ID"
echo "Bastion IP: $BASTION_PUBLIC_IP"
echo "VPC: $VPC_ID"


#############################################
# CREATE PRIVATE INSTANCE KEY
#############################################

PRIVATE_KEY_NAME="private-server-key"
PRIVATE_KEY="./${PRIVATE_KEY_NAME}.pem"


echo "Creating private key..."

aws ec2 create-key-pair \
--region $AWS_REGION \
--key-name $PRIVATE_KEY_NAME \
--query KeyMaterial \
--output text > $PRIVATE_KEY


chmod 400 $PRIVATE_KEY


echo "Private key created: $PRIVATE_KEY"


#############################################
# FIND PRIVATE SUBNET
#############################################

PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets \
--region $AWS_REGION \
--filters \
"Name=vpc-id,Values=$VPC_ID" \
--query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId | [0]" \
--output text)


echo "Private subnet: $PRIVATE_SUBNET_ID"



#############################################
# FIND AMAZON LINUX AMI
#############################################

AMI_ID=$(aws ec2 describe-images \
--region $AWS_REGION \
--owners amazon \
--filters \
"Name=name,Values=al2023-ami-*-x86_64" \
"Name=state,Values=available" \
--query "Images | sort_by(@,&CreationDate)[-1].ImageId" \
--output text)


echo "AMI: $AMI_ID"



#############################################
# CREATE PRIVATE SECURITY GROUP
#############################################

PRIVATE_SG=$(aws ec2 create-security-group \
--region $AWS_REGION \
--group-name private-instance-sg \
--description "Allow SSH only from bastion" \
--vpc-id $VPC_ID \
--query GroupId \
--output text)


aws ec2 authorize-security-group-ingress \
--region $AWS_REGION \
--group-id $PRIVATE_SG \
--protocol tcp \
--port 22 \
--source-group $BASTION_SG



#############################################
# LAUNCH PRIVATE EC2
#############################################

PRIVATE_INSTANCE_ID=$(aws ec2 run-instances \
--region $AWS_REGION \
--image-id $AMI_ID \
--instance-type t2.micro \
--subnet-id $PRIVATE_SUBNET_ID \
--security-group-ids $PRIVATE_SG \
--key-name $PRIVATE_KEY_NAME \
--associate-public-ip-address false \
--query "Instances[0].InstanceId" \
--output text)


echo "Private instance: $PRIVATE_INSTANCE_ID"



#############################################
# GET PRIVATE IP
#############################################

aws ec2 wait instance-running \
--region $AWS_REGION \
--instance-ids $PRIVATE_INSTANCE_ID


PRIVATE_IP=$(aws ec2 describe-instances \
--region $AWS_REGION \
--instance-ids $PRIVATE_INSTANCE_ID \
--query "Reservations[0].Instances[0].PrivateIpAddress" \
--output text)


echo "Private IP: $PRIVATE_IP"



#############################################
# COPY PRIVATE KEY TO BASTION
#############################################

echo "Copying private key to bastion..."

scp \
-o StrictHostKeyChecking=no \
-i bastion-key.pem \
$PRIVATE_KEY \
ec2-user@$BASTION_PUBLIC_IP:/home/ec2-user/private.pem



#############################################
# SSH HOP TEST
#############################################

ssh \
-i bastion-key.pem \
-o StrictHostKeyChecking=no \
ec2-user@$BASTION_PUBLIC_IP <<EOF

chmod 400 /home/ec2-user/private.pem

ssh \
-i /home/ec2-user/private.pem \
-o StrictHostKeyChecking=no \
ec2-user@$PRIVATE_IP <<INNER

echo "Inside private instance"

echo "Checking internet through NAT..."

curl -I https://aws.amazon.com

echo "External IP:"
curl https://checkip.amazonaws.com

INNER

EOF


echo "================================="
echo "DONE"
echo "Bastion ID: $BASTION_INSTANCE_ID"
echo "Private ID: $PRIVATE_INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"
echo "================================="
