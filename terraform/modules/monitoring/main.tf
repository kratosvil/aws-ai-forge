locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Sufijos ARN para dimensiones de metricas CloudWatch
  # ALB dimension: parte del ARN despues de "loadbalancer/"  → "app/<name>/<id>"
  # TG dimension:  parte del ARN despues de ":targetgroup/"  → "targetgroup/<name>/<id>"
  alb_arn_suffix = replace(var.alb_arn, "/^.*:loadbalancer\\//", "")
  tg_arn_suffix  = replace(var.target_group_arn, "/^.*:targetgroup\\//", "targetgroup/")
}

# ════════════════════════════════════════════════════════════════════════════════
# SNS — Topic de alertas + subscription por email
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_sns_topic" "alarms" {
  name         = "${local.name_prefix}-alarms"
  display_name = "${var.project_name} Alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ════════════════════════════════════════════════════════════════════════════════
# ALARMAS — Lambda
# ════════════════════════════════════════════════════════════════════════════════

# Errores en bedrock_handler (v1 /ask)
resource "aws_cloudwatch_metric_alarm" "lambda_bedrock_errors" {
  alarm_name          = "${local.name_prefix}-lambda-bedrock-errors"
  alarm_description   = "Lambda bedrock_handler supero ${var.lambda_error_threshold} errores en 5 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_bedrock_handler_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Errores en kb_query_handler (/search — RAG)
resource "aws_cloudwatch_metric_alarm" "lambda_kb_query_errors" {
  alarm_name          = "${local.name_prefix}-lambda-kb-query-errors"
  alarm_description   = "Lambda kb_query_handler supero ${var.lambda_error_threshold} errores en 5 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_kb_query_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Errores en kb_sync_handler (indexacion S3)
resource "aws_cloudwatch_metric_alarm" "lambda_kb_sync_errors" {
  alarm_name          = "${local.name_prefix}-lambda-kb-sync-errors"
  alarm_description   = "Lambda kb_sync_handler supero ${var.lambda_error_threshold} errores en 5 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_kb_sync_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Latencia alta en kb_query_handler — RetrieveAndGenerate puede ser lento
resource "aws_cloudwatch_metric_alarm" "lambda_kb_query_duration" {
  alarm_name          = "${local.name_prefix}-lambda-kb-query-duration"
  alarm_description   = "kb_query_handler supero 30s de duracion promedio en 5 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 30000 # 30 segundos en milisegundos
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_kb_query_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ════════════════════════════════════════════════════════════════════════════════
# ALARMAS — ECS
# ════════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  alarm_description   = "ECS CPU supero ${var.ecs_cpu_threshold}% por 10 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.ecs_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name_prefix}-ecs-memory-high"
  alarm_description   = "ECS Memory supero ${var.ecs_memory_threshold}% por 10 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.ecs_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ════════════════════════════════════════════════════════════════════════════════
# ALARMAS — ALB
# ════════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  alarm_description   = "ALB supero ${var.alb_5xx_threshold} errores 5XX en 5 min"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = local.tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-alb-unhealthy-hosts"
  alarm_description   = "ALB detecto targets no saludables — servicio posiblemente caido"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = local.tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ════════════════════════════════════════════════════════════════════════════════
# CLOUDWATCH DASHBOARD
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [

      # ── Fila 1: Lambda — Invocaciones y Errores ─────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — Invocaciones"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_bedrock_handler_name, { label = "bedrock-handler (/ask)" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_kb_query_name,         { label = "kb-query (/search)" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_kb_sync_name,          { label = "kb-sync (indexacion)" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — Errores"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_bedrock_handler_name, { label = "bedrock-handler", color = "#d62728" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_kb_query_name,         { label = "kb-query",        color = "#ff7f0e" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_kb_sync_name,          { label = "kb-sync",         color = "#e377c2" }],
          ]
        }
      },

      # ── Fila 2: Lambda — Duracion ───────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — Duracion promedio (ms)"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_bedrock_handler_name, { label = "bedrock-handler" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_kb_query_name,         { label = "kb-query (RAG)" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — Throttles"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_bedrock_handler_name, { label = "bedrock-handler" }],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_kb_query_name,         { label = "kb-query" }],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_kb_sync_name,          { label = "kb-sync" }],
          ]
        }
      },

      # ── Fila 3: ECS ─────────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "ECS — CPU Utilization (%)"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
          ]
          annotations = {
            horizontal = [{ value = var.ecs_cpu_threshold, label = "Umbral alarma", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "ECS — Memory Utilization (%)"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
          ]
          annotations = {
            horizontal = [{ value = var.ecs_memory_threshold, label = "Umbral alarma", color = "#d62728" }]
          }
        }
      },

      # ── Fila 4: ALB ─────────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Request Count"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Errores 5XX"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { color = "#d62728" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Target Response Time (s)"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix]
          ]
        }
      },

      # ── Fila 5: ALB Healthy Hosts ────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 12
        height = 6
        properties = {
          title  = "ALB — Healthy / Unhealthy Hosts"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",   "LoadBalancer", local.alb_arn_suffix, "TargetGroup", local.tg_arn_suffix, { label = "Healthy",   color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", local.alb_arn_suffix, "TargetGroup", local.tg_arn_suffix, { label = "Unhealthy", color = "#d62728" }],
          ]
        }
      },
    ]
  })
}
