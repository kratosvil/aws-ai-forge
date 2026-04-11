# aws-ai-forge

Intelligent document querying platform deployed on AWS, built with infrastructure as code and a decoupled serverless architecture.

## Architecture

```
Internet (HTTP:80)
        ↓
Application Load Balancer  (public subnets)
        ↓
FastAPI — ECS Fargate      (private subnets)
        ├── Amazon S3      (document storage & retrieval)
        └── AWS Lambda     (decoupled invocation)
                ↓
        Amazon Bedrock     (Claude 3 Haiku — response generation)
                ↓
        CloudWatch Logs    (observability)
```

Internal traffic between ECS, Lambda, S3 and Bedrock never leaves AWS — it flows exclusively through **VPC Endpoints**, eliminating the need for a NAT Gateway.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| IaC | Terraform >= 1.5 (modular structure) |
| API Compute | ECS Fargate |
| AI Compute | AWS Lambda (Python 3.12) |
| API Framework | FastAPI + Uvicorn |
| AI Model | Amazon Bedrock — Claude 3 Haiku |
| Container Registry | Amazon ECR |
| Storage | Amazon S3 |
| Networking | VPC, ALB, VPC Endpoints (no NAT Gateway) |
| Security | Least-privilege IAM, SSE-S3, restrictive Security Groups |
| Observability | CloudWatch Logs |
| Container | Docker multi-stage build, non-root user |

## Repository Structure

```
aws-ai-forge/
├── app/
│   ├── main.py              # FastAPI — /health /ask /version endpoints
│   ├── Dockerfile           # Multi-stage build, non-root user
│   └── requirements.txt
├── lambda/
│   └── bedrock_handler.py   # Invokes Bedrock with document context
└── terraform/
    ├── main.tf              # Orchestrator — calls modules only
    ├── variables.tf
    ├── outputs.tf
    └── modules/
        ├── vpc/             # VPC, subnets, IGW, route tables, VPC Endpoints
        ├── alb/             # Application Load Balancer, target group, listener
        ├── iam/             # ECS Execution Role, ECS Task Role, Lambda Role
        ├── s3/              # Bucket with SSE, versioning, lifecycle, deny non-TLS
        ├── ecr/             # Repository with immutable tags and scan on push
        ├── lambda/          # Lambda function + CloudWatch Log Group
        └── ecs/             # Cluster, task definition, Fargate service
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check — used by ALB and ECS |
| `GET` | `/version` | Service version and region |
| `POST` | `/ask` | Intelligent query over a document |

### Usage Example

```bash
# Upload a document to S3
aws s3 cp my-document.txt s3://<bucket-name>/docs/my-document.txt

# Query the document
curl -X POST http://<alb-dns>/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What does the document say about X?", "document_key": "docs/my-document.txt"}'
```

### Response

```json
{
  "answer": "According to the document...",
  "model_id": "anthropic.claude-3-haiku-20240307-v1:0",
  "document_key": "docs/my-document.txt",
  "input_tokens": 173,
  "output_tokens": 108
}
```

The model answers **only** based on the provided document context. If the answer is not in the document, it states so explicitly — no hallucinations.

## Deployment

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker

### 1. Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ecr-url>

# Build, tag and push
docker build -t aws-ai-forge-dev-api ./app
docker tag aws-ai-forge-dev-api:latest <ecr-url>:latest
docker push <ecr-url>:latest
```

### 3. Deploy to ECS

```bash
aws ecs update-service \
  --cluster aws-ai-forge-dev-cluster \
  --service aws-ai-forge-dev-api-service \
  --force-new-deployment \
  --region us-east-1
```

### Outputs

```bash
terraform output api_endpoint       # Public service URL
terraform output ecr_repository_url # ECR repository URL
terraform output s3_bucket_name     # Documents bucket name
```

## Architecture Decisions

- **No NAT Gateway** — VPC Endpoints for S3 (Gateway), ECR, CloudWatch, Bedrock and Lambda. Saves ~$32/month and keeps all traffic within AWS network.
- **Lambda as intermediary** — decouples ECS from Bedrock. Model can be swapped or scaled without touching the API layer.
- **Document-agnostic design** — the system accepts any file uploaded to S3. The caller specifies `document_key` per request, enabling multi-document support.
- **Least-privilege IAM** — each role has permissions scoped to the exact ARN of the resource it needs. No open wildcards.
- **Immutable ECR tags** — guarantees traceability of deployed images.
- **Dual health checks** — container-level (Python urllib) and ALB-level (target group), ensuring reliable zero-downtime deployments.

## Security Highlights

- **S3**: public access blocked on all 4 levels, SSE-S3 (AES256), bucket policy denying non-TLS requests
- **ECR**: `scan_on_push = true`, `IMMUTABLE` tags, repository policy restricted to account
- **IAM**: three separate roles (execution, task, lambda) with ARN-scoped least-privilege permissions
- **ECS**: non-root container user (uid 1001), no public IP, inbound only from ALB Security Group
- **FastAPI**: Swagger UI disabled, global exception handler with no stack traces in responses

## Planned Upgrades

- **Automatic RAG indexing** — Lambda indexes documents on S3 upload (`s3:ObjectCreated`). Queries work without specifying `document_key`. Implementation with Amazon Bedrock Knowledge Bases.
- **CloudWatch Dashboard** — visual metrics panel: token usage, Lambda latency, ECS errors, ALB health checks — via a new Terraform `dashboard` module.

## Estimated Lab Cost

| Resource | Cost/hour |
|---------|-----------|
| VPC Interface Endpoints (5 × 2 AZs) | ~$0.10/hr |
| ALB | ~$0.008/hr |
| ECS Fargate (0.25 vCPU / 512 MB) | ~$0.012/hr |
| Lambda + Bedrock (per use) | ~$0.0002/query |

> Run `terraform destroy` after finishing the lab to stop all charges.
