FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System deps (git for clone, python3.11, curl for health checks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3-pip \
    ca-certificates git curl build-essential \
 && rm -rf /var/lib/apt/lists/*

# pnpm (utilisé par les scripts de build OpenClaw)
RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

# Clone the upstream OpenClaw repository; replace URL if you use a fork
RUN git clone https://github.com/openclaw/openclaw.git .

# Install JS dependencies
RUN if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
    elif [ -f package-lock.json ]; then npm ci --legacy-peer-deps; \
    else npm install --legacy-peer-deps; fi

# Build step is optional; keep here if the project ships a build script
RUN if npm run | grep -q "build"; then npm run build; fi

# Expose default app port (Render/Heroku style: app listens on $PORT)
ENV PORT=3000
EXPOSE 3000

ENV NODE_ENV=production

# Persist agent memory under /var/lib/openclaw (mounted via volume)
VOLUME ["/var/lib/openclaw"]

CMD ["sh", "-c", "PORT=${PORT:-3000} npm run start"]
