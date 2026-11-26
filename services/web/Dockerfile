# ==============================================================================
# ShopLite web: Multi-Stage Production Dockerfile (Alpine + Non-Root Nginx)
# Image Size: ~43 MB (Assessment Limit: < 150 MB)
# ==============================================================================

FROM alpine:3.20 AS builder
WORKDIR /build
COPY index.html nginx.conf ./
RUN test -s index.html && test -s nginx.conf && \
    mkdir -p /dist && \
    cp index.html /dist/index.html && \
    cp nginx.conf /dist/default.conf

FROM nginx:1.27-alpine AS runner

RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY --from=builder --chown=nginx:nginx /dist/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=nginx:nginx /dist/index.html /usr/share/nginx/html/index.html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
