#!/bin/bash
set -e

########################################
# EDIT THESE BEFORE RUNNING
########################################
REGION="ap-southeast-2"
KEY_NAME="lab-key"
INSTANCE_TYPE="t3.micro"
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
########################################

AMI_ID=$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query "Parameters[0].Value" --output text)

echo ">> Using Ubuntu 22.04 AMI: $AMI_ID"

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text)

SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "Subnets[0].SubnetId" --output text)

SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values=docker-demo-sg Name=vpc-id,Values="$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" \
    --group-name docker-demo-sg \
    --description "Docker getting-started demo" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP"

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" --protocol tcp --port 80 --cidr "$MY_IP"
else
  echo ">> Reusing existing security group: $SG_ID"
fi

cat > /tmp/userdata_docker.sh <<'EOF'
#!/bin/bash
apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Run the official getting-started tutorial app as a container
docker run -d -p 80:80 --name getting-started docker/getting-started
EOF

INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --user-data file:///tmp/userdata_docker.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=docker-demo}]" \
  --query "Instances[0].InstanceId" --output text)

echo ">> Instance launched: $INSTANCE_ID"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "=================================================="
echo "Instance running at: $PUBLIC_IP"
echo "Wait ~1-2 min for user-data to finish, then check:"
echo "  http://$PUBLIC_IP"
echo ""
echo "SSH in with:"
echo "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
echo ""
echo "Then push the container image to Docker Hub manually"
echo "(credentials should never be embedded in user-data):"
echo "  docker login"
echo "  docker commit getting-started <your-dockerhub-username>/getting-started-demo"
echo "  docker push <your-dockerhub-username>/getting-started-demo"
echo "=================================================="
