"""
main.py
API principal de aws-ai-forge.

Expone tres endpoints:
  GET  /health  — health check para ALB y ECS
  GET  /version — info del servicio
  POST /ask     — recibe question + document_key, lee S3, invoca Lambda → Bedrock
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# ── Configuración ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
logger = logging.getLogger("aws-ai-forge")

S3_BUCKET_NAME      = os.environ["S3_BUCKET_NAME"]
LAMBDA_FUNCTION_NAME = os.environ["LAMBDA_FUNCTION_NAME"]
AWS_REGION          = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
VERSION             = os.environ.get("APP_VERSION", "0.1.0")

s3     = boto3.client("s3",     region_name=AWS_REGION)
lambda_ = boto3.client("lambda", region_name=AWS_REGION)

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="aws-ai-forge",
    description="Consulta inteligente sobre documentos usando Amazon Bedrock",
    version=VERSION,
    docs_url=None,   # Deshabilitar Swagger UI en producción
    redoc_url=None,
)

# ── Modelos de request / response ─────────────────────────────────────────────
class AskRequest(BaseModel):
    question: str = Field(
        ...,
        min_length=3,
        max_length=1000,
        description="Pregunta sobre el contenido del documento",
    )
    document_key: str = Field(
        ...,
        min_length=1,
        max_length=500,
        description="Clave del objeto en S3 (ej: 'docs/kubernetes.pdf')",
    )


class AskResponse(BaseModel):
    answer: str
    model_id: str
    document_key: str
    input_tokens: int
    output_tokens: int


class HealthResponse(BaseModel):
    status: str
    service: str


class VersionResponse(BaseModel):
    service: str
    version: str
    region: str

# ── Helpers ───────────────────────────────────────────────────────────────────
MAX_DOCUMENT_BYTES = 10 * 1024 * 1024  # 10 MB — consistente con el bucket policy

def read_document_from_s3(document_key: str) -> str:
    """Lee un objeto de S3 y retorna su contenido como texto."""
    try:
        response = s3.get_object(
            Bucket=S3_BUCKET_NAME,
            Key=document_key,
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "NoSuchKey":
            raise HTTPException(
                status_code=404,
                detail=f"Documento '{document_key}' no encontrado en S3.",
            )
        if error_code == "AccessDenied":
            raise HTTPException(
                status_code=403,
                detail=f"Sin permisos para acceder a '{document_key}'.",
            )
        logger.error("Error S3 (%s): %s", error_code, str(e))
        raise HTTPException(status_code=500, detail="Error al leer el documento desde S3.")

    content_length = response.get("ContentLength", 0)
    if content_length > MAX_DOCUMENT_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"El documento supera el límite de {MAX_DOCUMENT_BYTES // (1024*1024)} MB.",
        )

    return response["Body"].read().decode("utf-8", errors="replace")


def invoke_bedrock_lambda(question: str, context: str) -> dict:
    """Invoca la Lambda de Bedrock y retorna la respuesta parseada."""
    payload = json.dumps({"question": question, "context": context})

    try:
        response = lambda_.invoke(
            FunctionName=LAMBDA_FUNCTION_NAME,
            InvocationType="RequestResponse",
            Payload=payload.encode("utf-8"),
        )
    except ClientError as e:
        logger.error("Error invocando Lambda: %s", str(e))
        raise HTTPException(status_code=500, detail="Error al invocar el servicio de IA.")

    result = json.loads(response["Payload"].read())

    if result.get("statusCode") != 200:
        status = result.get("statusCode", 500)
        error  = result.get("error", "Error desconocido en Lambda.")
        logger.error("Lambda retornó error %d: %s", status, error)

        if status == 429:
            raise HTTPException(status_code=429, detail=error)
        if status == 400:
            raise HTTPException(status_code=422, detail=error)

        raise HTTPException(status_code=502, detail=error)

    return result


# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.get("/health", response_model=HealthResponse, tags=["ops"])
def health():
    """Health check — usado por ALB y ECS para verificar disponibilidad del servicio."""
    return {"status": "ok", "service": "aws-ai-forge"}


@app.get("/version", response_model=VersionResponse, tags=["ops"])
def version():
    """Retorna la versión y región del servicio desplegado."""
    return {
        "service": "aws-ai-forge",
        "version": VERSION,
        "region": AWS_REGION,
    }


@app.post("/ask", response_model=AskResponse, tags=["ai"])
def ask(request: AskRequest):
    """
    Recibe una pregunta y la clave de un documento en S3.
    Lee el documento, lo envía como contexto a Amazon Bedrock via Lambda
    y retorna la respuesta generada por el modelo.
    """
    logger.info(
        "Request /ask — document_key=%s question_length=%d",
        request.document_key,
        len(request.question),
    )

    # 1. Leer documento desde S3
    context = read_document_from_s3(request.document_key)
    logger.info("Documento leído — %d caracteres", len(context))

    # 2. Invocar Lambda → Bedrock
    result = invoke_bedrock_lambda(request.question, context)

    logger.info(
        "Respuesta generada — input_tokens=%d output_tokens=%d",
        result["input_tokens"],
        result["output_tokens"],
    )

    return AskResponse(
        answer=result["answer"],
        model_id=result["model_id"],
        document_key=request.document_key,
        input_tokens=result["input_tokens"],
        output_tokens=result["output_tokens"],
    )


# ── Handler de errores global ─────────────────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    # No exponer stack traces al cliente — solo loggear internamente
    logger.error("Error no manejado: %s", str(exc), exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Error interno del servidor."},
    )
