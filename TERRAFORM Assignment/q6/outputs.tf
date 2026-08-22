output "instance_public_ip" {
  value = aws_instance.app_server.public_ip
}

output "instance_private_ip" {
  value = aws_instance.app_server.private_ip
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.app_bucket.arn
}
