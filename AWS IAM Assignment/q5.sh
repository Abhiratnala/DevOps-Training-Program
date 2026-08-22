#!/bin/bash
USER_NAME="admin-user"
POLICY_NAME="CustomAdministratorAccess"
POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "*",
                "Resource": "*"
            }
        ]
    }' \
    --query 'Policy.Arn' \
    --output text)
echo "Policy created: $POLICY_ARN"
aws iam create-user --user-name "$USER_NAME"

echo "User created: $USER_NAME"
aws iam attach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "$POLICY_ARN"

echo "Policy attached successfully."
echo ""
echo "User: $USER_NAME"
echo "Policy ARN: $POLICY_ARN"
