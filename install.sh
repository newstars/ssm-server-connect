#!/bin/bash

# SSM Server Connect 설치 스크립트
#
# 사용법 (설치):
#   ./install.sh                         # 기본 설치 (/usr/local/bin/ssm-connect)
#   ./install.sh --install-dir /경로     # 설치 경로 지정
#   ./install.sh -h | --help             # 도움말 출력
#
# 설치 후 사용법:
#   ssm-connect                          # 기본 리전(ap-northeast-2) 사용
#   ssm-connect <region>                 # 특정 리전 지정 (예: ssm-connect us-west-2)
#
# curl 사용 예:
#   curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash -s -- --install-dir "$HOME/bin"
#
# 이 스크립트는 SSM Server Connect 도구와 필요한 의존성을 자동으로 설치합니다.

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

# 스크립트 사용법 출력
print_usage() {
    cat <<EOF
SSM Server Connect 설치 스크립트

사용법:
  $(basename "$0")                         기본 설치 (${INSTALL_DIR_DEFAULT}/ssm-connect)
  $(basename "$0") --install-dir /경로     설치 경로 지정
  $(basename "$0") -h | --help             이 도움말 출력

설치 후 사용법:
  ssm-connect                              기본 리전(ap-northeast-2) 사용
  ssm-connect <region>                     특정 리전 지정 (예: ssm-connect us-west-2)

옵션:
  --install-dir DIR   ssm-connect 설치 경로 (기본: ${INSTALL_DIR_DEFAULT})

curl 사용 예:
  curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash -s -- --install-dir "\$HOME/bin"

EOF
}

# yes/no 질문 헬퍼 (비대화형 환경에서도 기본값으로 진행)
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"  # y 또는 n
    local response=""

    if [ -t 0 ]; then
        # 대화형 터미널
        log_info "$prompt (y/n)"
        read -r response
    else
        # 파이프 등 비대화형
        response="$default"
        log_info "비대화형 환경입니다. 기본값 '$default' 로 진행합니다."
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 운영체제 감지
detect_os() {
    if [[ "${OSTYPE:-}" == "darwin"* ]]; then
        echo "macos"
    elif [[ "${OSTYPE:-}" == "linux-gnu"* ]] || [[ "${OSTYPE:-}" == "linux"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# CPU 아키텍처 감지 (AWS CLI 설치용)
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        arm64|aarch64)
            echo "aarch64"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Homebrew 설치 확인 (macOS)
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_warning "Homebrew가 설치되어 있지 않습니다."
        if ask_yes_no "Homebrew를 설치하시겠습니까?" "y"; then
            log_info "Homebrew를 설치하는 중..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
            log_error "Homebrew가 필요합니다. 수동으로 설치해주세요. (https://brew.sh)"
            return 1
        fi
    fi
}

# AWS CLI 설치 확인
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI가 설치되어 있지 않습니다."

        local os
        os=$(detect_os)
        case "$os" in
            "macos")
                if ask_yes_no "Homebrew를 통해 AWS CLI를 설치하시겠습니까?" "y"; then
                    check_homebrew || return 1
                    brew install awscli
                else
                    log_info "수동 설치 방법: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    return 1
                fi
                ;;
            "linux")
                if ask_yes_no "AWS CLI를 설치하시겠습니까?" "y"; then
                    local arch cli_url
                    arch=$(detect_arch)
                    case "$arch" in
                        "x86_64")
                            cli_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
                            ;;
                        "aarch64")
                            cli_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
                            ;;
                        *)
                            log_error "지원되지 않는 CPU 아키텍처입니다: $arch"
                            log_info "수동 설치 방법: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                            return 1
                            ;;
                    esac

                    log_info "AWS CLI를 다운로드하는 중... ($arch)"
                    curl -fsSL "$cli_url" -o "awscliv2.zip"
                    unzip -q awscliv2.zip
                    sudo ./aws/install
                    rm -rf awscliv2.zip aws/
                else
                    log_info "수동 설치 방법: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    return 1
                fi
                ;;
            *)
                log_error "지원되지 않는 운영체제입니다."
                return 1
                ;;
        esac
    else
        log_success "AWS CLI가 이미 설치되어 있습니다."
    fi
}

