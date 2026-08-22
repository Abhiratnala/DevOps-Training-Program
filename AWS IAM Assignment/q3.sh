#!/bin/bash
GROUP_NAME="Testing"
USER1="Test1"
USER2="Test2"
POLICY_NAME="Tester-Policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
echo "Creating users..."
aws iam create-user \
  --user-name $USER1
aws iam create-user \
  --user-name $USER2
echo "Users created successfully."
echo "Creating group..."
aws iam create-group \
  --group-name $GROUP_NAME
echo "Group created successfully."
echo "Adding users to group..."
aws iam add-user-to-group \
  --user-name $USER1 \
  --group-name $GROUP_NAME
aws iam add-user-to-group \
  --user-name $USER2 \
  --group-name $GROUP_NAME
echo "Users added to group successfully."
echo "Attaching policy to group..."
aws iam attach-group-policy \
  --group-name $GROUP_NAME \
  --policy-arn $POLICY_ARN
echo "Tester-Policy attached to $GROUP_NAME group successfully."
echo "Users in group:"
aws iam get-group \
  --group-name $GROUP_NAME
echo "Attached policies:"
aws iam list-attached-group-policies \
  --group-name $GROUP_NAME
echo "Setup completed successfully."
