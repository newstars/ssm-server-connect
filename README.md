# ssm-server-connect

AWS SSM Session Manager + fzf 를 이용해서  
EC2 인스턴스 목록을 고르고 바로 SSM 세션으로 접속하는 CLI 도구입니다.

---

## ✨ 기능

- AWS EC2 인스턴스 목록 자동 조회
- `fzf` 기반 인터랙티브 선택 UI
- Session Manager Plugin으로 **SSH 없이 바로 접속**
- 기본 리전: `ap-northeast-2`
- 원하는 리전 지정 가능
- macOS (Intel/M1/M2), Linux 완전 지원

---

## 📦 설치 방법

### 기본 설치

```
curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh | bash
```

설치 경로(기본값):

```
/usr/local/bin/ssm-connect
```

---

### 설치 경로 지정

```
curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/install.sh   | bash -s -- --install-dir "$HOME/bin"
```

> `$HOME/bin`을 PATH에 추가해야 실행됩니다.

---

## 🧼 삭제 (Uninstall)

별도의 uninstall 스크립트를 제공합니다.

```
curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh | bash
```

특정 설치 경로에서 제거하려면:

```
curl -sSL https://raw.githubusercontent.com/newstars/ssm-server-connect/main/uninstall.sh   | bash -s -- --install-dir "$HOME/bin"
```

---

## 🚀 사용 방법

### 기본 실행

```
ssm-connect
```

### 특정 리전 지정

```
ssm-connect us-west-2
```

### 특정 프로파일로 실행

```
AWS_PROFILE=prod ssm-connect
```

---

## 🔧 필요한 의존성

- AWS CLI
- Session Manager Plugin
- fzf
- jq

---

## 🔐 필요한 IAM 권한

### EC2 조회

```
{
  "Effect": "Allow",
  "Action": [
    "ec2:DescribeInstances",
    "ec2:DescribeTags"
  ],
  "Resource": "*"
}
```

### SSM Session Manager 접속

```
{
  "Effect": "Allow",
  "Action": [
    "ssm:StartSession",
    "ssm:TerminateSession",
    "ssm:DescribeSessions",
    "ssm:GetConnectionStatus"
  ],
  "Resource": "*"
}
```

### SSM Document

```
{
  "Effect": "Allow",
  "Action": [
    "ssm:SendCommand"
  ],
  "Resource": "*"
}
```

---

## 🛠 문제 해결

### PATH 문제

```
export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
```

### Session Manager Plugin 문제

macOS:
```
brew install --cask session-manager-plugin
```

Ubuntu:
```
sudo apt-get install session-manager-plugin
```

### AWS SSO 로그인 문제

```
aws sso login --profile <프로파일명>
```

---

## 📄 라이선스

MIT License

---

## 🙋‍♂️ Maintainer

**newstars**  
https://github.com/newstars
