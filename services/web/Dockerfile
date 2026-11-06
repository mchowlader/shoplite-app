# ==============================================================================
# ShopLite web: Production Dockerfile (Nginx Alpine)
# Target Image Size: < 45 MB (Assessment Limit: < 150 MB)
# Pattern: Single-stage — no build toolchain needed for static assets.
#          Multi-stage adds zero benefit here; nginx:alpine IS the final image.
# Security: Non-Root (USER nginx), Native Healthcheck
# ==============================================================================

FROM nginx:1.27-alpine

# Fix directory permissions for non-root execution
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx \
        /var/run/nginx.pid \
        /var/cache/nginx \
        /var/log/nginx \
        /etc/nginx/conf.d

# Copy reverse-proxy config and static assets
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx index.html /usr/share/nginx/html/index.html

USER nginx

EXPOSE 80

# Native Docker Healthcheck (Requirement 2.a)
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
