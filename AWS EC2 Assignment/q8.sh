#!/bin/bash
REGION="ap-southeast-2"
AZ="${REGION}a"
KEY="lab-key"
KEY_FILE="./${KEY}.pem"
INSTANCE_TYPE="t3.micro"

VPCA_CIDR="10.0.0.0/16"
VPCA_SUBNET_CIDR="10.0.1.0/24"
VPCB_CIDR="10.1.0.0/16"
VPCB_SUBNET_CIDR="10.1.1.0/24"

AMI=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)
echo "Using AMI: $AMI"

USER_DATA_A='#!/bin/bash
apt update -y
apt install -y nginx
echo "Hello from VPC-A Web Server" > /var/www/html/index.html
systemctl enable nginx
systemctl restart nginx'

USER_DATA_B='#!/bin/bash
apt update -y
apt install -y nginx
echo "Hello from VPC-B DB Server" > /var/www/html/index.html
systemctl enable nginx
systemctl restart nginx'

ssh_run() {
  # ssh_run <public_ip> <remote_command>
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$1" "$2"
}

wait_for_ssh() {
  local ip=$1
  echo "Waiting for SSH on $ip..."
  until nc -z -w 3 "$ip" 22 2>/dev/null; do sleep 5; done
  sleep 5
}
build_vpc() {
  local NAME=$1 CIDR=$2 SUBNET_CIDR=$3 USERDATA=$4

  echo ""
  echo "===== Building $NAME ====="

  VPC_ID=$(aws ec2 create-vpc --region $REGION --cidr-block $CIDR \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$NAME}]" \
    --query 'Vpc.VpcId' --output text)
  aws ec2 wait vpc-available --region $REGION --vpc-ids $VPC_ID
  aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
  aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"
  echo "$NAME VPC ID: $VPC_ID"

  SUBNET_ID=$(aws ec2 create-subnet --region $REGION --vpc-id $VPC_ID \
    --cidr-block $SUBNET_CIDR --availability-zone $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${NAME}-Public}]" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --region $REGION --subnet-id $SUBNET_ID --map-public-ip-on-launch
  echo "$NAME Subnet ID: $SUBNET_ID"

  IGW_ID=$(aws ec2 create-internet-gateway --region $REGION \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${NAME}-IGW}]" \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --region $REGION --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

  RT_ID=$(aws ec2 create-route-table --region $REGION --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${NAME}-RT}]" \
    --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-route --region $REGION --route-table-id $RT_ID \
    --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID >/dev/null
  aws ec2 associate-route-table --region $REGION --route-table-id $RT_ID --subnet-id $SUBNET_ID >/dev/null

  SG_ID=$(aws ec2 create-security-group --region $REGION \
    --group-name "${NAME}-SG" --description "SG for $NAME" --vpc-id $VPC_ID \
    --query 'GroupId' --output text)
  # SSH open for management/setup only. HTTP is intentionally NOT open to 0.0.0.0/0 -
  # it gets added later, scoped only to the peer VPC's CIDR (Part C, step 4).
  aws ec2 authorize-security-group-ingress --region $REGION \
    --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null

  INSTANCE_ID=$(aws ec2 run-instances --region $REGION \
    --image-id $AMI --instance-type $INSTANCE_TYPE --key-name $KEY \
    --subnet-id $SUBNET_ID --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --user-data "$USERDATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}-Instance}]" \
    --query 'Instances[0].InstanceId' --output text)
  aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

  PUB_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  PRIV_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

  echo "$NAME Instance ID : $INSTANCE_ID"
  echo "$NAME Public IP   : $PUB_IP"
  echo "$NAME Private IP  : $PRIV_IP"
}
build_vpc "VPC-A" "$VPCA_CIDR" "$VPCA_SUBNET_CIDR" "$USER_DATA_A"
VPCA_ID=$VPC_ID; VPCA_SUBNET=$SUBNET_ID; VPCA_RT=$RT_ID; VPCA_SG=$SG_ID
VPCA_INSTANCE=$INSTANCE_ID; VPCA_PUB_IP=$PUB_IP; VPCA_PRIV_IP=$PRIV_IP

build_vpc "VPC-B" "$VPCB_CIDR" "$VPCB_SUBNET_CIDR" "$USER_DATA_B"
VPCB_ID=$VPC_ID; VPCB_SUBNET=$SUBNET_ID; VPCB_RT=$RT_ID; VPCB_SG=$SG_ID
VPCB_INSTANCE=$INSTANCE_ID; VPCB_PUB_IP=$PUB_IP; VPCB_PRIV_IP=$PRIV_IP

echo ""
echo "Waiting for both instances to finish boot (cloud-init)..."
wait_for_ssh "$VPCA_PUB_IP"
wait_for_ssh "$VPCB_PUB_IP"
ssh_run "$VPCA_PUB_IP" "sudo cloud-init status --wait" >/dev/null
ssh_run "$VPCB_PUB_IP" "sudo cloud-init status --wait" >/dev/null
echo "Both instances ready."
echo "===== PART B: Pre-peering connectivity test ====="
echo "From VPC-A instance, curling VPC-B instance's private IP ($VPCB_PRIV_IP)..."
set +e
RESULT_B=$(ssh_run "$VPCA_PUB_IP" "curl -s --max-time 6 http://$VPCB_PRIV_IP")
STATUS_B=$?
set -e

