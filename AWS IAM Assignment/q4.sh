#!/bin/bash

# List all IAM users and display their attached policies

for user in $(aws iam list-users --query "Users[*].UserName" --output text)
do
    echo "User: $user"
    echo "Attached Policies:"

    aws iam list-attached-user-policies \
        --user-name "$user" \
        --query "AttachedPolicies[*].PolicyArn" \
        --output text

done
