
cat > s3_read.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Resource": "*"
    }
  ]
}

EOF

# Create trust policy for IAM role
cat > trust-policy.json << EOF
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

# Create IAM role
aws iam create-role \
    --role-name Test-role\
    --assume-role-policy-document file://trust-policy.json


aws iam create-policy \
    --policy-name Tester-policy \
    --policy-document file://s3_read.json

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Attach policy to role
aws iam attach-role-policy \
    --role-name Test-role \
    --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/Tester-policy

