output "alb_dns_name" {
  description = "DNS público del ALB — endpoint de acceso al servicio"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN del ALB"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN del Target Group — lo consume el ECS service"
  value       = aws_lb_target_group.api.arn
}

output "alb_sg_id" {
  description = "ID del Security Group del ALB — lo consume ECS para restringir inbound"
  value       = aws_security_group.alb.id
}
