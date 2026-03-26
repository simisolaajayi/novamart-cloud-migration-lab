output "instance_public_ip" {
  description = "Public IP of the NovaMart application server"
  value       = aws_instance.novamart_app.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the NovaMart application server"
  value       = aws_instance.novamart_app.public_dns
}

output "application_url" {
  description = "URL to access the NovaMart application"
  value       = "http://${aws_instance.novamart_app.public_ip}:3000"
}

output "vpc_id" {
  description = "ID of the NovaMart VPC"
  value       = aws_vpc.novamart.id
}

output "security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.novamart_app.id
}
