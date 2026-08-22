# IMPORTANT BOOTSTRAP NOTE:
# The S3 bucket and DynamoDB table referenced here must exist BEFORE
# `terraform init`, because Terraform must initialize the backend before
# it can create resources managed by this state.
#
# Create them once (outside this state), then replace the bucket name below.
# The assignment requires DynamoDB locking, so dynamodb_table is retained
# even though modern Terraform also supports S3 lockfiles.
terraform {
  backend "s3" {
    bucket         = "nimbuscart-1003"
    key            = "nimbuscart/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "nimbuscart-terraform-lock"
  }
}
