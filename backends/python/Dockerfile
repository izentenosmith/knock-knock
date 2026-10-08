# Single stage: stdlib only, nothing to build.
FROM python:3.13-slim
WORKDIR /app
COPY main.py ./
USER 65534:65534
EXPOSE 8080
ARG VERSION=dev
ENV VERSION=$VERSION
CMD ["python", "main.py"]
