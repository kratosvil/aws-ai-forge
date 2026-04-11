# aws-ai-forge — Contexto local de desarrollo

**Version activa:** v2.0.0-dev
**Ultima sesion:** 2026-04-11
**Etapa actual:** Fase 1 completada — Bedrock Knowledge Bases + RAG automatico

---

## Que se hizo en esta sesion (Fase 1 — KB)

Se implemento RAG real con Bedrock Knowledge Bases. El endpoint `/ask` (v1) se conserva.
Se agrego el nuevo endpoint `/search` que no requiere `document_key`.

### Archivos nuevos
| Archivo | Descripcion |
|---------|-------------|
| `lambda/kb_query_handler.py` | Llama `RetrieveAndGenerate` de Bedrock KB |
| `lambda/kb_sync_handler.py` | Dispara ingestion job al detectar ObjectCreated en S3 |
| `terraform/modules/knowledge_base/` | AOSS collection + Bedrock KB + data source + IAM service role |
| `terraform/modules/kb_lambda/` | kb_query + kb_sync Lambdas + IAM roles + S3 trigger |

### Archivos modificados
| Archivo | Cambio |
|---------|--------|
| `app/main.py` | Nuevo endpoint `POST /search` + modelos SearchRequest / SearchResponse |
| `terraform/modules/iam/main.tf` | ECS task puede invocar `kb-query-handler` |
| `terraform/modules/ecs/main.tf` | Nueva env var `KB_LAMBDA_FUNCTION_NAME` |
| `terraform/modules/ecs/variables.tf` | Variable `kb_lambda_function_name` |
| `terraform/main.tf` | Modulos `knowledge_base` y `kb_lambda` registrados |
| `terraform/outputs.tf` | Outputs: KB ID, ARN, AOSS endpoint, `/search` URL |

---

## Arquitectura v2 (estado actual)

```
Internet
    ↓
ALB → ECS Fargate (FastAPI)
        ├── POST /ask        → Lambda bedrock_handler → Bedrock InvokeModel (v1 legacy)
        └── POST /search     → Lambda kb_query_handler → Bedrock RetrieveAndGenerate
                                                               ↑
S3 upload → Lambda kb_sync_handler → StartIngestionJob → Bedrock KB
                                                               ↓
                                              AOSS (vector store) ← Titan Embeddings v2
```

---

## Proximos pasos (pendientes)

- [ ] Fase 2 — CloudWatch Dashboard + Alarms + SNS
- [ ] Fase 3 — WAF en ALB
- [ ] Fase 4 — ECS Auto Scaling + X-Ray

## Para desplegar v2

```bash
cd terraform
terraform init      # solo si es la primera vez post-v2
terraform plan
terraform apply

# Subir un documento para indexar
aws s3 cp mi-doc.pdf s3://<bucket>/

# Probar el endpoint RAG
curl -X POST http://<alb-dns>/search \
  -H "Content-Type: application/json" \
  -d '{"question": "¿Que es un Pod en Kubernetes?"}'
```

## Recordatorio de costos

- AOSS cobra desde `terraform apply` hasta `terraform destroy`
- Estimado: ~$0.96/hora (minimo 4 OCU x $0.24)
- Destruir el stack apenas termines el demo

```bash
terraform destroy   # <-- critico para no acumular costo
```

---

## Decisiones tecnicas v2

- OpenSearch Serverless (AOSS) como vector store — managed HA, sin gestion de nodos
- Titan Text Embeddings v2 (dimension 1024) — modelo de embeddings nativo AWS
- Chunking fijo: 512 tokens / 20% overlap — configurable via variables Terraform
- kb_sync_handler usa `clientToken` UUID para idempotencia en reintentos S3
- `/ask` se conserva como legacy — no rompe clientes existentes
