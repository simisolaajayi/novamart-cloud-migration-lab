output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.novamart.dns_name
}

output "application_url" {
  description = "URL to access NovaMart through the load balancer"
  value       = "http://${aws_lb.novamart.dns_name}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.novamart.endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.novamart.db_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.novamart.id
}
