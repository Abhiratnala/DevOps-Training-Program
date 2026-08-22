#!/usr/bin/env bash

set -euo pipefail

# ---------- Config ----------
BUCKET_NAME="1003-first-bucket"
REGION="ap-southeast-2"
WORK_DIR="$(mktemp -d)"
POLICY_FILE="${WORK_DIR}/bucket_policy.json"

echo "==> Bucket:  ${BUCKET_NAME}"
echo "==> Region:  ${REGION}"
echo "==> Workdir: ${WORK_DIR}"
echo "==> Creating bucket..."
if [[ "${REGION}" == "us-east-1" ]]; then
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}"
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
cat > "${POLICY_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OwnerFullAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${ACCOUNT_ID}:root" },
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
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
echo "==> Attaching bucket policy..."
aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy "file://${POLICY_FILE}"
echo "==> Creating sample files..."
echo "This is file one."   > "${WORK_DIR}/file1.txt"
echo "This is file two."   > "${WORK_DIR}/file2.txt"
echo "This is file three." > "${WORK_DIR}/file3.txt"
echo "==> Uploading files..."
for f in file1.txt file2.txt file3.txt; do
  aws s3 cp "${WORK_DIR}/${f}" "s3://${BUCKET_NAME}/${f}"
done
echo "==> Done. Bucket contents:"
aws s3 ls "s3://${BUCKET_NAME}/"
rm -rf "${WORK_DIR}"
