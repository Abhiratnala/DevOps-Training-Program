#!/bin/bash
# CONFIGURATION

AWS_REGION="ap-southeast-2"

VPC_CIDR="10.0.0.0/16"

PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

AZ="${AWS_REGION}a"

VPC_NAME="bit5-vpc"

PUBLIC_SUBNET_NAME="bit5-public-subnet"
PRIVATE_SUBNET_NAME="bit5-private-subnet"

AMI_ID=$(aws ec2 describe-images \
--region $AWS_REGION \
--owners amazon \
--filters \
"Name=name,Values=al2023-ami-*-x86_64" \
"Name=state,Values=available" \
--query "Images | sort_by(@,&CreationDate)[-1].ImageId" \
--output text)

KEY_NAME="bit5-key"
INSTANCE_TYPE="t2.micro"


#############################################
# FUNCTIONS
#############################################

create_vpc() {

    echo "Checking VPC..."

    VPC_ID=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --query "Vpcs[0].VpcId" \
    --output text)


    if [ "$VPC_ID" == "None" ]; then

        echo "Creating VPC..."

        VPC_ID=$(aws ec2 create-vpc \
        --region $AWS_REGION \
        --cidr-block $VPC_CIDR \
        --query "Vpc.VpcId" \
        --output text)


        aws ec2 create-tags \
        --resources $VPC_ID \
        --tags Key=Name,Value=$VPC_NAME

    else

        echo "VPC exists: $VPC_ID"

    fi
}


create_subnets() {

    echo "Checking subnets..."


    PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters \
    "Name=tag:Name,Values=$PUBLIC_SUBNET_NAME" \
    --query "Subnets[0].SubnetId" \
    --output text)


    if [ "$PUBLIC_SUBNET_ID" == "None" ]; then

        echo "Creating public subnet..."

        PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --region $AWS_REGION \
        --vpc-id $VPC_ID \
        --cidr-block $PUBLIC_SUBNET_CIDR \
        --availability-zone $AZ \
        --query "Subnet.SubnetId" \
        --output text)


        aws ec2 create-tags \
        --resources $PUBLIC_SUBNET_ID \
        --tags Key=Name,Value=$PUBLIC_SUBNET_NAME

    fi



    PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters \
    "Name=tag:Name,Values=$PRIVATE_SUBNET_NAME" \
    --query "Subnets[0].SubnetId" \
    --output text)



    if [ "$PRIVATE_SUBNET_ID" == "None" ]; then

        echo "Creating private subnet..."

        PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
        --region $AWS_REGION \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_CIDR \
        --availability-zone $AZ \
        --query "Subnet.SubnetId" \
        --output text)


        aws ec2 create-tags \
        --resources $PRIVATE_SUBNET_ID \
        --tags Key=Name,Value=$PRIVATE_SUBNET_NAME

    fi

}


setup_igw_and_route() {

    echo "Checking Internet Gateway..."


    IGW_ID=$(aws ec2 describe-internet-gateways \
    --region $AWS_REGION \
    --filters \
    "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text)



    if [ "$IGW_ID" == "None" ]; then

        echo "Creating IGW..."

        IGW_ID=$(aws ec2 create-internet-gateway \
        --region $AWS_REGION \
        --query "InternetGateway.InternetGatewayId" \
        --output text)


        aws ec2 attach-internet-gateway \
        --region $AWS_REGION \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID

    fi



    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --region $AWS_REGION \
    --filters \
    "Name=tag:Name,Values=public-route-table" \
    --query "RouteTables[0].RouteTableId" \
    --output text)



    if [ "$ROUTE_TABLE_ID" == "None" ]; then

        ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --region $AWS_REGION \
        --vpc-id $VPC_ID \
        --query "RouteTable.RouteTableId" \
        --output text)


        aws ec2 create-tags \
        --resources $ROUTE_TABLE_ID \
        --tags Key=Name,Value=public-route-table


        aws ec2 create-route \
        --region $AWS_REGION \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID


        aws ec2 associate-route-table \
        --route-table-id $ROUTE_TABLE_ID \
        --subnet-id $PUBLIC_SUBNET_ID

    fi

}


setup_nat_and_route() {

    echo "Checking NAT Gateway..."


    EIP_ALLOC=$(aws ec2 describe-addresses \
    --region $AWS_REGION \
    --query "Addresses[0].AllocationId" \
    --output text)



    if [ "$EIP_ALLOC" == "None" ]; then

        EIP_ALLOC=$(aws ec2 allocate-address \
        --region $AWS_REGION \
        --domain vpc \
        --query AllocationId \
        --output text)

    fi



    NAT_ID=$(aws ec2 describe-nat-gateways \
    --region $AWS_REGION \
    --filter \
    "Name=vpc-id,Values=$VPC_ID" \
    --query "NatGateways[?State!='deleted'].NatGatewayId" \
    --output text)



    if [ "$NAT_ID" == "None" ]; then

        NAT_ID=$(aws ec2 create-nat-gateway \
        --region $AWS_REGION \
        --subnet-id $PUBLIC_SUBNET_ID \
        --allocation-id $EIP_ALLOC \
        --query "NatGateway.NatGatewayId" \
        --output text)


        aws ec2 wait nat-gateway-available \
        --region $AWS_REGION \
        --nat-gateway-ids $NAT_ID

    fi



    PRIVATE_RT=$(aws ec2 create-route-table \
    --region $AWS_REGION \
    --vpc-id $VPC_ID \
    --query RouteTable.RouteTableId \
    --output text)



    aws ec2 create-route \
    --region $AWS_REGION \
    --route-table-id $PRIVATE_RT \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_ID


    aws ec2 associate-route-table \
    --region $AWS_REGION \
    --route-table-id $PRIVATE_RT \
    --subnet-id $PRIVATE_SUBNET_ID

}


launch_instances() {

    echo "Launching instances..."

    INSTANCE=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters \
    "Name=tag:Name,Values=private-server" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)



    if [ "$INSTANCE" == "None" ]; then

        INSTANCE=$(aws ec2 run-instances \
        --region $AWS_REGION \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --subnet-id $PRIVATE_SUBNET_ID \
        --key-name $KEY_NAME \
        --associate-public-ip-address false \
        --query "Instances[0].InstanceId" \
        --output text)


        aws ec2 create-tags \
        --resources $INSTANCE \
        --tags Key=Name,Value=private-server

    else

        echo "Instance exists: $INSTANCE"

    fi

}

# EXECUTION

create_vpc

create_subnets

setup_igw_and_route

setup_nat_and_route

launch_instances


echo "VPC provisioning complete using fucntions"

