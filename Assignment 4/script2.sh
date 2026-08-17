vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
 --query 'Vpc.VpcId' \
  --output text)
  
 aws ec2 describe-vpcs --vpc-ids "$vpc_id" && echo "VPC verified with vpc id $vpc_id " || echo "VPC creation failed"
  
