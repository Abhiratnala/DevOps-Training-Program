#create vpc
vpc_id=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/27 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
  --query 'Vpc.VpcId' \
  --output text)


#create a public subnet
public_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.0.0/28 \
  --availability-zone ap-southeast-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-AZ1}]' \
  --query 'Subnet.SubnetId' \
  --output text)


#create a private subnet
private_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.0.16/28 \
  --availability-zone ap-southeast-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-AZ1}]' \
  --query 'Subnet.SubnetId' \
  --output text)


# Create Internet Gateway
ig=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=MyIGW}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)


# Attach Internet Gateway
aws ec2 attach-internet-gateway \
  --internet-gateway-id "$ig" \
  --vpc-id "$vpc_id"


# Create Public Route Table
public_rt=$(aws ec2 create-route-table \
  --vpc-id "$vpc_id" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)


# Public subnet route -> Internet Gateway
aws ec2 create-route \
  --route-table-id "$public_rt" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$ig"


# Associate Public Route Table
aws ec2 associate-route-table \
  --route-table-id "$public_rt" \
  --subnet-id "$public_subnet"


# Enable auto-assign public IPs
aws ec2 modify-subnet-attribute \
  --subnet-id "$public_subnet" \
  --map-public-ip-on-launch


# Allocate Elastic IP
elastic_ip=$(aws ec2 allocate-address \
  --domain vpc \
  --query 'AllocationId' \
  --output text)


# Create NAT Gateway in Public Subnet
nat=$(aws ec2 create-nat-gateway \
  --subnet-id "$public_subnet" \
  --allocation-id "$elastic_ip" \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=MyNATGateway}]' \
  --query 'NatGateway.NatGatewayId' \
  --output text)


# Wait for NAT Gateway
aws ec2 wait nat-gateway-available \
  --nat-gateway-ids "$nat"


# Create Private Route Table
private_rt=$(aws ec2 create-route-table \
  --vpc-id "$vpc_id" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private-RT}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)


# Private subnet route -> NAT Gateway
aws ec2 create-route \
  --route-table-id "$private_rt" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$nat"


# Associate Private Route Table
aws ec2 associate-route-table \
  --route-table-id "$private_rt" \
  --subnet-id "$private_subnet"
