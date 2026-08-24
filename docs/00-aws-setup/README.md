# 00. AWS CLI & IAM 실습 환경 구성

이 문서는 Bedrock RAG 실습을 시작하기 전에 AWS CLI 인증과 실습용 IAM 사용자를 구성하는 과정을 정리한다.

> 이 실습에서는 IAM과 AWS CLI의 인증/인가 흐름을 직접 확인하기 위해 로컬은 실습용 IAM User + Access Key를, CI/CD(GitHub Actions)는 OIDC + IAM Role을 사용한다. 실제 운영 환경에서는 장기 Access Key 대신 IAM Identity Center 등 임시 자격 증명 방식을 우선 고려한다.

## 전체 흐름

```text
개인 Admin IAM 사용자
        │
        │ aws login (브라우저 기반 인증)
        ▼
sts get-caller-identity 로 확인
        │
        ▼
실습용 IAM User 생성 (bedrock-rag-lab)
        │
        ▼
로컬 인증 방식 결정
  (Access Key를 바로 만들지 않고 재검토)
        │
        ▼
AWS CLI Profile 구성
        │
        ▼
      Terraform 실습

GitHub Actions
        │
        │ OIDC
        ▼
    IAM Role
        │
        ▼
      Terraform
```

## 1. 현재 AWS CLI 인증 확인 (aws login)

`aws login`은 AWS CLI의 브라우저 기반 로그인 방식이다. 별도로 Access Key를 만들지 않고도 현재 터미널 세션에 Admin IAM 사용자의 자격 증명을 연결할 수 있다.

로그인 후 현재 CLI가 어떤 AWS 주체로 인증되어 있는지 확인한다.

```bash
aws sts get-caller-identity
```

예상 결과에는 `Account`, `Arn`, `UserId`가 표시된다.

```text
arn:aws:iam::<ACCOUNT_ID>:user/admin
```

> `<ACCOUNT_ID>`는 비밀값은 아니지만 public GitHub에 굳이 노출할 정보는 아니다. 강의 자료로 스크린샷을 올릴 때는 Account ID 부분을 가린다.

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

## 3. 로컬 인증 방식 결정: IAM User + Access Key

앞서 Admin 인증에는 `aws login`(브라우저 기반 로그인)을 사용했다. 이 실습에서 굳이 실습용 IAM User에 장기 Access Key를 발급하는 것이 최선인지 검토한 결과, **로컬 실습용은 전통적인 IAM User + Access Key 방식을, CI/CD는 OIDC 방식을 사용**하기로 결정했다.

```text
Admin
  ↓ aws login (임시 자격 증명)
프로젝트 IAM User
  ↓ Access Key (장기 자격 증명)
로컬 Terraform 실습

GitHub Actions
  ↓ OIDC (임시 자격 증명)
IAM Role
  ↓
Terraform
```

로컬 실습 목적상 IAM User + Access Key가 개념을 직접 확인하기 가장 쉬운 방식이라 이번 실습에서는 이 방식을 택한다. 대신 권한은 필요한 만큼만(S3부터 단계적으로) 부여하고, 실습이 끝나면 Access Key를 폐기한다. CI/CD(GitHub Actions)는 처음부터 장기 credential 없이 OIDC + IAM Role로 간다.

## 4. 권한 정책 연결 (S3부터 단계적으로)

한 번에 넓은 권한(Bedrock 포함)을 주지 않고, 첫 Terraform 실습에 필요한 S3 권한만 우선 부여한다. 이후 IAM Role, Bedrock 등이 필요해질 때마다 그 시점에 권한을 추가한다.

```bash
aws iam attach-user-policy --user-name bedrock-rag-lab --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

확인:

```bash
aws iam list-attached-user-policies \
  --user-name bedrock-rag-lab
```

```text
IAM User (bedrock-rag-lab) + IAM Policy (AmazonS3FullAccess) = S3 작업 가능
```

## 5. CLI용 Access Key 생성

```bash
aws iam create-access-key \
  --user-name bedrock-rag-lab
```

> `AccessKeyId`와 `SecretAccessKey`는 GitHub, README, Terraform 코드, 스크린샷에 절대 포함하지 않는다. 특히 Secret Access Key는 생성 시점에만 확인할 수 있다.

## 6. 별도 AWS CLI Profile 구성

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

## 7. 실습용 IAM User 인증 확인

```bash
aws sts get-caller-identity \
  --profile bedrock-rag-lab
```

출력되는 ARN이 실습용 IAM User를 가리키는지 확인한다.

```text
arn:aws:iam::<ACCOUNT_ID>:user/bedrock-rag-lab
```

## 8. 이후 Terraform에서 사용

로컬 실습에서는 다음처럼 profile을 명시할 수 있다.

macOS/Linux (bash):

```bash
export AWS_PROFILE=bedrock-rag-lab
```

Windows CMD:

```cmd
set AWS_PROFILE=bedrock-rag-lab
```

Windows PowerShell:

```powershell
$env:AWS_PROFILE="bedrock-rag-lab"
```

> CMD의 `set`, PowerShell의 `$env:`는 해당 터미널 창에만 적용되고 창을 닫으면 사라진다.

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
- AWS Account ID가 보이는 스크린샷은 강의 자료로 올리기 전에 가린다.
- `.env`, `*.tfvars`, Terraform state 파일에 비밀값이 들어갈 수 있는지 확인한다.
- 실습 종료 후 불필요한 Access Key와 IAM User를 삭제한다.
- 운영 환경에서는 IAM Identity Center, IAM Role, OIDC 등 임시 자격 증명을 우선 사용한다.

## 00-aws-setup 완료

여기까지 진행하면 Admin이 아니라 `bedrock-rag-lab` 프로젝트 IAM User(S3 권한)로 CLI 작업이 전환된 상태다.

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
