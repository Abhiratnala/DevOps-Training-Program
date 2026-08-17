#!/bin/bash

REGION="ap-southeast-2"
INSTANCE_TYPE="t3.micro"
INSTANCE_NAME="ubuntu-server"

KEY_NAME="assign-4$(date +%s)"
SG_NAME="assign4-sg-$(date +%s)"

# ==========================
# Find latest Ubuntu 24.04 LTS AMI
# ==========================

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


# ==========================
# Create VPC
# CHANGE: VPC CIDR fixed
# ==========================

vpc_id=$(aws ec2 create-vpc \
 --cidr-block 10.0.0.0/16 \
 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
 --output text)


# ==========================
# Create Public Subnet
# ==========================

public_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.0.0/24 \
  --availability-zone ap-southeast-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet}]' \
  --query 'Subnet.SubnetId' \
  --output text)



# ==========================
# Internet Gateway
# ==========================

ig=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=MyIGW}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)


aws ec2 attach-internet-gateway \
 --internet-gateway-id "$ig" \
 --vpc-id "$vpc_id"



# ==========================
# Public Route Table
# ==========================

rt=$(aws ec2 create-route-table \
 --vpc-id "$vpc_id" \
 --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]' \
 --query 'RouteTable.RouteTableId' \
 --output text)


aws ec2 create-route \
 --route-table-id "$rt" \
 --destination-cidr-block 0.0.0.0/0 \
 --gateway-id "$ig"


aws ec2 associate-route-table \
 --route-table-id "$rt" \
 --subnet-id "$public_subnet"



# ==========================
# Create Key Pair
# ==========================

echo "Creating key pair..."

aws ec2 create-key-pair \
    --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query "KeyMaterial" \
    --output text > "${KEY_NAME}.pem"


chmod 400 "${KEY_NAME}.pem"



# ==========================
# Security Group
# ==========================

SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "Ubuntu EC2 Security Group" \
    --vpc-id "$vpc_id" \
    --query "GroupId" \
    --output text)


echo "Security Group: $SG_ID"



# SSH

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0



# HTTP

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0



# CHANGE: Added HTTPS rule

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0




# ==========================
# User Data
# CHANGE: Install and start nginx
# ==========================

cat > userdata.sh <<EOF
#!/bin/bash

apt update -y

apt install nginx -y

systemctl enable nginx

systemctl start nginx

echo "<h1>Nginx running successfully</h1>" > /var/www/html/index.html

EOF




# ==========================
# Launch EC2
# ==========================

echo "Launching EC2..."

INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$public_subnet" \
    --associate-public-ip-address \
    --user-data file://userdata.sh \
    --block-device-mappings '[
        {
            "DeviceName": "/dev/sda1",
            "Ebs": {
                "VolumeSize":8,
                "VolumeType":"gp3",
                "DeleteOnTermination":true
            }
        }
    ]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)



echo "Instance ID: $INSTANCE_ID"



# ==========================
# Wait for Instance
# ==========================

aws ec2 wait instance-running \
 --region "$REGION" \
 --instance-ids "$INSTANCE_ID"



# CHANGE: Wait for user-data nginx installation

echo "Waiting for nginx installation..."
sleep 30



# ==========================
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
echo "Public IP   : $PUBLIC_IP"
echo "Key         : ${KEY_NAME}.pem"
echo
echo "Open in browser:"
echo "http://$PUBLIC_IP"
echo
echo "SSH:"
echo "ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
echo "======================================"



# CHANGE: Verify nginx

curl http://$PUBLIC_IP
