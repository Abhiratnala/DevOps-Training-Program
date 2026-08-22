#!/bin/bash
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.1.0/24 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
  --output text)
 #create internet gateway
  ig=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=MyIGW}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
 
 #attach the internet gateway to the vpc that we just created
 aws ec2 attach-internet-gateway --internet-gateway-id "$ig" --vpc-id "$vpc_id"
 echo "VPC Id: $vpc_id"
 echo "Internet gate: $ig"
 echo "Internet gateway attched!"
 