# Session Manager Plugin 설치 확인
check_session_manager_plugin() {
    if ! command -v session-manager-plugin &> /dev/null; then
        log_warning "Session Manager Plugin이 설치되어 있지 않습니다."

        local os
        os=$(detect_os)
        case "$os" in
            "macos")
                if ask_yes_no "Homebrew를 통해 Session Manager Plugin을 설치하시겠습니까?" "y"; then
                    check_homebrew || return 1
                    brew install --cask session-manager-plugin
                else
                    log_info "수동 설치 방법:"
                    log_info "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                    return 1
                fi
                ;;
            "linux")
                if ask_yes_no "Session Manager Plugin을 설치하시겠습니까?" "y"; then
                    # 패키지 매니저 감지
                    if command -v apt-get &> /dev/null; then
                        log_info "Debian/Ubuntu 계열로 감지되었습니다. .deb 패키지를 설치합니다."
                        curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
                        sudo dpkg -i session-manager-plugin.deb
                        rm -f session-manager-plugin.deb
                    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                        log_info "RHEL/CentOS/Amazon Linux 계열로 감지되었습니다. .rpm 패키지를 설치합니다."
                        curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
                        if command -v yum &> /dev/null; then
                            sudo yum install -y session-manager-plugin.rpm
                        else
                            sudo dnf install -y session-manager-plugin.rpm
                        fi
                        rm -f session-manager-plugin.rpm
                    else
                        log_error "지원되는 패키지 매니저(apt, yum, dnf)를 찾을 수 없습니다."
                        log_info "수동 설치 방법:"
                        log_info "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                        return 1
                    fi
                else
                    log_info "수동 설치 방법:"
                    log_info "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                    return 1
                fi
                ;;
            *)
                log_error "지원되지 않는 운영체제입니다."
                return 1
                ;;
        esac
    else
        log_success "Session Manager Plugin이 이미 설치되어 있습니다."
    fi
}

# FZF 설치 확인
check_fzf() {
    if ! command -v fzf &> /dev/null; then
        log_warning "FZF가 설치되어 있지 않습니다."

        local os
        os=$(detect_os)
        case "$os" in
            "macos")
                if ask_yes_no "Homebrew를 통해 FZF를 설치하시겠습니까?" "y"; then
                    check_homebrew || return 1
                    brew install fzf
                else
                    log_info "수동 설치 방법: https://github.com/junegunn/fzf#installation"
                    return 1
                fi
                ;;
            "linux")
                if ask_yes_no "FZF를 설치하시겠습니까?" "y"; then
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get update
                        sudo apt-get install -y fzf
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y fzf
                    elif command -v dnf &> /dev/null; then
                        sudo dnf install -y fzf
                    else
                        log_info "패키지 매니저를 찾지 못했습니다. git을 통해 설치합니다."
                        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
                        ~/.fzf/install --all
                    fi
                else
                    log_info "수동 설치 방법: https://github.com/junegunn/fzf#installation"
                    return 1
                fi
                ;;
            *)
                log_error "지원되지 않는 운영체제입니다."
                return 1
                ;;
        esac
    else
        log_success "FZF가 이미 설치되어 있습니다."
    fi
}

# jq 설치 확인
check_jq() {
    if ! command -v jq &> /dev/null; then
        log_warning "jq가 설치되어 있지 않습니다."

        local os
        os=$(detect_os)
        case "$os" in
            "macos")
                if ask_yes_no "Homebrew를 통해 jq를 설치하시겠습니까?" "y"; then
                    check_homebrew || return 1
                    brew install jq
                else
                    log_info "수동 설치 방법: https://stedolan.github.io/jq/download/"
                    return 1
                fi
                ;;
            "linux")
                if ask_yes_no "jq를 설치하시겠습니까?" "y"; then
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get update
                        sudo apt-get install -y jq
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y jq
                    elif command -v dnf &> /dev/null; then
                        sudo dnf install -y jq
                    else
                        log_error "패키지 매니저를 찾을 수 없습니다. 수동으로 jq를 설치해주세요."
                        log_info "수동 설치 방법: https://stedolan.github.io/jq/download/"
                        return 1
                    fi
                else
                    log_info "수동 설치 방법: https://stedolan.github.io/jq/download/"
                    return 1
                fi
                ;;
            *)
                log_error "지원되지 않는 운영체제입니다."
                return 1
                ;;
        esac
    else
        log_success "jq가 이미 설치되어 있습니다."
    fi
}

