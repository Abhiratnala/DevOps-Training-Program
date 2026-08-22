#!/usr/bin/env bash
BUCKET_NAME="1003-fourth-bucket"
REGION="ap-southeast-2"
WORK_DIR="$(mktemp -d)"
POLICY_FILE="${WORK_DIR}/bucket_policy.json"

echo "==> Bucket:  ${BUCKET_NAME}"
echo "==> Region:  ${REGION}"
echo "==> Creating bucket..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
echo "==> Disabling block-public-access (needed for public website hosting)..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
echo "==> Enabling static website hosting..."
aws s3api put-bucket-website \
  --bucket "${BUCKET_NAME}" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Key": "error.html"}
  }'
cat > "${POLICY_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
echo "==> Attaching public-read bucket policy..."
aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy "file://${POLICY_FILE}"
echo "==> Creating index.html and error.html..."
cat > "${WORK_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Hello S3</title></head>
<body>
  <h1>It works!</h1>
  <p>This is a static website.</p>
</body>
</html>
EOF

cat > "${WORK_DIR}/error.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>404</title></head>
<body>
  <h1>Error</h1>
</body>
</html>
EOF

echo "==> Uploading site files..."
aws s3 cp "${WORK_DIR}/index.html" "s3://${BUCKET_NAME}/index.html" --content-type "text/html"
aws s3 cp "${WORK_DIR}/error.html" "s3://${BUCKET_NAME}/error.html" --content-type "text/html"

# ---------- 6. Print the website endpoint ----------
WEBSITE_ENDPOINT="http://${BUCKET_NAME}.s3-website.${REGION}.amazonaws.com"
# Note: some older regions use a dash format s3-website-<region>; AWS
# resolves either, but the dot form above is the current standard.

echo ""
echo "==> Done!"
echo "==> Website endpoint: ${WEBSITE_ENDPOINT}"
echo "==> Test with:  curl ${WEBSITE_ENDPOINT}"

rm -rf "${WORK_DIR}"
