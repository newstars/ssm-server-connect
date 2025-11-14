# SSM Server Connect

AWS Systems Manager Session Manager를 통해 리눅스 서버에 쉽게 접속할 수 있는 CLI 도구입니다.

## 주요 기능

- **직관적인 서버 선택**: FZF를 활용한 대화형 인터페이스로 서버를 쉽게 선택
- **자동 인증 관리**: AWS SSO 로그인 상태 확인 및 자동 로그인
- **실시간 미리보기**: 서버 선택 시 인스턴스 상세 정보를 실시간으로 확인
- **안전한 연결**: AWS Systems Manager Session Manager를 통한 보안 연결
- **다중 리전 지원**: 여러 AWS 리전의 서버 관리
- **오류 처리**: 연결 실패 시 구체적인 해결 방법 제시

## 설치 방법

### 빠른 설치 (권장)

```bash
curl -fsSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash
```

### 수동 설치

1. 스크립트 다운로드:
```bash
curl -O https://raw.githubusercontent.com/newstars/ssm-server-connect/main/ssm-exec-fzf.sh
chmod +x ssm-exec-fzf.sh
```

2. PATH에 추가 (선택사항):
```bash
sudo mv ssm-exec-fzf.sh /usr/local/bin/ssm-connect
```

## 요구사항

### 필수 도구

다음 도구들이 설치되어 있어야 합니다:

- **AWS CLI v2**: AWS 서비스와 통신
- **Session Manager Plugin**: SSM 세션 연결
- **FZF**: 대화형 선택 인터페이스

### macOS 설치 (Homebrew)

```bash
# AWS CLI v2
brew install awscli

# Session Manager Plugin
brew install --cask session-manager-plugin

# FZF
brew install fzf
```

### 기타 운영체제

- [AWS CLI 설치 가이드](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Session Manager Plugin 설치 가이드](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [FZF 설치 가이드](https://github.com/junegunn/fzf#installation)

## 사용법

### 기본 사용법

```bash
./ssm-exec-fzf.sh
```

### 특정 리전 지정

```bash
./ssm-exec-fzf.sh us-west-2
```

### 사용 흐름

1. **AWS 프로파일 선택**: 사용할 AWS 프로파일을 FZF로 선택
2. **자동 인증**: SSO 로그인 상태 확인 및 필요시 자동 로그인
3. **서버 선택**: SSM 관리 대상 인스턴스 목록에서 연결할 서버 선택
4. **연결**: Session Manager를 통한 안전한 셸 세션 시작

## 예제

### 프로덕션 환경 서버 접속

```bash
# 기본 리전(ap-northeast-2)에서 실행
./ssm-exec-fzf.sh

# 1. 프로파일 선택: production
# 2. 서버 선택: WebServer-01 (i-1234567890abcdef0)
# 3. 자동으로 SSM 세션 시작
```

### 다른 리전의 서버 접속

```bash
# 미국 서부 리전의 서버에 접속
./ssm-exec-fzf.sh us-west-2

# 해당 리전의 인스턴스 목록이 표시됨
```

## 호환성

### 지원 운영체제
- macOS (10.15 이상)
- Linux (Ubuntu 18.04+, Amazon Linux 2+, CentOS 7+)

### 지원 AWS 서비스
- EC2 인스턴스 (Linux)
- 온프레미스 서버 (SSM Agent 설치 필요)

### 지원 인증 방식
- AWS SSO
- IAM 사용자 (Access Key)
- IAM 역할 (EC2 인스턴스 프로파일)

## 문제 해결

### 일반적인 문제

**Q: "command not found" 오류가 발생합니다**
A: 필수 도구가 설치되어 있는지 확인하세요. 스크립트 실행 시 자동으로 확인됩니다.

**Q: SSM 연결이 실패합니다**
A: 다음을 확인하세요:
- 인스턴스에 SSM Agent가 설치되어 있는지
- 인스턴스에 적절한 IAM 역할이 연결되어 있는지
- 보안 그룹에서 아웃바운드 HTTPS(443) 트래픽이 허용되는지

**Q: 인스턴스 목록이 비어있습니다**
A: 다음을 확인하세요:
- 선택한 리전에 SSM 관리 대상 인스턴스가 있는지
- AWS 계정에 적절한 권한이 있는지
- 인스턴스가 실행 중이고 SSM Agent가 온라인 상태인지

### 필요한 IAM 권한

사용자 또는 역할에 다음 권한이 필요합니다:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeInstanceInformation",
                "ssm:StartSession",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

## 기여하기

프로젝트에 기여하고 싶으시다면 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참고하세요.

## 지원

- 이슈 리포트: [GitHub Issues](https://github.com/[username]/ssm-server-connect/issues)
- 기능 요청: [GitHub Discussions](https://github.com/[username]/ssm-server-connect/discussions)

---

**참고**: 이 도구는 AWS Systems Manager Session Manager를 사용하므로 추가적인 네트워크 설정이나 SSH 키 관리가 필요하지 않습니다.
No newline at end of file
