"""
kb_sync_handler.py
Lambda disparada por S3 (s3:ObjectCreated) cuando se sube un documento.
Inicia un ingestion job en Bedrock Knowledge Base para indexar el nuevo contenido.

Flujo:
  S3 upload → s3:ObjectCreated → esta Lambda → StartIngestionJob → Bedrock KB
                                                                         ↓
                                                  indexa chunks → OpenSearch Serverless

Variables de entorno requeridas:
  KB_ID          — ID de la Bedrock Knowledge Base
  DATA_SOURCE_ID — ID del data source S3 configurado en la KB
"""

import json
import logging
import os
import uuid

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

KB_ID          = os.environ["KB_ID"]
DATA_SOURCE_ID = os.environ["DATA_SOURCE_ID"]

bedrock_agent = boto3.client("bedrock-agent")


def handler(event, context):
    """Entry point de la Lambda — procesa eventos S3."""
    logger.info("kb_sync_handler invocado — event_records=%d", len(event.get("Records", [])))

    if not event.get("Records"):
        logger.warning("Evento S3 sin records — descartando.")
        return {"statusCode": 200, "message": "Sin records para procesar."}

    # Extraer info del objeto S3 subido (para logging)
    record    = event["Records"][0]
    s3_bucket = record.get("s3", {}).get("bucket", {}).get("name", "unknown")
    s3_key    = record.get("s3", {}).get("object", {}).get("key", "unknown")

    logger.info(
        "Documento nuevo detectado — bucket=%s key=%s — iniciando ingestion job",
        s3_bucket,
        s3_key,
    )

    try:
        # client_token garantiza idempotencia (evita duplicar jobs por reintentos de S3)
        client_token = str(uuid.uuid4())

        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KB_ID,
            dataSourceId=DATA_SOURCE_ID,
            clientToken=client_token,
            description=f"Auto-sync: s3://{s3_bucket}/{s3_key}",
        )

        job = response["ingestionJob"]
        job_id = job["ingestionJobId"]
        status = job["status"]

        logger.info(
            "Ingestion job iniciado — job_id=%s status=%s kb=%s",
            job_id,
            status,
            KB_ID,
        )

        return {
            "statusCode": 200,
            "ingestion_job_id": job_id,
            "status": status,
            "document": f"s3://{s3_bucket}/{s3_key}",
        }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error("Error iniciando ingestion job: %s — %s", error_code, str(e))

        if error_code == "ConflictException":
            # Ya hay un job en curso — S3 puede disparar múltiples eventos para el mismo objeto
            logger.warning("Ingestion job ya en curso — descartando duplicado.")
            return {"statusCode": 200, "message": "Ingestion job ya en curso."}

        if error_code == "ResourceNotFoundException":
            return {"statusCode": 404, "error": f"KB o data source no encontrado: {str(e)}"}

        return {"statusCode": 500, "error": f"Error iniciando ingestion job: {error_code}"}

    except Exception as e:  # pylint: disable=broad-except
        logger.error("Error inesperado: %s", str(e))
        return {"statusCode": 500, "error": "Error interno del servidor."}
