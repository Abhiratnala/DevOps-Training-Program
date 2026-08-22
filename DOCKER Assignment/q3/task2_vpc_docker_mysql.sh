#!/bin/bash
set -e

########################################
# EDIT THESE BEFORE RUNNING
########################################
REGION="ap-southeast-2"
AZ="ap-southeast-2a"
KEY_NAME="lab-key"
INSTANCE_TYPE="t3.micro"
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
AMI_ID=$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query "Parameters[0].Value" --output text)
   # Ubuntu 22.04 LTS, verify for your region
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
########################################

# ---- VPC ----
VPC_ID=$(aws ec2 create-vpc --region "$REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=docker-mysql-vpc}]" \
  --query "Vpc.VpcId" --output text)

aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"
echo ">> VPC created: $VPC_ID"

# ---- Subnet ----
SUBNET_ID=$(aws ec2 create-subnet --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET_CIDR" \
  --availability-zone "$AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=docker-mysql-subnet}]" \
  --query "Subnet.SubnetId" --output text)

aws ec2 modify-subnet-attribute --region "$REGION" \
  --subnet-id "$SUBNET_ID" --map-public-ip-on-launch

echo ">> Subnet created: $SUBNET_ID"

# ---- Internet Gateway ----
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=docker-mysql-igw}]" \
  --query "InternetGateway.InternetGatewayId" --output text)

aws ec2 attach-internet-gateway --region "$REGION" \
  --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

echo ">> Internet Gateway created and attached: $IGW_ID"

# ---- Route Table ----
RT_ID=$(aws ec2 create-route-table --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=docker-mysql-rt}]" \
  --query "RouteTable.RouteTableId" --output text)

aws ec2 create-route --region "$REGION" \
  --route-table-id "$RT_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"

aws ec2 associate-route-table --region "$REGION" \
  --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID"

echo ">> Route table created and associated: $RT_ID"

# ---- Security Group ----
SG_ID=$(aws ec2 create-security-group --region "$REGION" \
  --group-name docker-mysql-sg \
  --description "Docker + MySQL demo" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP"

echo ">> Security group created: $SG_ID"

# ---- User data: install Docker + MySQL, create and display a DB ----
cat > /tmp/userdata_docker_mysql.sh <<'EOF'
#!/bin/bash
apt-get update -y
apt-get install -y docker.io mysql-server

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

systemctl enable mysql
systemctl start mysql

# Create a database and record proof it exists
mysql -e "CREATE DATABASE IF NOT EXISTS demo_db;"
mysql -e "SHOW DATABASES;" > /home/ubuntu/db_output.txt
chown ubuntu:ubuntu /home/ubuntu/db_output.txt
EOF

# ---- Launch instance ----
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --user-data file:///tmp/userdata_docker_mysql.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=docker-mysql-instance}]" \
  --query "Instances[0].InstanceId" --output text)

echo ">> Instance launched: $INSTANCE_ID"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "=================================================="
echo "Instance running at: $PUBLIC_IP"
echo "Wait ~1-2 min for user-data to finish, then check the DB:"
echo "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
echo "  cat db_output.txt"
echo "=================================================="
