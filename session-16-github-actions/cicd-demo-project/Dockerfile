# syntax=docker/dockerfile:1

# Session 16 calculator - container image used by the CI and CD pipelines.
FROM python:3.13-slim

# Link the GHCR package to the repository (shows the repo on the package page).
LABEL org.opencontainers.image.source="https://github.com/devops-student/devops-heros" \
      org.opencontainers.image.description="Session 16 CI/CD demo - command line calculator"

# No .pyc files, and unbuffered stdout so piped output appears immediately.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Run as an unprivileged user instead of root.
RUN useradd --create-home --uid 10001 appuser

# Only the application code goes into the image (tests/build files are excluded).
COPY app/ ./app/

USER appuser

# Interactive calculator: run with `docker run -it --rm <image>`
CMD ["python", "app/calculator.py"]
