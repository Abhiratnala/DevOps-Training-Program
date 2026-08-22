provider "aws" {
  region = "ap-southeast-2"
}
resource "aws_iam_user" "admin_user" {
  name = "terraform-admin-user"

  tags = {
    Name = "Terraform IAM User"
  }
}
resource "aws_iam_user_policy_attachment" "admin_access" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_user_policy_attachment" "ec2_full_access" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}
resource "aws_iam_access_key" "admin_key" {
  user = aws_iam_user.admin_user.name
}

output "access_key_id" {
  value = aws_iam_access_key.admin_key.id
}
