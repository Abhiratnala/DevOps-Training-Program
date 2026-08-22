#!/bin/bash
bucketname="1003secondbucket"
region="ap-southeast-2"
aws s3 mb "s3://$bucketname" --region "$region"
aws s3api delete-public-access-block \
    --bucket "$bucketname"
# Apply the bucket policy using a Here-Doc
aws s3api put-bucket-policy --bucket "$bucketname" --policy "$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicRead",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${bucketname}/*"
        }
    ]
}
EOF
)"
cat > a.txt << EOF
This is file1 
EOF
cat > b.txt << EOF
This is file2 
EOF
cat > c.txt << EOF
This is file3 
EOF
aws s3 cp a.txt s3://$bucketname/
aws s3 cp b.txt s3://$bucketname/
aws s3 cp c.txt s3://$bucketname/


