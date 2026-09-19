#!/usr/bin/env bash

# ==============================================================================
# Script: build-and-push.sh
# Mục đích: Tự động tăng version, build & push Dokploy và Monitoring lên Docker Hub
# ==============================================================================

set -e

# Màu sắc hiển thị
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
BLUE=$(printf '\033[0;34m')
YELLOW=$(printf '\033[1;33m')
CYAN=$(printf '\033[0;36m')
MAGENTA=$(printf '\033[0;35m')
BOLD=$(printf '\033[1m')
NC=$(printf '\033[0m') # No Color

# Thư mục gốc dự án
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Cấu hình mặc định
NAMESPACE="${DOCKER_NAMESPACE:-softtynet}"
BUILD_DOKPLOY=true
BUILD_MONITORING=true
DO_PUSH=true
MULTI_ARCH=false
CUSTOM_VERSION=""
BUMP_TYPE="patch" # "patch", "minor", "major", "none"

# Hàm hiển thị hướng dẫn sử dụng
show_help() {
    cat << EOF
${BOLD}SỬ DỤNG:${NC}
  ./scripts/build-and-push.sh [VERSION] [OPTIONS]
  (hoặc chạy qua pnpm: pnpm run docker:release -- [OPTIONS])

${BOLD}TÍNH NĂNG TỰ TĂNG VERSION:${NC}
  - Mặc định khi chạy ${CYAN}./scripts/build-and-push.sh${NC}, script sẽ ${GREEN}TỰ ĐỘNG TĂNG PATCH VERSION${NC}
    (Ví dụ: v0.30.6 ➔ v0.30.7) và cập nhật thẳng vào file apps/dokploy/package.json.
    Bạn không cần phải nhớ hay gõ tay số version nữa!

${BOLD}THAM SỐ:${NC}
  VERSION                 Chỉ định số version cụ thể nếu muốn (ví dụ: v0.31.0).

${BOLD}TÙY CHỌN BUMP VERSION:${NC}
  --no-bump               Giữ nguyên version hiện tại trong package.json, không tự tăng.
  --bump-minor            Tăng version minor (Ví dụ: v0.30.6 ➔ v0.31.0).
  --bump-major            Tăng version major (Ví dụ: v0.30.6 ➔ v1.0.0).

${BOLD}TÙY CHỌN BUILD & PUSH:${NC}
  --dokploy-only          Chỉ build & push Dokploy
  --monitoring-only       Chỉ build & push Monitoring
  --no-push               Chỉ build trên máy tính, không push lên Docker Hub
  --multi-arch            Build đa kiến trúc (linux/amd64,linux/arm64) qua buildx
  --namespace <tên>       Đổi namespace Docker Hub (mặc định: softtynet)
  -h, --help              Hiển thị hướng dẫn này

${BOLD}VÍ DỤ:${NC}
  ./scripts/build-and-push.sh                    # Tự động tăng version (+1 patch) và build & push cả 2 image
  ./scripts/build-and-push.sh --no-bump          # Dùng lại version hiện tại, không tăng số
  ./scripts/build-and-push.sh --bump-minor       # Nhảy version minor (v0.30.x ➔ v0.31.0)
  ./scripts/build-and-push.sh v0.30.9           # Chỉ định chính xác version v0.30.9
  ./scripts/build-and-push.sh --no-push          # Chỉ build local để test, không push
EOF
    exit 0
}

# Phân tích tham số dòng lệnh
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --no-bump)
            BUMP_TYPE="none"
            shift
            ;;
        --bump-patch)
            BUMP_TYPE="patch"
            shift
            ;;
        --bump-minor)
            BUMP_TYPE="minor"
            shift
            ;;
        --bump-major)
            BUMP_TYPE="major"
            shift
            ;;
        --dokploy-only)
            BUILD_DOKPLOY=true
            BUILD_MONITORING=false
            shift
            ;;
        --monitoring-only)
            BUILD_DOKPLOY=false
            BUILD_MONITORING=true
            shift
            ;;
        --no-push)
            DO_PUSH=false
            shift
            ;;
        --multi-arch)
            MULTI_ARCH=true
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            if [[ -z "$CUSTOM_VERSION" && ! "$1" =~ ^-- ]]; then
                CUSTOM_VERSION="$1"
                BUMP_TYPE="custom"
            else
                echo -e "${RED}Tham số không hợp lệ: $1${NC}"
                show_help
            fi
            shift
            ;;
    esac
done

