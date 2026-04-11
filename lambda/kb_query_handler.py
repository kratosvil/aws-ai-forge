"""
kb_query_handler.py
Lambda que recibe una pregunta y consulta Bedrock Knowledge Base
usando RetrieveAndGenerate — RAG completamente gestionado por AWS.

No requiere document_key: busca en toda la base de conocimiento indexada.

Payload de entrada:
{
    "question": "¿Cómo funciona un Pod en Kubernetes?"
}

Respuesta:
{
    "statusCode": 200,
    "answer": "<respuesta generada>",
    "citations": [
        {"text": "<fragmento recuperado>", "source": "s3://bucket/doc.pdf"}
    ],
    "retrieved_chunks": <int>,
    "model_id": "<model id usado>"
}
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

KB_ID            = os.environ["KB_ID"]
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
NUM_RESULTS      = int(os.environ.get("NUM_RESULTS", "5"))

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")


def build_model_arn(region: str, model_id: str) -> str:
    return f"arn:aws:bedrock:{region}::foundation-model/{model_id}"


def extract_citations(raw_citations: list) -> list[dict]:
    """Extrae fragmentos recuperados y sus fuentes S3 de la respuesta de Bedrock KB."""
    citations = []
    for citation in raw_citations:
        for ref in citation.get("retrievedReferences", []):
            content = ref.get("content", {}).get("text", "")
            location = ref.get("location", {})
            s3_uri = location.get("s3Location", {}).get("uri", "unknown")
            citations.append({"text": content[:500], "source": s3_uri})
    return citations


def handler(event, context):
    """Entry point de la Lambda."""
    logger.info("Invocación kb_query_handler — kb_id=%s", KB_ID)

    question = event.get("question", "").strip()

    if not question:
        return {
            "statusCode": 400,
            "error": "El campo 'question' es requerido y no puede estar vacío.",
        }

    # Obtener region desde el ARN del contexto de Lambda
    region = context.invoked_function_arn.split(":")[3]
    model_arn = build_model_arn(region, BEDROCK_MODEL_ID)

    try:
        response = bedrock_agent_runtime.retrieve_and_generate(
            input={"text": question},
            retrieveAndGenerateConfiguration={
                "type": "KNOWLEDGE_BASE",
                "knowledgeBaseConfiguration": {
                    "knowledgeBaseId": KB_ID,
                    "modelArn": model_arn,
                    "retrievalConfiguration": {
                        "vectorSearchConfiguration": {
                            "numberOfResults": NUM_RESULTS,
                        }
                    },
                    "generationConfiguration": {
                        "promptTemplate": {
                            "textPromptTemplate": (
                                "Eres un asistente experto en análisis de documentos. "
                                "Responde ÚNICAMENTE basándote en los fragmentos de contexto proporcionados. "
                                "Si la información no está en el contexto, indícalo claramente. "
                                "No inventes datos ni hagas suposiciones fuera del contexto.\n\n"
                                "$search_results$\n\n"
                                "Pregunta: $query$"
                            )
                        },
                        "inferenceConfig": {
                            "textInferenceConfig": {
                                "maxTokens": 1024,
                                "temperature": 0.1,
                            }
                        },
                    },
                },
            },
        )

        answer = response["output"]["text"]
        raw_citations = response.get("citations", [])
        citations = extract_citations(raw_citations)

        logger.info(
            "Respuesta generada — chunks_recuperados=%d citas=%d",
            NUM_RESULTS,
            len(citations),
        )

        return {
            "statusCode": 200,
            "answer": answer,
            "citations": citations,
            "retrieved_chunks": len(citations),
            "model_id": BEDROCK_MODEL_ID,
        }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error("Error Bedrock KB: %s — %s", error_code, str(e))

        if error_code == "ThrottlingException":
            return {"statusCode": 429, "error": "Rate limit alcanzado. Reintenta en unos segundos."}
        if error_code == "ValidationException":
            return {"statusCode": 400, "error": f"Payload inválido: {str(e)}"}
        if error_code == "ResourceNotFoundException":
            return {"statusCode": 404, "error": f"Knowledge Base '{KB_ID}' no encontrada."}

        return {"statusCode": 500, "error": f"Error invocando Bedrock KB: {error_code}"}

    except Exception as e:  # pylint: disable=broad-except
        logger.error("Error inesperado: %s", str(e))
        return {"statusCode": 500, "error": "Error interno del servidor."}
