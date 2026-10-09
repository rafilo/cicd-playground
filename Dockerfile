FROM node:24-alpine
ARG VERSION=dev
ENV APP_VERSION=$VERSION NODE_ENV=production
WORKDIR /app
COPY --chown=node:node app ./app
USER node
EXPOSE 8080
CMD ["node","app/server.js"]