# Kiểm tra Docker daemon đang chạy
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}[LỖI] Docker daemon chưa khởi động. Vui lòng bật Docker Desktop trước!${NC}"
    exit 1
fi

# Đường dẫn file package.json của Dokploy
PACKAGE_JSON="${REPO_ROOT}/apps/dokploy/package.json"

# Lấy version hiện tại
CURRENT_VERSION=$(node -p "require('$PACKAGE_JSON').version" 2>/dev/null || echo "v0.30.6")

# Tính toán VERSION mới
if [[ "$BUMP_TYPE" == "custom" ]]; then
    VERSION="$CUSTOM_VERSION"
    [[ ! "$VERSION" =~ ^v ]] && VERSION="v$VERSION"
elif [[ "$BUMP_TYPE" == "none" ]]; then
    VERSION="$CURRENT_VERSION"
else
    # Tự động tính version mới bằng Node.js SemVer logic
    VERSION=$(node -e "
        const current = '$CURRENT_VERSION'.replace(/^v/, '');
        let parts = current.split('.').map(p => parseInt(p, 10));
        let major = isNaN(parts[0]) ? 0 : parts[0];
        let minor = isNaN(parts[1]) ? 0 : parts[1];
        let patch = isNaN(parts[2]) ? 0 : parts[2];

        if ('$BUMP_TYPE' === 'major') {
            major++; minor = 0; patch = 0;
        } else if ('$BUMP_TYPE' === 'minor') {
            minor++; patch = 0;
        } else {
            patch++;
        }
        console.log('v' + major + '.' + minor + '.' + patch);
    ")
fi

# Cập nhật version mới vào apps/dokploy/package.json nếu có thay đổi
if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
    node -e "
        const fs = require('fs');
        const file = '$PACKAGE_JSON';
        const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
        pkg.version = '$VERSION';
        fs.writeFileSync(file, JSON.stringify(pkg, null, '\t') + '\n');
    "
    VERSION_STATUS="${YELLOW}${CURRENT_VERSION}${NC} ➔ ${GREEN}${BOLD}${VERSION}${NC} ${MAGENTA}(Đã tự động lưu vào apps/dokploy/package.json)${NC}"
else
    VERSION_STATUS="${GREEN}${BOLD}${VERSION}${NC} (Giữ nguyên)"
fi

echo -e "\n${BOLD}${CYAN}====================================================${NC}"
echo -e "${BOLD}${CYAN}   🚀 DOKPLOY AUTOMATED BUILD & PUSH PIPELINE       ${NC}"
echo -e "${BOLD}${CYAN}====================================================${NC}"
echo -e "${BOLD}Namespace Docker Hub:${NC} ${GREEN}${NAMESPACE}${NC}"
echo -e "${BOLD}Version:             ${NC} ${VERSION_STATUS}"
echo -e "${BOLD}Build Dokploy:       ${NC} $([ "$BUILD_DOKPLOY" = true ] && echo -e "${GREEN}CÓ${NC}" || echo -e "${YELLOW}KHÔNG${NC}")"
echo -e "${BOLD}Build Monitoring:    ${NC} $([ "$BUILD_MONITORING" = true ] && echo -e "${GREEN}CÓ${NC}" || echo -e "${YELLOW}KHÔNG${NC}")"
echo -e "${BOLD}Push lên Docker Hub: ${NC} $([ "$DO_PUSH" = true ] && echo -e "${GREEN}CÓ${NC}" || echo -e "${YELLOW}KHÔNG (chỉ build local)${NC}")"
echo -e "${BOLD}Kiến trúc (Arch):    ${NC} $([ "$MULTI_ARCH" = true ] && echo -e "${BLUE}Multi-arch (amd64,arm64)${NC}" || echo -e "${BLUE}linux/amd64 (Host Build - Nhanh & Ổn định)${NC}")"
echo -e "${CYAN}----------------------------------------------------${NC}\n"

# ------------------------------------------------------------------------------
# 1. BUILD & PUSH MONITORING (Nhanh: ~20-30s)
# ------------------------------------------------------------------------------
if [ "$BUILD_MONITORING" = true ]; then
    echo -e "${BLUE}[1/2] 🔨 Đang build Monitoring image (${NAMESPACE}/monitoring)...${NC}"
    
    MONITORING_IMG="${NAMESPACE}/monitoring"
    
    if [ "$MULTI_ARCH" = true ]; then
        BUILDER=$(docker buildx create --use)
        PUSH_FLAG=""
        [ "$DO_PUSH" = true ] && PUSH_FLAG="--push"
        
        docker buildx build --platform linux/amd64,linux/arm64 \
            -t "${MONITORING_IMG}:latest" \
            -t "${MONITORING_IMG}:${VERSION}" \
            -f "${REPO_ROOT}/Dockerfile.monitoring" \
            ${PUSH_FLAG} "${REPO_ROOT}"
            
        docker buildx rm "$BUILDER" > /dev/null 2>&1 || true
    else
        docker build --platform linux/amd64 \
            -t "${MONITORING_IMG}:latest" \
            -t "${MONITORING_IMG}:${VERSION}" \
            -f "${REPO_ROOT}/Dockerfile.monitoring" \
            "${REPO_ROOT}"
            
        if [ "$DO_PUSH" = true ]; then
            echo -e "${BLUE}      📤 Đang push ${MONITORING_IMG}:latest...${NC}"
            docker push "${MONITORING_IMG}:latest"
            echo -e "${BLUE}      📤 Đang push ${MONITORING_IMG}:${VERSION}...${NC}"
            docker push "${MONITORING_IMG}:${VERSION}"
        fi
    fi
    echo -e "${GREEN}      ✅ Hoàn tất Monitoring!${NC}\n"
fi

# ------------------------------------------------------------------------------
# 2. BUILD & PUSH DOKPLOY APP
# ------------------------------------------------------------------------------
if [ "$BUILD_DOKPLOY" = true ]; then
    echo -e "${BLUE}[2/2] 🔨 Đang build Dokploy image (${NAMESPACE}/dokploy)...${NC}"
    
    DOKPLOY_IMG="${NAMESPACE}/dokploy"
    
    if [ "$MULTI_ARCH" = true ]; then
        BUILDER=$(docker buildx create --use)
        PUSH_FLAG=""
        [ "$DO_PUSH" = true ] && PUSH_FLAG="--push"
        
        docker buildx build --platform linux/amd64,linux/arm64 \
            -t "${DOKPLOY_IMG}:latest" \
            -t "${DOKPLOY_IMG}:${VERSION}" \
            -f "${REPO_ROOT}/Dockerfile" \
            ${PUSH_FLAG} "${REPO_ROOT}"
            
        docker buildx rm "$BUILDER" > /dev/null 2>&1 || true
    else
        docker build --platform linux/amd64 \
            -t "${DOKPLOY_IMG}:latest" \
            -t "${DOKPLOY_IMG}:${VERSION}" \
            -f "${REPO_ROOT}/Dockerfile" \
            "${REPO_ROOT}"
            
        if [ "$DO_PUSH" = true ]; then
            echo -e "${BLUE}      📤 Đang push ${DOKPLOY_IMG}:latest...${NC}"
            docker push "${DOKPLOY_IMG}:latest"
            echo -e "${BLUE}      📤 Đang push ${DOKPLOY_IMG}:${VERSION}...${NC}"
            docker push "${DOKPLOY_IMG}:${VERSION}"
        fi
    fi
    echo -e "${GREEN}      ✅ Hoàn tất Dokploy!${NC}\n"
fi

# ------------------------------------------------------------------------------
# TỔNG KẾT KẾT QUẢ
# ------------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}   🎉 TẤT CẢ CÔNG VIỆC ĐÃ HOÀN TẤT THÀNH CÔNG!     ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"

if [ "$DO_PUSH" = true ]; then
    echo -e "Các image đã sẵn sàng trên Docker Hub của bạn:"
    [ "$BUILD_DOKPLOY" = true ] && echo -e "  - ${CYAN}${NAMESPACE}/dokploy:latest${NC} và ${CYAN}${NAMESPACE}/dokploy:${VERSION}${NC}"
    [ "$BUILD_MONITORING" = true ] && echo -e "  - ${CYAN}${NAMESPACE}/monitoring:latest${NC} và ${CYAN}${NAMESPACE}/monitoring:${VERSION}${NC}"
    echo -e "\n${BOLD}Lệnh cập nhật nhanh trên VPS:${NC}"
    if [ "$BUILD_DOKPLOY" = true ]; then
        echo -e "  ${YELLOW}docker service update --image ${NAMESPACE}/dokploy:latest dokploy${NC}"
    fi
else
    echo -e "Các image đã được build và lưu trong local Docker daemon của bạn."
    echo -e "Kiểm tra bằng: ${CYAN}docker images | grep ${NAMESPACE}${NC}"
fi
echo -e "${GREEN}====================================================${NC}\n"
