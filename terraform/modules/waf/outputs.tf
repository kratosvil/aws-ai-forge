output "web_acl_arn" {
  description = "ARN del WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "ID del WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}
