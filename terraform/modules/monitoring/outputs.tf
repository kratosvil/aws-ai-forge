output "sns_topic_arn" {
  description = "ARN del SNS topic de alarmas"
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  description = "Nombre del CloudWatch Dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL directa al dashboard en la consola AWS"
  value       = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
