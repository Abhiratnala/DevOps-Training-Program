#!/bin/bash
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.1.0/24 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
  --output text) 
  #create a public subnet
public_subnet=$(aws ec2 create-subnet \
  --vpc-id "$vpc_id" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ap-southeast-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-AZ1}]' \
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
  #create the routing table
 rt=$(aws ec2 create-route-table \
  --vpc-id "$vpc_id" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public-RT}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)
  
  #add route 
  aws ec2 create-route --route-table-id "$rt" --destination-cidr-block 0.0.0.0/0 --gateway-id "$ig"
  #associate the route
  aws ec2 associate-route-table \
  --route-table-id "$rt" \
  --subnet-id "$public_subnet"
  
  #verification 
  aws ec2 describe-route-tables \
    --filters Name=association.subnet-id,Values="$public_subnet" \
    --query 'RouteTables[].{RouteTableId:RouteTableId,DestinationCIDR:Routes[].DestinationCidrBlock}' \
    --output table
