FROM node:20-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

FROM base AS final
COPY --from=deps /app/node_modules ./node_modules
COPY src ./src
COPY package.json ./

ENV NODE_ENV=production
ENV PORT=4000

EXPOSE 4000

USER node

CMD ["node", "src/index.js"]
