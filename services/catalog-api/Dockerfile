# ==============================================================================
# ShopLite catalog-api: Multi-Stage Production Dockerfile (Alpine Base)
# Target Image Size: < 65 MB (Assessment Limit: < 150 MB)
# Security: Non-Root Execution (USER 1001), Zero Compilers in Final Image
# ==============================================================================

# --- Stage 1: Build Dependencies ---
FROM python:3.11-alpine AS builder

WORKDIR /build

# Install temporary build headers required to compile C extensions
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libpq-dev

COPY requirements.txt .

# Install dependencies into an isolated prefix
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- Stage 2: Minimal Production Runtime ---
FROM python:3.11-alpine AS runner

WORKDIR /app

# Install only the runtime dynamic library and curl for healthchecks
RUN apk add --no-cache \
    libpq \
    curl

# Create an unprivileged system user and group (UID 1001)
RUN addgroup -g 1001 shoplite && \
    adduser -u 1001 -G shoplite -s /bin/sh -D shoplite

# Copy built python packages from builder stage
COPY --from=builder /install /usr/local

# Copy application source code with non-root ownership
COPY --chown=shoplite:shoplite app/ /app/app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

USER 1001

EXPOSE 8000

# Native Docker Healthcheck (Requirement 2.a)
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://127.0.0.1:8000/healthz || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
