# WinOpo web · Next.js en modo standalone
FROM node:22-alpine AS deps
WORKDIR /app
COPY web/package.json web/package-lock.json* ./
RUN npm ci || npm install

FROM node:22-alpine AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
# Durante el build no hay core al que llamar: las rutas que dependen de sesion son dinamicas.
ENV WINOPO_API_URL=http://127.0.0.1:8080
COPY --from=deps /app/node_modules ./node_modules
COPY web/ ./
RUN npm run build

FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -S winopo && adduser -S -G winopo winopo
COPY --from=build --chown=winopo:winopo /app/.next/standalone ./
COPY --from=build --chown=winopo:winopo /app/.next/static ./.next/static
COPY --from=build --chown=winopo:winopo /app/public ./public
USER winopo
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:3000/ >/dev/null || exit 1
CMD ["node", "server.js"]
