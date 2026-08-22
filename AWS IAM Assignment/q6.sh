#!/bin/bash
ROLE_NAME="EC2S3FullAccessRole"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonS3FullAccess"
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
echo "Creating IAM role..."
if aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json; then
    echo "Role created successfully."
else
    echo "Failed to create role."
    rm -f trust-policy.json
    exit 1
fi
echo "Attaching S3 policy..."
if aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"; then
    echo "Policy attached successfully."
else
    echo "Failed to attach policy."
    rm -f trust-policy.json
    exit 1
fi
echo "Listing attached policies..."
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
rm -f trust-policy.json
