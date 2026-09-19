#!/bin/bash

# Determine the type of build based on the first script argument
BUILD_TYPE=${1:-production}

IMAGE_NAME=${DOCKER_IMAGE:-softtynet/dokploy}
BUILDER=$(docker buildx create --use)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ "$BUILD_TYPE" == "canary" ]; then
    TAG="canary"
    echo "PUSHING CANARY: ${IMAGE_NAME}:${TAG}"
    docker buildx build --platform linux/amd64,linux/arm64 --pull --rm -t "${IMAGE_NAME}:${TAG}" -f "${REPO_ROOT}/Dockerfile" --push "${REPO_ROOT}"
else
    echo "PUSHING PRODUCTION: ${IMAGE_NAME}"
    VERSION=$(node -p "require('${REPO_ROOT}/apps/dokploy/package.json').version")
    docker buildx build --platform linux/amd64,linux/arm64 --pull --rm -t "${IMAGE_NAME}:latest" -t "${IMAGE_NAME}:${VERSION}" -f "${REPO_ROOT}/Dockerfile" --push "${REPO_ROOT}"
fi

docker buildx rm $BUILDER

