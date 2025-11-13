#!/bin/bash

# SSM Server Connect 설치 스크립트
# 이 스크립트는 SSM Server Connect 도구와 필요한 의존성을 자동으로 설치합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 운영체제 감지
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Homebrew 설치 확인 (macOS)
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_warning "Homebrew가 설치되어 있지 않습니다."
        log_info "Homebrew를 설치하시겠습니까? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log_info "Homebrew를 설치하는 중..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
            log_error "Homebrew가 필요합니다. 수동으로 설치해주세요."
            return 1
        fi
    fi
}

# AWS CLI 설치 확인
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI가 설치되어 있지 않습니다."
        
        local os=$(detect_os)
        case $os in
            "macos")
                log_info "Homebrew를 통해 AWS CLI를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    check_homebrew || return 1
                    brew install awscli
                else
                    log_info "수동 설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    return 1
                fi
                ;;
            "linux")
                log_info "AWS CLI를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                    unzip awscliv2.zip
                    sudo ./aws/install
                    rm -rf awscliv2.zip aws/
                else
                    log_info "수동 설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
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
        
        local os=$(detect_os)
        case $os in
            "macos")
                log_info "Homebrew를 통해 Session Manager Plugin을 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    check_homebrew || return 1
                    brew install --cask session-manager-plugin
                else
                    log_info "수동 설치: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                    return 1
                fi
                ;;
            "linux")
                log_info "Session Manager Plugin을 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
                    sudo dpkg -i session-manager-plugin.deb
                    rm session-manager-plugin.deb
                else
                    log_info "수동 설치: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
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
        
        local os=$(detect_os)
        case $os in
            "macos")
                log_info "Homebrew를 통해 FZF를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    check_homebrew || return 1
                    brew install fzf
                else
                    log_info "수동 설치: https://github.com/junegunn/fzf#installation"
                    return 1
                fi
                ;;
            "linux")
                log_info "FZF를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    # 패키지 매니저 감지 및 설치
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get update && sudo apt-get install -y fzf
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y fzf
                    elif command -v dnf &> /dev/null; then
                        sudo dnf install -y fzf
                    else
                        # Git을 통한 설치
                        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
                        ~/.fzf/install --all
                    fi
                else
                    log_info "수동 설치: https://github.com/junegunn/fzf#installation"
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
        
        local os=$(detect_os)
        case $os in
            "macos")
                log_info "Homebrew를 통해 jq를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    check_homebrew || return 1
                    brew install jq
                else
                    log_info "수동 설치: https://stedolan.github.io/jq/download/"
                    return 1
                fi
                ;;
            "linux")
                log_info "jq를 설치하시겠습니까? (y/n)"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    # 패키지 매니저 감지 및 설치
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get update && sudo apt-get install -y jq
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y jq
                    elif command -v dnf &> /dev/null; then
                        sudo dnf install -y jq
                    else
                        log_error "패키지 매니저를 찾을 수 없습니다. 수동으로 jq를 설치해주세요."
                        return 1
                    fi
                else
                    log_info "수동 설치: https://stedolan.github.io/jq/download/"
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
    local install_dir="/usr/local/bin"
    local script_name="ssm-connect"
    local script_url="https://raw.githubusercontent.com/[username]/ssm-server-connect/main/ssm-exec-fzf.sh"
    
    log_info "SSM Server Connect 스크립트를 다운로드하는 중..."
    
    # 임시 파일로 다운로드
    local temp_file=$(mktemp)
    if curl -fsSL "$script_url" -o "$temp_file"; then
        # 실행 권한 설정
        chmod +x "$temp_file"
        
        # /usr/local/bin에 설치 (sudo 권한 필요할 수 있음)
        if [[ -w "$install_dir" ]]; then
            mv "$temp_file" "$install_dir/$script_name"
        else
            log_info "관리자 권한이 필요합니다..."
            sudo mv "$temp_file" "$install_dir/$script_name"
        fi
        
        log_success "SSM Server Connect가 $install_dir/$script_name에 설치되었습니다."
        
        # PATH 확인
        if [[ ":$PATH:" == *":$install_dir:"* ]]; then
            log_success "이제 'ssm-connect' 명령어로 실행할 수 있습니다."
        else
            log_warning "$install_dir이 PATH에 없습니다."
            log_info "다음 명령어를 실행하여 PATH에 추가하세요:"
            echo "echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.bashrc"
            echo "source ~/.bashrc"
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
    echo "사용법:"
    echo "  ssm-connect                    # 기본 리전(ap-northeast-2) 사용"
    echo "  ssm-connect us-west-2          # 특정 리전 지정"
    echo
    echo "문제가 발생하면 다음을 확인하세요:"
    echo "  - AWS 자격 증명이 설정되어 있는지"
    echo "  - 필요한 IAM 권한이 있는지"
    echo "  - 대상 인스턴스에 SSM Agent가 설치되어 있는지"
    echo
    echo "자세한 정보: https://github.com/[username]/ssm-server-connect"
}

# 메인 실행 함수
main() {
    echo "SSM Server Connect 설치 스크립트"
    echo "================================="
    echo
    
    log_info "운영체제: $(detect_os)"
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