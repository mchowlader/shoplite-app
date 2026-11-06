# ==============================================================================
# ShopLite web: Production Dockerfile (Nginx Alpine Base)
# Target Image Size: < 45 MB (Assessment Limit: < 150 MB)
# Security: Non-Root Execution, Minimal Static Runtime
# ==============================================================================

FROM nginx:1.27-alpine

# Configure directory permissions for unprivileged execution
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

RUN chown -R nginx:nginx /usr/share/nginx/html

USER nginx

EXPOSE 80

# Native Docker Healthcheck (Requirement 2.a)
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
