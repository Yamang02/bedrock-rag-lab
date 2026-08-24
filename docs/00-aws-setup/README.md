# 00. AWS CLI & IAM 실습 환경 구성

이 문서는 Bedrock RAG 실습을 시작하기 전에 AWS CLI 인증과 실습용 IAM 사용자를 구성하는 과정을 정리한다.

> 이 실습에서는 IAM과 AWS CLI의 인증/인가 흐름을 직접 확인하기 위해 실습용 IAM User와 Access Key를 사용한다. 실제 운영 환경에서는 장기 Access Key 사용을 피하고 IAM Identity Center, IAM Role, OIDC 등 임시 자격 증명 방식을 우선 고려한다.

## 전체 흐름

```text
개인 Admin IAM 계정
        │
        │ AWS CLI
        ▼
실습용 IAM User 생성
        │
        ├─ 권한 정책 연결
        └─ Access Key 생성
                │
                ▼
        AWS CLI Profile 구성
                │
                ▼
      sts get-caller-identity
                │
                ▼
         Terraform 실습
```

## 1. 현재 AWS CLI 인증 확인

먼저 현재 CLI가 어떤 AWS 주체로 인증되어 있는지 확인한다.

```bash
aws sts get-caller-identity
```

예상 결과에는 `Account`, `Arn`, `UserId`가 표시된다.

## 2. 실습용 IAM User 생성

```bash
aws iam create-user \
  --user-name bedrock-rag-lab
```

생성 여부를 확인한다.

```bash
aws iam get-user \
  --user-name bedrock-rag-lab
```

## 3. 권한 정책 연결

초기 실습에서는 필요한 AWS 리소스를 Terraform으로 생성할 수 있도록 권한을 부여한다.

강의에서는 편의를 위해 넓은 권한으로 시작할 수 있지만, 이후 IAM 정책을 최소 권한으로 줄이는 과정을 별도 학습 포인트로 다룬다.

현재 연결된 정책은 다음 명령으로 확인할 수 있다.

```bash
aws iam list-attached-user-policies \
  --user-name bedrock-rag-lab
```

## 4. CLI용 Access Key 생성

```bash
aws iam create-access-key \
  --user-name bedrock-rag-lab
```

> `AccessKeyId`와 `SecretAccessKey`는 GitHub, README, Terraform 코드, 스크린샷에 절대 포함하지 않는다. 특히 Secret Access Key는 생성 시점에만 확인할 수 있다.

## 5. 별도 AWS CLI Profile 구성

Admin 계정의 기본 profile을 덮어쓰지 않고 실습용 profile을 별도로 만든다.

```bash
aws configure --profile bedrock-rag-lab
```

입력 예시:

```text
AWS Access Key ID: ********
AWS Secret Access Key: ********
Default region name: ap-northeast-2
Default output format: json
```

## 6. 실습용 IAM User 인증 확인

```bash
aws sts get-caller-identity \
  --profile bedrock-rag-lab
```

출력되는 ARN이 실습용 IAM User를 가리키는지 확인한다.

```text
arn:aws:iam::<ACCOUNT_ID>:user/bedrock-rag-lab
```

## 7. 이후 Terraform에서 사용

로컬 실습에서는 다음처럼 profile을 명시할 수 있다.

```bash
export AWS_PROFILE=bedrock-rag-lab
```

이후 Terraform과 AWS CLI 명령은 해당 profile의 자격 증명을 사용한다.

```bash
aws sts get-caller-identity
terraform init
terraform plan
```

Terraform 코드에 Access Key나 Secret Access Key를 직접 작성하지 않는다.

## GitHub Actions에서는 어떻게 할까?

로컬 실습과 CI/CD 인증 방식은 분리한다.

```text
로컬 개발
IAM User + AWS CLI Profile
        ↓
    Terraform

GitHub Actions
        ↓
      OIDC
        ↓
   AWS IAM Role
        ↓
    Terraform
```

GitHub Actions 단계에서는 장기 AWS Access Key를 GitHub Secrets에 저장하는 대신 OIDC와 IAM Role을 사용하는 것을 목표로 한다.

## 보안 체크

- Root 계정으로 CLI 실습을 진행하지 않는다.
- Access Key와 Secret Access Key를 Git에 커밋하지 않는다.
- Access Key가 보이는 터미널 화면을 그대로 캡처하지 않는다.
- `.env`, `*.tfvars`, Terraform state 파일에 비밀값이 들어갈 수 있는지 확인한다.
- 실습 종료 후 불필요한 Access Key와 IAM User를 삭제한다.
- 운영 환경에서는 IAM Identity Center, IAM Role, OIDC 등 임시 자격 증명을 우선 사용한다.

## 다음 단계

AWS CLI 인증이 확인되면 Terraform으로 가장 단순한 AWS 리소스를 생성한다.

```text
AWS CLI 인증 확인
        ↓
Terraform Provider 설정
        ↓
S3 Bucket 생성
        ↓
terraform apply
        ↓
AWS CLI로 생성 확인
        ↓
terraform destroy
        ↓
Bedrock RAG 인프라로 확장
```
