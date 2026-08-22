vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
  --output text) 
  public_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.0.0/24 \
  --availability-zone ap-southeast-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-AZ1}]' \
   --query 'Subnet.SubnetId' \
  --output text)
  
 #create a private subnet 
 private_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ap-southeast-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-AZ1}]' \
   --query 'Subnet.SubnetId' \
  --output text)
  {
    echo "PUBLIC_SUBNET_ID=$public_subnet"
    echo "PRIVATE_SUBNET_ID=$private_subnet"
} >> vars.env
