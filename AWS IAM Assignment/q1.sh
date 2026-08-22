#!/bin/bash
aws iam create-user --user-name Test
aws iam attach-user-policy \
--user-name Test \
--policy-arn arn:aws:iam::aws:policy/AdministratorAccess
echo "Policies attached successfully"
echo "IAM USER REPORT"
aws iam get-user \
--user-name Test \
--query 'User.[UserName,Arn]' \
--output table


