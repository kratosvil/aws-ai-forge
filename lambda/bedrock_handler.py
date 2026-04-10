"""
bedrock_handler.py
Función Lambda que recibe una pregunta + contexto de documento
e invoca Amazon Bedrock (Claude Haiku) para generar una respuesta.

Payload de entrada esperado:
{
    "question": "¿Qué dice el documento sobre X?",
    "context": "<contenido del documento leído desde S3>"
}

Respuesta:
{
    "answer": "<respuesta generada por Bedrock>",
    "model_id": "<model id usado>",
    "input_tokens": <int>,
    "output_tokens": <int>
}
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "1024"))

bedrock = boto3.client("bedrock-runtime")


def build_prompt(question: str, context: str) -> list[dict]:
    """Construye el mensaje para la API de Bedrock (formato Messages API)."""
    system_prompt = (
        "Eres un asistente experto en análisis de documentos. "
        "Responde ÚNICAMENTE basándote en el contexto proporcionado. "
        "Si la información no está en el contexto, indícalo claramente. "
        "No inventes datos ni hagas suposiciones fuera del contexto."
    )

    user_message = (
        f"Contexto del documento:\n"
        f"---\n{context}\n---\n\n"
        f"Pregunta: {question}"
    )

    return system_prompt, [{"role": "user", "content": user_message}]


def invoke_bedrock(question: str, context: str) -> dict:
    """Invoca Bedrock y retorna la respuesta parseada."""
    system_prompt, messages = build_prompt(question, context)

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": MAX_TOKENS,
        "system": system_prompt,
        "messages": messages,
    })

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=body,
    )

    response_body = json.loads(response["body"].read())

    return {
        "answer": response_body["content"][0]["text"],
        "model_id": BEDROCK_MODEL_ID,
        "input_tokens": response_body["usage"]["input_tokens"],
        "output_tokens": response_body["usage"]["output_tokens"],
    }


def handler(event, context):
    """Entry point de la Lambda."""
    logger.info("Invocación recibida — model_id=%s", BEDROCK_MODEL_ID)

    # Validar payload de entrada
    question = event.get("question", "").strip()
    doc_context = event.get("context", "").strip()

    if not question:
        return {
            "statusCode": 400,
            "error": "El campo 'question' es requerido y no puede estar vacío.",
        }

    if not doc_context:
        return {
            "statusCode": 400,
            "error": "El campo 'context' es requerido y no puede estar vacío.",
        }

    # Truncar contexto si supera el límite seguro (~150K caracteres ≈ ~37K tokens)
    # Deja margen para el system prompt, la pregunta y la respuesta esperada
    max_context_chars = 150_000
    if len(doc_context) > max_context_chars:
        logger.warning(
            "Contexto truncado: %d → %d caracteres", len(doc_context), max_context_chars
        )
        doc_context = doc_context[:max_context_chars]

    try:
        result = invoke_bedrock(question, doc_context)
        logger.info(
            "Respuesta generada — input_tokens=%d output_tokens=%d",
            result["input_tokens"],
            result["output_tokens"],
        )
        return {"statusCode": 200, **result}

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error("Error de Bedrock: %s — %s", error_code, str(e))

        if error_code == "ThrottlingException":
            return {"statusCode": 429, "error": "Límite de rate de Bedrock alcanzado. Reintenta en unos segundos."}
        if error_code == "ValidationException":
            return {"statusCode": 422, "error": f"Payload inválido para Bedrock: {str(e)}"}

        return {"statusCode": 500, "error": f"Error invocando Bedrock: {error_code}"}

    except Exception as e:  # pylint: disable=broad-except
        logger.error("Error inesperado: %s", str(e))
        return {"statusCode": 500, "error": "Error interno del servidor."}