# 메인 스크립트 다운로드 및 설치
install_ssm_connect() {
    local script_name="ssm-connect"
    local script_url="https://raw.githubusercontent.com/newstars/ssm-server-connect/main/ssm-exec-fzf.sh"

    log_info "SSM Server Connect 스크립트를 다운로드하는 중..."
    local temp_file
    temp_file=$(mktemp)

    if curl -fsSL "$script_url" -o "$temp_file"; then
        chmod +x "$temp_file"

        if [[ ! -d "$INSTALL_DIR" ]]; then
            log_info "설치 경로가 존재하지 않습니다. 디렉터리를 생성합니다: $INSTALL_DIR"
            mkdir -p "$INSTALL_DIR"
        fi

        if [[ -w "$INSTALL_DIR" ]]; then
            mv "$temp_file" "$INSTALL_DIR/$script_name"
        else
            log_info "관리자 권한이 필요합니다. sudo로 설치를 진행합니다..."
            sudo mv "$temp_file" "$INSTALL_DIR/$script_name"
        fi

        log_success "SSM Server Connect가 ${INSTALL_DIR}/${script_name} 에 설치되었습니다."

        if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
            log_success "이제 'ssm-connect' 명령어로 실행할 수 있습니다."
        else
            log_warning "$INSTALL_DIR 이 PATH에 없습니다."
            log_info "다음 명령어를 쉘 설정에 추가하세요 (예: ~/.bashrc, ~/.zshrc):"
            echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        fi
    else
        log_error "스크립트 다운로드에 실패했습니다."
        rm -f "$temp_file"
        return 1
    fi
}

# 설치 완료 메시지
show_completion_message() {
    echo
    log_success "설치가 완료되었습니다!"
    echo
    echo "설치 경로:"
    echo "  ${INSTALL_DIR}/ssm-connect"
    echo
    echo "사용법:"
    echo "  ssm-connect                    # 기본 리전(ap-northeast-2) 사용"
    echo "  ssm-connect us-west-2          # 특정 리전 지정"
    echo
    echo "문제가 발생하면 다음을 확인하세요:"
    echo "  - AWS 자격 증명이 설정되어 있는지"
    echo "  - 필요한 IAM 권한이 있는지"
    echo "  - 대상 인스턴스에 SSM Agent가 설치되어 있는지"
    echo
    echo "자세한 정보: https://github.com/newstars/ssm-server-connect"
}

# 메인 실행 함수
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

    echo "SSM Server Connect 설치 스크립트"
    echo "================================="
    echo

    local os
    os=$(detect_os)
    log_info "운영체제: $os"
    log_info "설치 경로: ${INSTALL_DIR}"
    echo

    # 의존성 확인 및 설치
    log_info "의존성을 확인하는 중..."

    check_aws_cli || {
        log_error "AWS CLI 설치에 실패했습니다."
        exit 1
    }

    check_session_manager_plugin || {
        log_error "Session Manager Plugin 설치에 실패했습니다."
        exit 1
    }

    check_fzf || {
        log_error "FZF 설치에 실패했습니다."
        exit 1
    }

    check_jq || {
        log_error "jq 설치에 실패했습니다."
        exit 1
    }

    echo
    log_success "모든 의존성이 설치되었습니다."
    echo

    # 메인 스크립트 설치
    install_ssm_connect || {
        log_error "SSM Server Connect 설치에 실패했습니다."
        exit 1
    }

    # 완료 메시지
    show_completion_message
}

# 스크립트 실행
main "$@"
