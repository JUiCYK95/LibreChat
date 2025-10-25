# v0.8.0

# Base node image
FROM node:20-alpine AS node

# Install jemalloc
RUN apk add --no-cache jemalloc
RUN apk add --no-cache python3 py3-pip uv

# Set environment variable to use jemalloc
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

# Add `uv` for extended MCP support
COPY --from=ghcr.io/astral-sh/uv:0.6.13 /uv /uvx /bin/
RUN uv --version

RUN mkdir -p /app && chown node:node /app
WORKDIR /app

USER node

COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node api/package.json ./api/package.json
COPY --chown=node:node client/package.json ./client/package.json
COPY --chown=node:node packages/data-provider/package.json ./packages/data-provider/package.json
COPY --chown=node:node packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY --chown=node:node packages/api/package.json ./packages/api/package.json

RUN \
    # Allow mounting of these files, which have no default
    touch .env ; \
    # Create directories for the volumes to inherit the correct permissions
    mkdir -p /app/client/public/images /app/api/logs /app/uploads ; \
    npm config set fetch-retry-maxtimeout 600000 ; \
    npm config set fetch-retries 5 ; \
    npm config set fetch-retry-mintimeout 15000 ; \
    npm ci --no-audit --legacy-peer-deps

COPY --chown=node:node . .

RUN \
    # Install rollup's Alpine Linux (musl) native bindings
    # This must be done before building packages that use rollup
    npm install @rollup/rollup-linux-x64-musl --save-optional --no-save --legacy-peer-deps; \
    # Install peer dependencies explicitly (needed because of --legacy-peer-deps)
    npm install --legacy-peer-deps mongoose jsonwebtoken winston winston-daily-rotate-file nanoid lodash klona meilisearch; \
    # Build packages first (data-schemas, data-provider, api, client-package)
    npm run build:packages; \
    # React client build (only build client, packages already built)
    NODE_OPTIONS="--max-old-space-size=2048" npm run build:client; \
    # Verify packages were built correctly
    ls -la packages/data-schemas/dist || echo "ERROR: data-schemas dist not found"; \
    ls -la packages/data-provider/dist || echo "ERROR: data-provider dist not found"; \
    ls -la packages/api/dist || echo "ERROR: api dist not found"; \
    # Note: Skipping npm prune to preserve workspace packages
    npm cache clean --force

# Node API setup
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]

# Optional: for client with nginx routing
# FROM nginx:stable-alpine AS nginx-client
# WORKDIR /usr/share/nginx/html
# COPY --from=node /app/client/dist /usr/share/nginx/html
# COPY client/nginx.conf /etc/nginx/conf.d/default.conf
# ENTRYPOINT ["nginx", "-g", "daemon off;"]
