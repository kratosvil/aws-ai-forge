# ── Stage 1: dependencias ─────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Copiar solo requirements primero — aprovecha caché de Docker si no cambian
COPY requirements.txt .

RUN pip install --upgrade pip --no-cache-dir \
 && pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: imagen final ─────────────────────────────────────────────────────
FROM python:3.12-slim

# Metadatos
LABEL maintainer="aws-ai-forge" \
      version="0.1.0" \
      description="API de consulta inteligente sobre documentos con Amazon Bedrock"

# Variables de entorno de Python — evita .pyc y buffering
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# Copiar dependencias instaladas desde el stage builder
COPY --from=builder /install /usr/local

# Copiar código fuente
COPY main.py .

# Crear usuario no-root para correr la app — nunca correr como root en contenedores
RUN groupadd --gid 1001 appgroup \
 && useradd --uid 1001 --gid appgroup --no-create-home --shell /bin/false appuser \
 && chown -R appuser:appgroup /app

USER appuser

# Puerto expuesto — documentativo, el mapeo real lo hace ECS
EXPOSE 8080

# Health check a nivel de imagen — complementa el del ECS task definition
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Entrypoint — uvicorn como servidor ASGI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
