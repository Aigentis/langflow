# syntax=docker/dockerfile:1

################################
# BUILDER-BASE
# Used to build deps + create our virtual environment
################################
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Install system dependencies for building Python packages and frontend
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
        build-essential \
        git \
        npm \
        gcc \
        libpq-dev \
    && pip install celery \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install backend base dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=README.md,target=README.md \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=src/backend/base/README.md,target=src/backend/base/README.md \
    --mount=type=bind,source=src/backend/base/uv.lock,target=src/backend/base/uv.lock \
    --mount=type=bind,source=src/backend/base/pyproject.toml,target=src/backend/base/pyproject.toml \
    uv sync --frozen --no-install-project --no-editable --extra postgresql

# Copy application source
COPY ./src /app/src

# Build frontend
COPY src/frontend /tmp/src/frontend
WORKDIR /tmp/src/frontend
RUN --mount=type=cache,target=/root/.npm \
    npm ci \
    && npm run build \
    && mkdir -p /app/src/backend/langflow/frontend \
    && cp -r build/* /app/src/backend/langflow/frontend \
    && rm -rf /tmp/src/frontend

# Install main project dependencies into the virtual environment
WORKDIR /app
COPY ./README.md /app/README.md
COPY ./uv.lock /app/uv.lock
COPY ./pyproject.toml /app/pyproject.toml

RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /app/.venv --python 3.12 \
    && . /app/.venv/bin/activate \
    && uv sync --frozen --no-editable --extra postgresql


################################
# RUNTIME
# Setup user, utilities and copy the virtual environment only
################################
FROM python:3.12.3-slim AS runtime

# Install runtime system dependencies
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
        git \
        libpq5 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy virtual environment and application code from builder
COPY --from=builder --chown=1000:1000 /app/.venv /app/.venv
COPY --from=builder --chown=1000:1000 /app /app

# Set PATH to include venv executables
ENV PATH="/app/.venv/bin:$PATH"

# Create a non-root user and group
RUN groupadd -r appgroup -g 1000 && \
    useradd -r -u 1000 -g appgroup --no-create-home --home-dir /app/data appuser

# Create data directory and set permissions
RUN mkdir -p /app/data && \
    chown 1000:1000 /app/data

# Grant write permission to the Langflow alembic directory for the owner
# This path needs to exist and be writable by appuser for alembic logs/operations
RUN mkdir -p /app/.venv/lib/python3.12/site-packages/langflow/alembic/ && \
    chown -R 1000:1000 /app/.venv/lib/python3.12/site-packages/langflow/alembic/ && \
    chmod -R u+w /app/.venv/lib/python3.12/site-packages/langflow/alembic/

# Switch to the non-root user
USER appuser
WORKDIR /app

# Set Langflow environment variables
ENV LANGFLOW_HOST=0.0.0.0
ENV LANGFLOW_PORT=7860
# WARNING: Hardcoding database credentials in the Dockerfile is not recommended for production due to security risks.
# It's generally better to set this via your deployment platform (e.g., Dokploy environment variables).
ENV LANGFLOW_DATABASE_URL=postgresql+asyncpg://langflow:langflow@13.43.144.88:5432/langflow

# Expose Langflow's port
EXPOSE 7860

# Command to run Langflow
CMD ["langflow", "run"]
