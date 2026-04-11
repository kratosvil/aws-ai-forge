#!/usr/bin/env python3
"""
create_index.py
Crea el indice vector en la coleccion AOSS requerido por Bedrock Knowledge Bases.

Usa requests + requests-aws4auth — patron oficial recomendado por AWS para AOSS.
Bedrock KB requiere que el indice exista antes de poder crear la Knowledge Base.

Uso: python3 create_index.py <collection_endpoint>
"""
import sys
import json
import time

import boto3
import requests
from requests_aws4auth import AWS4Auth

INDEX_NAME = "bedrock-knowledge-base-default-index"

INDEX_MAPPING = {
    "settings": {
        "index.knn": True,
        "number_of_shards": 2,
        "number_of_replicas": 0,
        "knn.algo_param.ef_search": 512,
    },
    "mappings": {
        "properties": {
            # Campo vector — dimension 1024 para Titan Text Embeddings v2
            "bedrock-knowledge-base-default-vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "name": "hnsw",
                    "engine": "faiss",
                    "parameters": {"ef_construction": 512, "m": 16},
                },
            },
            # Campos de texto requeridos por Bedrock KB
            "AMAZON_BEDROCK_TEXT_CHUNK": {"type": "text"},
            "AMAZON_BEDROCK_METADATA":   {"type": "text"},
        }
    },
}


def create_index(endpoint: str) -> None:
    session     = boto3.Session()
    credentials = session.get_credentials().get_frozen_credentials()
    region      = session.region_name or "us-east-1"

    # AWS4Auth — patron oficial para autenticacion SigV4 en AOSS
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        "aoss",
        session_token=credentials.token,
    )

    url     = f"{endpoint}/{INDEX_NAME}"
    headers = {"Content-Type": "application/json"}

    for attempt in range(6):
        try:
            response = requests.put(
                url,
                auth=awsauth,
                headers=headers,
                data=json.dumps(INDEX_MAPPING),
                timeout=30,
            )

            if response.status_code in (200, 201):
                print(f"Indice creado: {response.text}")
                return

            if response.status_code == 400 and "already_exists" in response.text:
                print("Indice ya existe — nada que hacer.")
                return

            print(f"Intento {attempt + 1}/6 fallido (HTTP {response.status_code}): {response.text}")

        except Exception as exc:  # pylint: disable=broad-except
            print(f"Intento {attempt + 1}/6 fallido: {exc}")

        if attempt < 5:
            print("Esperando 15s antes de reintentar...")
            time.sleep(15)

    print("ERROR: No se pudo crear el indice despues de 6 intentos.")
    sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uso: create_index.py <collection_endpoint>")
        sys.exit(1)
    create_index(sys.argv[1])
