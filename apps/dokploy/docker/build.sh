#!/bin/bash

# Determine the type of build based on the first script argument
BUILD_TYPE=${1:-production}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ "$BUILD_TYPE" == "canary" ]; then
    TAG="canary"
else
    VERSION=$(node -p "require('${REPO_ROOT}/apps/dokploy/package.json').version")
    TAG="$VERSION"
fi

IMAGE_NAME=${DOCKER_IMAGE:-softtynet/dokploy}
BUILDER=$(docker buildx create --use)

docker buildx build --platform linux/amd64,linux/arm64 --pull --rm -t "${IMAGE_NAME}:${TAG}" -f "${REPO_ROOT}/Dockerfile" "${REPO_ROOT}"

docker buildx rm $BUILDER
