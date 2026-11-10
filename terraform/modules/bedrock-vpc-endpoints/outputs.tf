output "endpoint_ids" {
  description = "Map of service name to VPC endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.this : k => v.id }
}

output "security_group_id" {
  description = "Security group attached to the endpoints."
  value       = aws_security_group.this.id
}
