#!/bin/bash
# Run this AFTER vpc_peering_lab.sh, with the same variables (REGION, KEY, etc.)
# Proves VPC-C (unrelated, not peered) still cannot reach VPC-A's instance,
# even though VPC-A <-> VPC-B peering is working.
#
# Fill these in from vpc_peering_lab.sh's output:
REGION="ap-southeast-2"
AZ="${REGION}a"
KEY="lab-key"
KEY_FILE="./${KEY}.pem"
INSTANCE_TYPE="t3.micro"
VPCA_PRIV_IP="<paste VPC-A instance private IP here>"   # target we try to reach

VPCC_CIDR="10.2.0.0/16"
VPCC_SUBNET_CIDR="10.2.1.0/24"

set -e

AMI=$(aws ec2 describe-images --region $REGION --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' --output text)

VPCC_ID=$(aws ec2 create-vpc --region $REGION --cidr-block $VPCC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=VPC-C}]" \
  --query 'Vpc.VpcId' --output text)
aws ec2 wait vpc-available --region $REGION --vpc-ids $VPCC_ID

VPCC_SUBNET=$(aws ec2 create-subnet --region $REGION --vpc-id $VPCC_ID \
  --cidr-block $VPCC_SUBNET_CIDR --availability-zone $AZ \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $VPCC_SUBNET --map-public-ip-on-launch

IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region $REGION --vpc-id $VPCC_ID --internet-gateway-id $IGW_ID
RT_ID=$(aws ec2 create-route-table --region $REGION --vpc-id $VPCC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID >/dev/null
aws ec2 associate-route-table --region $REGION --route-table-id $RT_ID --subnet-id $VPCC_SUBNET >/dev/null

SG_ID=$(aws ec2 create-security-group --region $REGION --group-name "VPC-C-SG" \
  --description "SG for VPC-C" --vpc-id $VPCC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null

INSTANCE_ID=$(aws ec2 run-instances --region $REGION --image-id $AMI \
  --instance-type $INSTANCE_TYPE --key-name $KEY --subnet-id $VPCC_SUBNET \
  --security-group-ids $SG_ID --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=VPC-C-Instance}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

PUB_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "VPC-C Instance public IP: $PUB_IP"
echo "Waiting for SSH..."
until nc -z -w 3 "$PUB_IP" 22 2>/dev/null; do sleep 5; done
sleep 10

echo "From VPC-C (NOT peered with VPC-A), curling VPC-A private IP ($VPCA_PRIV_IP)..."
set +e
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$PUB_IP" \
  "curl -s --max-time 6 http://$VPCA_PRIV_IP || echo 'FAILED (expected - no peering, no route to VPC-A)'"
set -e

echo ""
echo "This confirms peering is point-to-point and non-transitive: VPC-A <-> VPC-B"
echo "communicate fine, but VPC-C has no route to either, since no peering (or"
echo "route table entry) exists for VPC-C. AWS VPC peering never auto-propagates"
echo "to a third VPC even if that third VPC peers with one of the two."

echo ""
echo "Cleanup: terminate $INSTANCE_ID, then delete SG $SG_ID, RT $RT_ID,"
echo "detach/delete IGW $IGW_ID, subnet $VPCC_SUBNET, and VPC $VPCC_ID."
