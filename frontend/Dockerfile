# Employee Management frontend -- static HTML/CSS/JS served by nginx:alpine.
#
# For local docker-compose dev, nginx.conf.template also reverse-proxies
# /api/* to BACKEND_HOST so local behavior matches the prod GKE Ingress
# routing (/api/* -> backend Service, /* -> frontend Service). In prod,
# BACKEND_HOST can be left at its default; the Ingress bypasses this
# proxy for /api/* traffic.
FROM nginx:alpine

ENV BACKEND_HOST=backend:8080

# Static site
COPY src/ /usr/share/nginx/html/

# nginx:alpine runs envsubst over *.template files in
# /etc/nginx/templates/ at container startup, writing the result to
# /etc/nginx/conf.d/<name>.conf.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80
