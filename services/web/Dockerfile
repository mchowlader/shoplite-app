# ==============================================================================
# ShopLite web: Multi-Stage Production Dockerfile (Nginx Alpine)
# Target Image Size: < 45 MB (Assessment Limit: < 150 MB)
# Security: Multi-Stage Build, Non-Root (USER nginx), Native Healthcheck
# ==============================================================================

# --- Stage 1: Asset Preparation & Verification ---
FROM alpine:3.20 AS builder

WORKDIR /src

COPY nginx.conf index.html ./

# Validate static assets and set strict read permissions
RUN test -f nginx.conf && test -f index.html && chmod 644 nginx.conf index.html

# --- Stage 2: Minimal Hardened Nginx Runtime ---
FROM nginx:1.27-alpine AS runner

# Configure directory permissions for unprivileged execution
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

# Copy validated assets from builder stage
COPY --from=builder --chown=nginx:nginx /src/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=nginx:nginx /src/index.html /usr/share/nginx/html/index.html

USER nginx

EXPOSE 80

# Native Docker Healthcheck (Requirement 2.a)
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
