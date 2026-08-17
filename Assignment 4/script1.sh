#to create a vpc, create 2 subnets (private and public) attach the public one to #Internet gateway and the private one to Nat but NAT charges so we dont make it in #the free tier
#!/bin/bash

#create vpc
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.1.0/24 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
  --output text)

#create a public subnet
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
  
  #create internet gateway
  ig=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=MyIGW}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
 
 #attach the internet gateway to the vpc that we just created
 aws ec2 attach-internet-gateway --internet-gateway-id "$ig" --vpc-id "$vpc_id"
 
  #create the routing table
 rt=$(aws ec2 create-route-table \
  --vpc-id "$vpc_id" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)
  
  #add route 
  aws ec2 create-route --route-table-id "$rt" --destination-cidr-block 0.0.0.0/0 --gateway-id "$ig"
  
  #associate subnet 
  aws ec2 associate-route-table --route-table-id "$rt" --subnet-id ""

