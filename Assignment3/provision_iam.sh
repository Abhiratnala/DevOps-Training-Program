#!/bin/bash

# 1: Parse & validate with core Linux tools
sed 's/\r$//' users.csv | sed 's/[[:space:]]*$//' > valid_users.csv

n=$(awk 'NR>1 {count++} END {print count}' valid_users.csv)

echo "Processing Users= $n"

valid=0
rejected=0

# why rejected rows are deleted
while read record
do
    username=$(echo $record | cut -d ',' -f1)
    dept=$(echo $record | cut -d ',' -f2)
    access=$(echo $record | cut -d ',' -f3)

    if ! echo "$username" | grep -Eq '^[a-z]+\.[a-z]+$'
    then
        echo "$record - Rejected (invalid username)"
        ((rejected++))

    elif [ -z "$dept" ]
    then
        echo "$record - Rejected (invalid department)"
        ((rejected++))

    elif ! echo "$access" | grep -Eq '^(readonly|poweruser|admin)$'
    then
        echo "$record - Rejected (Invalid access level)"
        ((rejected++))

    else
        echo "$record - Accepted"
        echo "$record" >> new_valid_users.csv
        ((valid++))
    fi

done< <(tail -n +1 valid_users.csv)

echo "Valid rows : $valid"
echo "Rejected rows : $rejected"

# creating custom policy
tail -n +1 new_valid_users.csv | while read record 
do
    username=$(echo $record | cut -d ',' -f1)
    dept=$(echo $record | cut -d ',' -f2)
    access=$(echo $record | cut -d ',' -f3)

    aws iam get-user --user-name "$username" >/dev/null 2>&1

    if [ $? -eq 0 ]
    then
        echo "SKIPPED,$username,Already Exists" >> provision.log
        continue
    fi

    aws iam create-user --user-name "$username"

    if [ $? -ne 0 ]
    then
        echo "FAILED,$username,User Creation" >> errors.log
        continue
    fi

    # attaching policies as per the requirement in csv files.
    case $access in

        readonly)

            aws iam attach-user-policy \
                --user-name "$username" \
                --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
            ;;

        poweruser)

            aws iam attach-user-policy \
                --user-name "$username" \
                --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
            ;;

        admin)

            cat <<EOF > policy.json
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":"s3:*",
            "Resource":[
                "arn:aws:s3:::$dept-bucket",
                "arn:aws:s3:::$dept-bucket/*"
            ]
        }
    ]
}
EOF

            policyArn=$(aws iam create-policy \
                --policy-name "${dept}_AdminPolicy" \
                --policy-document file://policy.json \
                --query 'Policy.Arn' \
                --output text)

            if [ $? -ne 0 ]
            then
                echo "FAILED,$username,Policy Creation" >> errors.log
                continue
            fi

            aws iam attach-user-policy \
                --user-name "$username" \
                --policy-arn "$policyArn"
            ;;

    esac

    if [ $? -eq 0 ]
    then
        echo "SUCCESS,$username,$access" >> provision.log
    else
        echo "FAILED,$username,Policy Attach" >> errors.log
    fi

done
echo "Username              | Policy Attached"

grep "SUCCESS" provision.log | awk -F',' '{print $2 " | " $3}' | column -t -s '|'
