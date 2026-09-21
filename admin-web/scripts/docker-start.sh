#!/bin/sh
set -eu

mkdir -p /data/runtime

if [ ! -f /data/.trailwatch-database-initialized ]; then
  node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB \
    --local \
    --config ./dist/server/wrangler.json \
    --persist-to /data \
    --file ./drizzle/0000_busy_shriek.sql
  touch /data/.trailwatch-database-initialized
fi

exec node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js dev \
  --config ./dist/server/wrangler.json \
  --local \
  --persist-to /data \
  --ip 0.0.0.0 \
  --port 5173 \
  --inspector-port 0
