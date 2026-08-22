output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "peering_connection_id" {
  value = {
    web_app  = aws_vpc_peering_connection.web_app.id
    app_data = aws_vpc_peering_connection.app_data.id
  }
}

output "nat_gateway_public_ip" {
  value = aws_eip.nat.public_ip
}

output "frontend_url" {
  value = "http://${aws_instance.web.public_ip}"
}
