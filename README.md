# aws-ai-forge

Plataforma de consulta inteligente sobre documentos desplegada en AWS, construida con infraestructura como código y arquitectura serverless desacoplada.

## Arquitectura

```
Internet (HTTP:80)
        ↓
Application Load Balancer  (subnets públicas)
        ↓
FastAPI — ECS Fargate      (subnets privadas)
        ├── Amazon S3      (lectura de documentos)
        └── AWS Lambda     (invocación desacoplada)
                ↓
        Amazon Bedrock     (Claude 3 Haiku — generación de respuesta)
                ↓
        CloudWatch Logs    (observabilidad)
```

El tráfico interno entre ECS, Lambda, S3 y Bedrock nunca sale a internet — transita exclusivamente por **VPC Endpoints**, eliminando la necesidad de NAT Gateway.

## Stack tecnológico

| Capa | Tecnología |
|------|-----------|
| IaC | Terraform >= 1.5 (estructura modular) |
| Cómputo API | ECS Fargate |
| Cómputo IA | AWS Lambda (Python 3.12) |
| API Framework | FastAPI + Uvicorn |
| Modelo IA | Amazon Bedrock — Claude 3 Haiku |
| Registro de contenedores | Amazon ECR |
| Almacenamiento | Amazon S3 |
| Red | VPC, ALB, VPC Endpoints (sin NAT Gateway) |
| Seguridad | IAM mínimo privilegio, SSE-S3, SGs restrictivos |
| Observabilidad | CloudWatch Logs |
| Contenedor | Docker multi-stage, usuario no-root |

## Estructura del repositorio

```
aws-ai-forge/
├── app/
│   ├── main.py              # FastAPI — endpoints /health /ask /version
│   ├── Dockerfile           # Multi-stage build, usuario no-root
│   └── requirements.txt
├── lambda/
│   └── bedrock_handler.py   # Invoca Bedrock con contexto del documento
└── terraform/
    ├── main.tf              # Orquestador — solo llama módulos
    ├── variables.tf
    ├── outputs.tf
    └── modules/
        ├── vpc/             # VPC, subnets, IGW, route tables, VPC Endpoints
        ├── alb/             # Application Load Balancer, target group, listener
        ├── iam/             # ECS Execution Role, ECS Task Role, Lambda Role
        ├── s3/              # Bucket con SSE, versionado, lifecycle, deny non-TLS
        ├── ecr/             # Repositorio con tags inmutables y scan on push
        ├── lambda/          # Función Lambda + CloudWatch Log Group
        └── ecs/             # Cluster, task definition, service Fargate
```

## Endpoints

| Method | Endpoint | Descripción |
|--------|----------|-------------|
| `GET` | `/health` | Health check — usado por ALB y ECS |
| `GET` | `/version` | Versión y región del servicio |
| `POST` | `/ask` | Consulta inteligente sobre un documento |

### Ejemplo de uso

```bash
# Subir un documento a S3
aws s3 cp mi-documento.txt s3://<bucket-name>/docs/mi-documento.txt

# Consultar sobre el documento
curl -X POST http://<alb-dns>/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "¿Qué dice el documento sobre X?", "document_key": "docs/mi-documento.txt"}'
```

### Respuesta

```json
{
  "answer": "Según el documento...",
  "model_id": "anthropic.claude-3-haiku-20240307-v1:0",
  "document_key": "docs/mi-documento.txt",
  "input_tokens": 173,
  "output_tokens": 108
}
```

El modelo responde **únicamente** con información presente en el documento. Si la respuesta no está en el contexto, lo indica explícitamente.

## Despliegue

### Prerrequisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.5
- Docker

### 1. Infraestructura

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 2. Imagen Docker

```bash
# Login a ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ecr-url>

# Build, tag y push
docker build -t aws-ai-forge-dev-api ./app
docker tag aws-ai-forge-dev-api:latest <ecr-url>:latest
docker push <ecr-url>:latest
```

### 3. Deploy al servicio ECS

```bash
aws ecs update-service \
  --cluster aws-ai-forge-dev-cluster \
  --service aws-ai-forge-dev-api-service \
  --force-new-deployment \
  --region us-east-1
```

### Outputs

```bash
terraform output api_endpoint       # URL pública del servicio
terraform output ecr_repository_url # URL del repositorio ECR
terraform output s3_bucket_name     # Nombre del bucket de documentos
```

## Decisiones de arquitectura

- **Sin NAT Gateway** — VPC Endpoints para S3 (Gateway), ECR, CloudWatch, Bedrock y Lambda. Reduce costo ~$32/mes y mantiene el tráfico dentro de la red de AWS.
- **Lambda como intermediario** — desacopla ECS de Bedrock. Permite escalar o cambiar el modelo sin modificar la API.
- **Documentos transversales** — el sistema acepta cualquier archivo subido a S3. El usuario especifica `document_key` en el request.
- **IAM mínimo privilegio** — cada rol tiene permisos scoped al ARN exacto del recurso que necesita. Sin wildcards abiertos.
- **Tags inmutables en ECR** — garantiza trazabilidad de imágenes desplegadas.
- **Health check doble** — a nivel de contenedor (Python urllib) y a nivel de ALB (target group).

## Seguridad

- S3: acceso público bloqueado en los 4 niveles, SSE-S3 (AES256), bucket policy que deniega requests sin TLS
- ECR: `scan_on_push = true`, tags `IMMUTABLE`, repository policy restringida a la cuenta
- IAM: tres roles separados (execution, task, lambda) con permisos mínimos y scoped por ARN
- ECS: contenedor corre como usuario no-root (uid 1001), sin IP pública, inbound solo desde ALB SG
- FastAPI: Swagger deshabilitado, exception handler global sin stack traces en respuestas

## Upgrades planificados

- **RAG con índice automático** — Lambda indexa documentos al subirse a S3 via `s3:ObjectCreated`. Las consultas buscan semánticamente sin especificar `document_key`. Implementación con Amazon Bedrock Knowledge Bases.
- **CloudWatch Dashboard** — panel con métricas de tokens, latencia y errores via módulo Terraform.

## Costo estimado (sesión de lab)

| Recurso | Costo/hora |
|---------|-----------|
| VPC Interface Endpoints (5 × 2 AZs) | ~$0.10/hr |
| ALB | ~$0.008/hr |
| ECS Fargate (0.25 vCPU / 512 MB) | ~$0.012/hr |
| Lambda + Bedrock (por uso) | ~$0.0002/consulta |

**Ejecutar `terraform destroy` al finalizar el lab.**
