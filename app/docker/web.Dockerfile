# syntax=docker/dockerfile:1
# Build context: ./app  (docker build -f app/docker/web.Dockerfile app)

FROM nginx:1.27-alpine

# The official entrypoint renders /etc/nginx/templates/*.template with envsubst at
# start-up, so the /api upstream is chosen at run time through API_UPSTREAM and the
# same image works in any environment.
COPY web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY web/index.html web/app.js web/styles.css /usr/share/nginx/html/

ENV API_UPSTREAM=api:8080
EXPOSE 8080
