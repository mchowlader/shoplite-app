# ==============================================================================
# ShopLite order-worker: Multi-Stage Production Dockerfile (Alpine Base)
# Target Image Size: < 60 MB (Assessment Limit: < 150 MB)
# Security: Non-Root Execution (USER 1001), Zero Compilers in Final Image
# ==============================================================================

# --- Stage 1: Build Dependencies ---
FROM python:3.11-alpine AS builder

WORKDIR /build

RUN apk add --no-cache \
    gcc \
    musl-dev \
    libpq-dev

COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Stage 2: Minimal Production Runtime ---
FROM python:3.11-alpine AS runner

WORKDIR /app

RUN apk add --no-cache \
    libpq \
    curl

RUN addgroup -g 1001 shoplite && \
    adduser -u 1001 -G shoplite -s /bin/sh -D shoplite

COPY --from=builder /install /usr/local
COPY --chown=shoplite:shoplite worker.py /app/worker.py

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

USER 1001

EXPOSE 9101

# Healthcheck testing worker metrics exporter endpoint
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://127.0.0.1:9101/metrics || exit 1

CMD ["python", "worker.py"]
