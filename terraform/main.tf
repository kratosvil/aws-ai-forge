terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── VPC ──────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ── IAM ──────────────────────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  s3_bucket_arn  = module.s3.bucket_arn
  bedrock_model_id = var.bedrock_model_id
}

# ── S3 ───────────────────────────────────────────────────────────────────────
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

# ── ECR ──────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

# ── Lambda ───────────────────────────────────────────────────────────────────
module "lambda" {
  source = "./modules/lambda"

  project_name       = var.project_name
  environment        = var.environment
  lambda_role_arn    = module.iam.lambda_role_arn
  bedrock_model_id   = var.bedrock_model_id
  log_retention_days = var.log_retention_days
}

# ── ALB ──────────────────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

# ── ECS ──────────────────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  ecr_repository_url     = module.ecr.repository_url
  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  lambda_function_name   = module.lambda.function_name
  s3_bucket_name         = module.s3.bucket_name
  log_retention_days     = var.log_retention_days
  target_group_arn       = module.alb.target_group_arn
  alb_sg_id              = module.alb.alb_sg_id
}
