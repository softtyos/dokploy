#!/bin/bash

# Determine the type of build based on the first script argument
BUILD_TYPE=${1:-production}

if [ "$BUILD_TYPE" == "canary" ]; then
    TAG="canary"
else
    TAG="latest"
fi

IMAGE_NAME=${DOCKER_MONITORING_IMAGE:-softtynet/monitoring}
BUILDER=$(docker buildx create --use)

# Navigate to repo root if run from inside apps/dokploy
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "Building ${IMAGE_NAME}:${TAG} from ${REPO_ROOT}/Dockerfile.monitoring"
docker buildx build --platform linux/amd64,linux/arm64 --pull --rm -t "${IMAGE_NAME}:${TAG}" -f "${REPO_ROOT}/Dockerfile.monitoring" "${REPO_ROOT}"

docker buildx rm $BUILDER
