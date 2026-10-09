FROM node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1
ARG VERSION=dev
ENV APP_VERSION=$VERSION NODE_ENV=production
WORKDIR /app
COPY --chown=node:node app ./app
USER node
EXPOSE 8080
CMD ["node","app/server.js"]
