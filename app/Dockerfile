# ---------- Stage 1: build ----------
# Use a full image only to compile/install dependencies (build tools, headers, etc.)
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build deps needed to compile psycopg2-binary wheels etc.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install into an isolated prefix so we can copy just the result into the final image
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Stage 2: runtime ----------
# Minimal, slim runtime image: no compilers, no package manager cache, smaller attack surface
FROM python:3.12-slim AS runtime

# Only the runtime shared library for postgres client, not the full -dev headers
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 appgroup \
    && useradd --uid 10001 --gid appgroup --shell /usr/sbin/nologin --no-create-home appuser

WORKDIR /app

# Bring in only the installed python packages from the builder stage (no build tools)
COPY --from=builder /install /usr/local
COPY app.py .

# Drop privileges: run as a dedicated, unprivileged, non-login user (least privilege)
USER appuser

EXPOSE 5000

# Basic container-level healthcheck (also duplicated by k8s probes)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health').read()" || exit 1

# gunicorn instead of flask dev server: production-grade WSGI server
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
