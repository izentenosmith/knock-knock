# Single stage: Node 24 strips the types itself, nothing to build.
FROM node:24-alpine
WORKDIR /app
COPY package.json server.ts ./
USER node
EXPOSE 8080
ARG VERSION=dev
ENV VERSION=$VERSION
CMD ["node", "server.ts"]
