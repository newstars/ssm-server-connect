#!/bin/bash

# SSM Server Connect 삭제 스크립트
#
# 사용법:
#   ./uninstall.sh                         # 기본 경로(/usr/local/bin/ssm-connect)에서 삭제
#   ./uninstall.sh --install-dir /경로     # 지정 경로에서 삭제
#   ./uninstall.sh -h | --help             # 도움말 출력
#
# curl 사용 예:
#   curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh | bash
#   curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh | bash -s -- --install-dir "\$HOME/bin"

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설치 경로
INSTALL_DIR_DEFAULT="/usr/local/bin"
INSTALL_DIR="$INSTALL_DIR_DEFAULT"

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_usage() {
    cat <<EOF
SSM Server Connect 삭제 스크립트

사용법:
  $(basename "$0")                         기본 경로(${INSTALL_DIR_DEFAULT}/ssm-connect)에서 삭제
  $(basename "$0") --install-dir /경로     지정 경로에서 삭제
  $(basename "$0") -h | --help             이 도움말 출력

옵션:
  --install-dir DIR   ssm-connect가 설치된 경로 (기본: ${INSTALL_DIR_DEFAULT})

예시:
  ./uninstall.sh
  ./uninstall.sh --install-dir \$HOME/bin

curl 사용 예:
  curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh | bash
  curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh | bash -s -- --install-dir "\$HOME/bin"

EOF
}

# 삭제 실행 함수
uninstall_ssm_connect() {
    local script_name="ssm-connect"
    local target_path="${INSTALL_DIR}/${script_name}"

    log_info "삭제 대상 경로: ${target_path}"

    if [[ ! -e "$target_path" ]]; then
        log_warning "해당 경로에 ssm-connect가 존재하지 않습니다: ${target_path}"
        log_info "다른 경로에 설치했을 수 있습니다. --install-dir 옵션을 사용해 다시 시도해보세요."
        return 0
    fi

    # 인터랙티브 여부에 따라 동작 변경
    if [ -t 0 ]; then
        # 터미널에서 직접 실행할 때는 한 번 물어봄
        echo
        read -r -p "정말로 ${target_path} 를 삭제하시겠습니까? (y/N) " answer
        case "$answer" in
            [Yy]*)
                ;;
            *)
                log_info "삭제를 취소했습니다."
                return 0
                ;;
        esac
    else
        # 파이프(curl | bash) 등 비대화형이면 바로 삭제
        log_info "비대화형 환경으로 감지되었습니다. 확인 없이 삭제를 진행합니다."
    fi

    # 실제 삭제
    if [[ -w "$INSTALL_DIR" ]]; then
        rm -f "$target_path"
    else
        log_info "관리자 권한이 필요합니다. sudo로 삭제를 진행합니다..."
        sudo rm -f "$target_path"
    fi

    log_success "ssm-connect가 삭제되었습니다: ${target_path}"
    echo
    echo "참고:"
    echo "  - fzf, jq, AWS CLI, Session Manager Plugin 등 의존성은 그대로 남아있습니다."
    echo "  - 원하면 패키지 매니저(brew, apt, yum 등)로 별도로 제거할 수 있습니다."
}

main() {
    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            --install-dir)
                shift || true
                INSTALL_DIR="${1:-$INSTALL_DIR_DEFAULT}"
                ;;
            *)
                log_warning "알 수 없는 인자: $1"
                print_usage
                exit 1
                ;;
        esac
        shift || true
    done

    echo "SSM Server Connect 삭제 스크립트"
    echo "================================"
    echo
    log_info "대상 경로: ${INSTALL_DIR}"
    echo

    uninstall_ssm_connect
}

main "$@"