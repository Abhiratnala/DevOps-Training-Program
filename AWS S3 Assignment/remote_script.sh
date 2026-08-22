#!/bin/bash

BUCKET="bucket-$(date +%s)"

# Create S3 bucket
aws s3 mb s3://$BUCKET

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create Access Point
aws s3control create-access-point \
    --account-id $ACCOUNT_ID \
    --name my-access-point \
    --bucket $BUCKET

echo "Bucket: $BUCKET"
echo "Access Point created successfully."

