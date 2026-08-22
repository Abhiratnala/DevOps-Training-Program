#!/bin/bash
bucketname=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 10; echo "")
region="ap-southeast-2"
aws s3 mb "s3://$bucketname" --region "$region"
bucket_name=$(aws s3 ls | tail -n1 | awk '{print $3}')
echo "$bucket_name"
aws s3 cp a.txt s3://$bucket_name/
aws s3 ls
aws s3 rm s3://$bucketname/ --recursive
aws s3 rb s3://$bucketname

