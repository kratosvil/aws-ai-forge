locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Security Group del ALB ────────────────────────────────────────────────────
# Solo expone HTTP (80) desde internet. ECS únicamente acepta tráfico del ALB.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Permite trafico HTTP entrante desde internet al ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida hacia ECS en el puerto del contenedor"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }
}

# ── Application Load Balancer ─────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Protección contra borrado accidental
  enable_deletion_protection = false

  # Access logs deshabilitados en lab para evitar costo de S3
  # En producción: habilitar con bucket S3 dedicado
  drop_invalid_header_fields = true

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# ── Target Group ──────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-tg-api"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Requerido para ECS Fargate

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-tg-api"
  }
}

# ── Listener HTTP ─────────────────────────────────────────────────────────────
# Puerto 80 → Target Group de la API
# Nota: en producción usar HTTPS (443) con certificado ACM
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
