# =============================================================================
# NovaMart Inventory API — Production-Ready Dockerfile
# =============================================================================
# This Dockerfile uses a multi-stage build to keep the final image small and
# secure. Multi-stage builds let us use a full Node environment for installing
# dependencies, then copy only what we need into a minimal runtime image.
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Build — install production dependencies
# ---------------------------------------------------------------------------
# We use node:18-alpine as the base because Alpine Linux is ~5 MB vs ~100 MB
# for Debian-based images. Smaller images = faster pulls, smaller attack surface.
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files first (before source code). Docker caches each layer, so
# if package.json hasn't changed, npm ci won't re-run — saving build time.
COPY package.json package-lock.json ./

# npm ci (Clean Install) is preferred over npm install for reproducible builds:
# - It installs exact versions from package-lock.json
# - It's faster in CI/CD because it skips the dependency resolution step
# --only=production excludes devDependencies (test frameworks, linters, etc.)
RUN npm ci --only=production && \
    npm cache clean --force

# ---------------------------------------------------------------------------
# Stage 2: Runtime — minimal image with only what we need to run
# ---------------------------------------------------------------------------
FROM node:18-alpine AS runtime

# Add metadata labels so we can identify this image in a registry
LABEL maintainer="NovaMart DevOps Team"
LABEL description="NovaMart Inventory API — Phase 3 Re-Architect"

# Create a non-root user. Running containers as root is a security risk —
# if an attacker escapes the app, they'd have root access to the container.
# UID 1000 is conventional for the first non-system user.
RUN addgroup -g 1000 novamart && \
    adduser -u 1000 -G novamart -s /bin/sh -D novamart

WORKDIR /app

# Create the data directory for SQLite fallback (when RDS is not available)
RUN mkdir -p /app/data && chown -R novamart:novamart /app/data

# Copy only production node_modules from the builder stage.
# This means devDependencies, npm cache, and build artifacts are NOT in the
# final image — keeping it small and secure.
COPY --from=builder --chown=novamart:novamart /app/node_modules ./node_modules

# Copy only the files the application needs to run.
# We do NOT copy the entire project — no tests, no docs, no .git directory.
COPY --chown=novamart:novamart package.json ./
COPY --chown=novamart:novamart server.js ./

# Switch to the non-root user before running the application
USER novamart

# Document that the app listens on port 3000.
# EXPOSE doesn't publish the port — it's documentation for anyone running the container.
EXPOSE 3000

# HEALTHCHECK tells Docker (and orchestrators) how to verify the container is healthy.
# If /health returns non-200 for 3 consecutive checks, the container is marked unhealthy.
# --interval: time between checks
# --timeout: max time to wait for a response
# --start-period: grace period for the app to start up
# --retries: how many failures before marking unhealthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Use the array form of CMD (exec form) so the Node process receives signals
# directly (important for graceful shutdown). The string form wraps in /bin/sh,
# which swallows SIGTERM and can cause delayed shutdowns.
CMD ["node", "server.js"]