if [ $STATUS_B -ne 0 ] || [ -z "$RESULT_B" ]; then
  echo "RESULT: Connection FAILED / timed out (expected)."
else
  echo "RESULT: Unexpected success -> $RESULT_B"
fi

cat <<'EOF'

Why this fails:
Each VPC is an isolated network by default; there is no route in either VPC's
route table pointing at the other VPC's CIDR, so packets destined for
10.1.0.0/16 from inside VPC-A have nowhere to go and are simply dropped
locally (or sent out the default 0.0.0.0/0 route to the internet gateway,
where they are discarded since 10.1.x.x is a private, non-routable range).
This is independent of security groups - it's basic L3 routing isolation
that AWS enforces between VPCs unless you explicitly connect them (peering,
Transit Gateway, VPN, etc.).
EOF

# ============================================================
# PART C: Establish VPC Peering
# ============================================================
echo ""
echo "===== PART C: Creating VPC Peering Connection ====="

PCX_ID=$(aws ec2 create-vpc-peering-connection --region $REGION \
  --vpc-id $VPCA_ID --peer-vpc-id $VPCB_ID \
  --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=VPCA-VPCB-Peering}]" \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
echo "Peering Connection ID: $PCX_ID"

aws ec2 wait vpc-peering-connection-exists --region $REGION --vpc-peering-connection-ids $PCX_ID
aws ec2 accept-vpc-peering-connection --region $REGION --vpc-peering-connection-id $PCX_ID >/dev/null
echo "Peering connection accepted (same-account/same-region flow)."
# NOTE: for cross-account peering, the ACCEPTER account must run the
# accept-vpc-peering-connection call using their own credentials, after the
# REQUESTER account creates it. Same-account peering skips that hand-off.

echo "Adding routes..."
aws ec2 create-route --region $REGION --route-table-id $VPCA_RT \
  --destination-cidr-block $VPCB_CIDR --vpc-peering-connection-id $PCX_ID >/dev/null
aws ec2 create-route --region $REGION --route-table-id $VPCB_RT \
  --destination-cidr-block $VPCA_CIDR --vpc-peering-connection-id $PCX_ID >/dev/null
echo "VPC-A route table -> $VPCB_CIDR via $PCX_ID"
echo "VPC-B route table -> $VPCA_CIDR via $PCX_ID"

echo "Updating security groups (HTTP from peer CIDR only, not 0.0.0.0/0)..."
aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $VPCA_SG --protocol tcp --port 80 --cidr $VPCB_CIDR >/dev/null
aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $VPCB_SG --protocol tcp --port 80 --cidr $VPCA_CIDR >/dev/null
echo "VPC-A SG allows port 80 from $VPCB_CIDR"
echo "VPC-B SG allows port 80 from $VPCA_CIDR"

# ============================================================
# PART C (cont.): Post-peering connectivity test
# ============================================================
echo ""
echo "===== Post-peering connectivity test ====="

echo "From VPC-A instance -> VPC-B private IP ($VPCB_PRIV_IP):"
RESULT_A_TO_B=$(ssh_run "$VPCA_PUB_IP" "curl -s --max-time 6 http://$VPCB_PRIV_IP")
echo "  -> $RESULT_A_TO_B"

echo "From VPC-B instance -> VPC-A private IP ($VPCA_PRIV_IP):"
RESULT_B_TO_A=$(ssh_run "$VPCB_PUB_IP" "curl -s --max-time 6 http://$VPCA_PRIV_IP")
echo "  -> $RESULT_B_TO_A"

# ============================================================
# SUMMARY
# ============================================================
cat <<SUMMARY_EOF

============================================================
SUMMARY
============================================================
VPC-A: $VPCA_ID   Subnet: $VPCA_SUBNET   RT: $VPCA_RT   SG: $VPCA_SG
  Instance: $VPCA_INSTANCE  Public IP: $VPCA_PUB_IP  Private IP: $VPCA_PRIV_IP

VPC-B: $VPCB_ID   Subnet: $VPCB_SUBNET   RT: $VPCB_RT   SG: $VPCB_SG
  Instance: $VPCB_INSTANCE  Public IP: $VPCB_PUB_IP  Private IP: $VPCB_PRIV_IP

Peering Connection: $PCX_ID

Pre-peering  A -> B curl:  FAILED (expected)
Post-peering A -> B curl:  $RESULT_A_TO_B
Post-peering B -> A curl:  $RESULT_B_TO_A

Cleanup (run when done, in this order):
  aws ec2 delete-vpc-peering-connection --region $REGION --vpc-peering-connection-id $PCX_ID
  aws ec2 terminate-instances --region $REGION --instance-ids $VPCA_INSTANCE $VPCB_INSTANCE
  # wait for termination, then delete SGs, route table associations, subnets, IGWs (detach first), and VPCs.
SUMMARY_EOF
