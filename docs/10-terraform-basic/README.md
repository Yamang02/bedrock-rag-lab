# 10. Terraform 기본 흐름 (S3 Bucket)

이 문서는 [00-aws-setup](../00-aws-setup/README.md)에서 구성한 `bedrock-rag-lab` 프로젝트 IAM User(S3 권한)를 사용해, Terraform으로 AWS 리소스를 생성/삭제하는 가장 단순한 흐름을 정리한다.

첫 실습은 범위를 최대한 좁게 잡아 S3 Bucket 하나만 만들고 지운다.

## 전체 흐름

```text
Terraform 설치 확인
        ↓
AWS Provider 설정
        ↓
현재 AWS profile 확인
        ↓
S3 Bucket 하나 정의
        ↓
terraform init
        ↓
terraform fmt / validate
        ↓
terraform plan
        ↓
terraform apply
        ↓
AWS CLI로 생성 확인
        ↓
terraform destroy
```

## 폴더 구조

```text
bedrock-rag-lab/
├── docs/
│   ├── 00-aws-setup/
│   └── 10-terraform-basic/
│       └── README.md
│
└── infra/
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── s3.tf
    └── outputs.tf
```

## 1. Terraform 설치 확인

```bash
terraform -version
```

## 2. AWS Provider / Profile 설정

Provider는 [00-aws-setup](../00-aws-setup/README.md)에서 만든 `bedrock-rag-lab` profile을 사용한다.

```hcl
# providers.tf
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

```hcl
# variables.tf
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_profile" {
  type    = string
  default = "bedrock-rag-lab"
}
```

Terraform을 실행하기 전에 현재 CLI가 프로젝트 profile로 인증되어 있는지 확인한다.

```bash
aws sts get-caller-identity --profile bedrock-rag-lab
```

## 3. S3 Bucket 정의

```hcl
# s3.tf
resource "aws_s3_bucket" "documents" {
  bucket_prefix = "bedrock-rag-lab-"

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}
```

버킷 이름을 고정하지 않고 `bucket_prefix`를 쓰는 이유는, S3 버킷 이름이 전역으로 유일해야 하기 때문이다. 나중에 이름을 명시적으로 관리해야 할 때(예: Bedrock Knowledge Base 연동) 고정 이름으로 바꾼다.

## 4. Terraform 실행

```bash
cd infra

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

`terraform apply`의 `yes` 확인 프롬프트에서 plan 내용을 먼저 확인한다.

## 5. AWS CLI로 생성 확인

```bash
aws s3 ls --profile bedrock-rag-lab
```

`outputs.tf`에 정의된 버킷 이름과 일치하는지 확인한다.

```hcl
# outputs.tf
output "documents_bucket_name" {
  value = aws_s3_bucket.documents.bucket
}
```

## 6. 리소스 정리

실습이 끝나면 반드시 정리한다.

```bash
terraform destroy
```

```bash
aws s3 ls --profile bedrock-rag-lab
```

버킷이 더 이상 보이지 않으면 성공이다.

## 보안 체크

- `infra/` 아래에 Access Key, Secret Access Key를 하드코딩하지 않는다. Provider는 profile 참조만 한다.
- `terraform.tfstate`, `.terraform/`은 Git에 커밋하지 않는다 (`.gitignore` 확인).
- 실습 종료 후 `terraform destroy`로 비용이 발생하는 리소스를 남기지 않는다.

## 10-terraform-basic 완료

`terraform init → plan → apply → aws s3 ls 확인 → terraform destroy`까지 확인했다. S3 버킷은 생성 후 삭제되어 현재 남아있는 과금 리소스는 없다.

## 다음 단계

S3 Bucket 생성/삭제까지 확인되면, 이후 단계를 폭을 넓혀가며 진행한다.

```text
10-terraform-basic (S3 Bucket)
        ↓
20-bedrock-rag-infra (S3 Document Bucket + IAM Role + S3 Vectors + Knowledge Base)
        ↓
30-ingestion-retrieval (Ingestion + Retrieve/RetrieveAndGenerate)
```
