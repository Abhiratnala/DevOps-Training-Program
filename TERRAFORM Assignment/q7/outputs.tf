output "instance_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "instance_private_ip" {
  value = aws_instance.web_server.private_ip
}
