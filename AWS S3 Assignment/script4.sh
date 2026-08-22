#!/bin/bash
set -e

read -p "Enter existing S3 bucket name: " BUCKET_NAME

echo "Bucket Selected: $BUCKET_NAME"


cat > bucket-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicWriteAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF


echo "Policy File Created"


aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file://bucket-policy.json


echo "Bucket Policy Updated Successfully"


aws s3api get-bucket-policy \
    --bucket $BUCKET_NAME


echo "Completed"


