FROM node:22-bookworm-slim

WORKDIR /app

ENV NODE_ENV=production \
    WRANGLER_SEND_METRICS=false \
    WRANGLER_WRITE_LOGS=false \
    SITES_RUNTIME_ROOT=/data/runtime

COPY package.json package-lock.json .npmrc ./
RUN npm ci --include=dev && npm cache clean --force

COPY . .
RUN npm run build

EXPOSE 5173

CMD ["/app/scripts/docker-start.sh"]
