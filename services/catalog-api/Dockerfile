# ==============================================================================
# ShopLite catalog-api: Multi-Stage Production Dockerfile (Alpine Base)
# Target Image Size: < 150 MB | Security: Non-Root (USER 1001)
# ==============================================================================

FROM python:3.11-alpine AS builder
WORKDIR /build

RUN apk add --no-cache gcc musl-dev libpq-dev binutils

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt && \
    find /install -type d -name '__pycache__' -exec rm -rf {} + && \
    find /install -type d -name 'tests' -exec rm -rf {} + && \
    find /install -name '*.so*' -exec strip --strip-unneeded {} + 2>/dev/null || true

FROM python:3.11-alpine AS runner
WORKDIR /app

RUN apk add --no-cache libpq && \
    addgroup -g 1001 shoplite && \
    adduser -u 1001 -G shoplite -s /bin/sh -D shoplite && \
    rm -rf /usr/local/lib/python3.11/ensurepip

COPY --from=builder /install /usr/local
COPY --chown=shoplite:shoplite app/ /app/app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

USER 1001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
