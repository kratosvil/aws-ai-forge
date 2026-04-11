locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ════════════════════════════════════════════════════════════════════════════════
# WAF Web ACL
#
# scope = REGIONAL — para ALBs (vs CLOUDFRONT para distribuciones)
# Las AWS Managed Rule Groups son mantenidas por AWS y se actualizan
# automaticamente cuando aparecen nuevas amenazas.
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name_prefix}-web-acl"
  description = "WAF para ${var.project_name} — OWASP Top 10 + Known Bad Inputs"
  scope       = "REGIONAL"

  # Accion por defecto: permitir todo lo que no matchee una regla de bloqueo
  default_action {
    allow {}
  }

  # ── Regla 1: AWS Common Rule Set (OWASP Top 10) ─────────────────────────────
  # Cubre: SQL injection, XSS, path traversal, LFI, RCE, HTTP anomalias
  # Priority 1 — se evalua primero
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # Respetar la accion definida en el rule group (block/count)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── Regla 2: Known Bad Inputs ────────────────────────────────────────────────
  # Cubre: Log4Shell (CVE-2021-44228), exploits JNDI, shellshock,
  #        path traversal avanzado, payloads de exploit conocidos
  # Priority 2 — se evalua despues del Common Rule Set
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Metricas globales del Web ACL (requests totales, bloqueados, permitidos)
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-web-acl"
  }
}

# ════════════════════════════════════════════════════════════════════════════════
# Asociacion WAF → ALB
#
# El Web ACL se adjunta al ARN del ALB.
# A partir de aqui, todo request que llegue al ALB pasa por el WAF primero.
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
