#!/bin/bash

bucketname="1003thirdbucket"
region="ap-southeast-2"

# Create bucket
aws s3 mb "s3://$bucketname" --region "$region"

# Remove block public access
aws s3api delete-public-access-block \
    --bucket "$bucketname"

# Attach bucket policy
aws s3api put-bucket-policy \
--bucket "$bucketname" \
--policy "$(cat <<EOF
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

# Create website files
cat > index.html <<EOF
<html>
<body>
<h1>Hello from S3 Static Website</h1>
</body>
</html>
EOF

cat > 404.html <<EOF
<html>
<body>
<h1>404 - Page Not Found</h1>
</body>
</html>
EOF

# Enable website hosting
aws s3 website s3://$bucketname/ \
--index-document index.html \
--error-document 404.html

# Upload website files
aws s3 cp index.html s3://$bucketname/
aws s3 cp 404.html s3://$bucketname/

# Print website URL
echo "Website Endpoint:"
echo "http://${bucketname}.s3-website-${region}.amazonaws.com"

