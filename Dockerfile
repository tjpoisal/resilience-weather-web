FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache dumb-init curl && \
    addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001
COPY --from=builder /app/node_modules ./node_modules
COPY . .
RUN chown -R nodejs:nodejs /app
USER nodejs
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1
EXPOSE 3000
CMD ["/usr/sbin/dumb-init", "node", "src/server.js"]
