# syntax=docker/dockerfile:1
# Keep this syntax directive! It's used to enable Docker BuildKit

################################
# BUILDER-BASE
# Used to build deps + create our virtual environment
################################

# 1. use python:3.12.3-slim as the base image until https://github.com/pydantic/pydantic-core/issues/1292 gets resolved
# 2. do not add --platform=$BUILDPLATFORM because the pydantic binaries must be resolved for the final architecture
# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

# Create accessible folders and set the working directory in the container




# Install the project into `/app`
WORKDIR /app

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
    # deps for building python deps
    build-essential \
    git \
    # npm
    npm \
    # gcc
    gcc \
    # for postgresql client build
    libpq-dev \
    && pip install celery \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=README.md,target=README.md \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=src/backend/base/README.md,target=src/backend/base/README.md \
    --mount=type=bind,source=src/backend/base/uv.lock,target=src/backend/base/uv.lock \
    --mount=type=bind,source=src/backend/base/pyproject.toml,target=src/backend/base/pyproject.toml \
    uv sync --frozen --no-install-project --no-editable --extra postgresql

COPY ./src /app/src

COPY src/frontend /tmp/src/frontend
WORKDIR /tmp/src/frontend
RUN --mount=type=cache,target=/root/.npm \
    npm ci \
    && npm run build \
    && cp -r build /app/src/backend/langflow/frontend \
    && rm -rf /tmp/src/frontend

WORKDIR /app
 COPY ./README.md /app/README.md
 COPY ./uv.lock /app/uv.lock
 COPY ./pyproject.toml /app/pyproject.toml

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-editable --extra postgresql




################################
# RUNTIME
# Setup user, utilities and copy the virtual environment only
################################
FROM python:3.12.3-slim AS runtime

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y git nginx \
    # for postgresql runtime client
    libpq5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder --chown=1000:1000 /app/.venv /app/.venv
COPY --from=builder /app /app
# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

LABEL org.opencontainers.image.title=langflow
LABEL org.opencontainers.image.authors=['Langflow']
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.url=https://github.com/langflow-ai/langflow
LABEL org.opencontainers.image.source=https://github.com/langflow-ai/langflow



# Copy the Nginx configuration file (as root)
COPY /docker/nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p /var/lib/nginx /var/log/nginx /run/nginx && \
    chown -R 1000:1000 /var/lib/nginx /var/log/nginx /run/nginx



# Create additional group and user (as root)
# Create a dedicated group and user for the application
RUN groupadd -r appgroup -g 1000 && \
    useradd -r -u 1000 -g appgroup --no-create-home --home-dir /app/data appuser

# Copy start script and set permissions for the new user/group
COPY /docker/start.sh /app/start.sh
RUN chown 1000:1000 /app/start.sh 
RUN chmod +x /app/start.sh

# Create data directory and set permissions for appuser
RUN mkdir -p /app/data && \
    chown 1000:1000 /app/data

# Grant write permission to the Langflow alembic directory for the owner
RUN mkdir -p /app/.venv/lib/python3.12/site-packages/langflow/alembic/ && chown -R 1000:1000 /app/.venv/lib/python3.12/site-packages/langflow/alembic/

# Now switch to the non-root user 'appuser'
USER appuser
WORKDIR /app

ENV LANGFLOW_HOST=0.0.0.0
ENV LANGFLOW_PORT=7860


# Expose the Nginx port
EXPOSE 80


# CMD ["langflow", "run"]
CMD ["sh", "-c", "cd /app &&./start.sh"]
# CMD ["/app/start.sh"]
