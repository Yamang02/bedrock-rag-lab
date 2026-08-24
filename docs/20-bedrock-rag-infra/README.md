# 20. Bedrock RAG Infrastructure

이 문서는 Bedrock Knowledge Base를 만들기 전에 필요한 AWS 인프라(S3 문서 버킷, IAM Service Role, S3 Vectors, Knowledge Base, Data Source)를 Terraform으로 구성하는 과정을 정리한다.

`10-terraform-basic`에서 확인한 IAM User(`bedrock-rag-lab`, S3 권한) 기반 profile을 그대로 사용한다.

## 완료 기준

```text
문서 저장용 S3 Bucket
        ↓
Bedrock Service IAM Role
        ↓
Embedding Model 호출 권한
        ↓
S3 Vectors (Vector Bucket + Index)
        ↓
bedrock-rag-lab User 자체 권한 확장 (IAM Role/S3 Vectors/Bedrock KB 생성 권한)
        ↓
Bedrock Knowledge Base
        ↓
S3 Data Source 연결
```

이 단계에서는 아직 ingestion을 실행하지 않는다. Knowledge Base 생성과 Data Source 연결까지가 목표다. 실제 질의는 `30-ingestion-retrieval`에서 다룬다.

## 사전 확인 사항

작성 전에 Terraform AWS Provider의 리소스 지원 여부와 리전을 확인했다.

- `aws_bedrockagent_knowledge_base`의 `storage_configuration.type = "S3_VECTORS"`가 지원된다 (OpenSearch Serverless 없이 S3 Vectors를 바로 벡터 저장소로 사용 가능).
- `aws_s3vectors_vector_bucket`, `aws_s3vectors_index` 리소스가 존재한다 (provider `>= 6.24.0` 필요, 현재 `infra/.terraform.lock.hcl`은 `6.61.0`으로 충족).
- `aws_bedrockagent_data_source`(S3 타입)가 존재한다.
- Titan Text Embeddings V2, S3 Vectors 모두 `ap-northeast-2`(Seoul)에서 사용 가능하다. 리전을 바꿀 필요는 없다.

## 폴더 구조

```text
bedrock-rag-lab/
├── documents/
│   ├── project-overview.md
│   ├── architecture.md
│   └── api.md
│
├── docs/
│   └── 20-bedrock-rag-infra/
│       ├── README.md
│       └── bedrock-rag-lab-provisioning.json
│
└── infra/
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── s3.tf
    ├── s3vectors.tf
    ├── iam.tf
    ├── bedrock.tf
    └── outputs.tf
```

## 1. 문서 버킷 (s3.tf)

`10-terraform-basic`에서 만들었던 테스트용 버킷 정의를 RAG 문서 버킷으로 확장한다.

```hcl
resource "aws_s3_bucket" "documents" {
  bucket_prefix = "bedrock-rag-lab-docs-"
  ...
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id
  ...
}
```

`aws_s3_object` 리소스로 `documents/*.md` 파일을 자동 업로드한다. `terraform apply` 한 번으로 버킷 생성과 문서 업로드가 함께 끝난다.

## 2. 샘플 문서 (documents/)

Knowledge Base에 넣을 최소한의 문서 3개를 준비했다.

```text
documents/
├── project-overview.md   # 인증 방식(JWT), DB(PostgreSQL) 언급
├── architecture.md       # S3 / S3 Vectors / Knowledge Base 구조 언급
└── api.md                # POST /query, citation 언급
```

30단계에서 "이 프로젝트의 인증 방식은?" 같은 질의로 정확한 답변이 나오는지 확인할 예정이다.

## 3. Bedrock Service IAM Role (iam.tf)

로컬에서 Terraform을 실행하는 `bedrock-rag-lab` IAM User와, Bedrock 서비스가 AWS 리소스에 접근할 때 사용하는 IAM Role은 별개다.

```text
IAM User (bedrock-rag-lab)  → 사람이 Terraform 실행
IAM Role (bedrock-rag-lab-kb-role) → Bedrock 서비스가 S3/S3 Vectors/Embedding Model 접근
```

Trust policy는 `bedrock.amazonaws.com`을 principal로 하되, `aws:SourceAccount` / `aws:SourceArn` 조건으로 이 계정의 knowledge base 요청만 신뢰하도록 제한한다 (AWS 공식 문서 권장, confused deputy 방지).

권한 정책은 다음 4가지를 포함한다.

- `bedrock:ListFoundationModels` / `bedrock:ListCustomModels`
- `bedrock:InvokeModel` (embedding model ARN에 한정)
- `s3:ListBucket` / `s3:GetObject` (문서 버킷에 한정)
- `s3vectors:PutVectors` / `GetVectors` / `DeleteVectors` / `QueryVectors` / `GetIndex` (vector index ARN에 한정)

## 4. Embedding Model

```text
Model ID: amazon.titan-embed-text-v2:0
```

`variables.tf`의 `embedding_model_id`로 관리하고, `bedrock.tf`에서 `arn:aws:bedrock:<region>::foundation-model/<model-id>` 형태의 ARN으로 참조한다.

## 5. S3 Vectors (s3vectors.tf)

```hcl
resource "aws_s3vectors_vector_bucket" "rag" { ... }

resource "aws_s3vectors_index" "rag" {
  data_type       = "float32"
  dimension       = var.vector_dimension       # 1024 (Titan V2 기본)
  distance_metric = var.vector_distance_metric # cosine
}
```

## 6. Bedrock Knowledge Base (bedrock.tf)

```hcl
resource "aws_bedrockagent_knowledge_base" "rag" {
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_model_arn
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.rag.index_arn
    }
  }
}
```

Service Role, Embedding Model, Vector Store 세 가지 의존 관계가 이 리소스 하나에 모인다.

## 7. S3 Data Source 연결 (bedrock.tf)

```hcl
resource "aws_bedrockagent_data_source" "documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.rag.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.documents.arn
    }
  }
}
```

## 8. 실행 주체(bedrock-rag-lab User) 권한 확장

`iam.tf`에서 만드는 `bedrock-rag-lab-kb-role`은 **Bedrock 서비스**가 assume해서 쓰는 Role이다. 이것과 별개로, Terraform을 실행하는 **`bedrock-rag-lab` IAM User 자신**도 이번 단계에서 IAM Role/S3 Vectors/Bedrock Knowledge Base를 생성·조회·삭제할 권한이 필요하다. `00-aws-setup`에서는 `AmazonS3FullAccess`만 부여했으므로, 이 단계에서 처음 `terraform apply`를 돌리면 권한 부족으로 막힌다.

이 권한은 `bedrock-rag-lab` User 스스로에게 줄 수 없으므로 Admin(`default` profile)으로 부여한다. 정책은 [bedrock-rag-lab-provisioning.json](bedrock-rag-lab-provisioning.json)에 있다. 계정 ID는 플레이스홀더(`<ACCOUNT_ID>`)로 남겨두고, 로컬에서 실행할 때만 메모리(변수)에서 실제 값으로 치환한다 (Account ID를 커밋하지 않기 위함).

**정책 구성 (최종)**

| 대상 | 목적 | 대표 action |
| --- | --- | --- |
| `bedrock-rag-lab-kb-role` | 생성/조회/삭제 + 인라인 정책 | `iam:CreateRole`, `PutRolePolicy`, `DeleteRole` 등 |
| 위 Role의 삭제 라이프사이클 | `terraform destroy` 시 사전 점검 | `iam:ListInstanceProfilesForRole`, `ListAttachedRolePolicies` 등 |
| Bedrock에 Role 전달 | KB 생성 시 `role_arn` 지정 | `iam:PassRole` (`iam:PassedToService = bedrock.amazonaws.com` 조건) |
| S3 Vectors (bucket + index) | 생성/조회/삭제 + 태그 | `s3vectors:CreateVectorBucket`, `CreateIndex`, `ListTagsForResource` 등 |
| Bedrock Knowledge Base / Data Source | 생성/조회/삭제 + 태그 | `bedrock:CreateKnowledgeBase`, `CreateDataSource`, `ListDataSources` 등 |

전체 목록은 JSON 파일을 참조한다.

> **왜 이렇게 세세하게 나열되어 있나** — AWS 공식 문서(`kb-permissions.html`)는 *Bedrock 서비스가 실행 시점에* 필요한 권한(Service Role 쪽)만 안내하고, *Terraform으로 이 리소스들을 생성하는 사람*에게 필요한 IAM 권한은 별도로 정리되어 있지 않다. 이 정책은 2026-08-24에 `terraform apply`를 반복 실행하며 `AccessDenied` 에러 메시지에 나온 action을 하나씩 추가해 완성한 것이다. Terraform AWS Provider나 Bedrock/S3 Vectors API가 업데이트되면 필요한 action이 달라질 수 있다 — 다시 `AccessDenied`가 나오면 에러 메시지의 action 이름을 그대로 이 정책에 추가하고 재부여하면 된다.

**적용 (PowerShell, Admin profile)**

계정 ID가 박힌 파일을 저장소나 로컬에 남기지 않도록 임시 파일로 처리한다.

```powershell
$accountId = aws sts get-caller-identity --profile default --query Account --output text

$policy = (Get-Content docs\20-bedrock-rag-infra\bedrock-rag-lab-provisioning.json -Raw) -replace '<ACCOUNT_ID>', $accountId

$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $policy -Encoding ascii

aws iam put-user-policy --user-name bedrock-rag-lab --policy-name bedrock-rag-lab-provisioning --policy-document file://$tempFile --profile default

Remove-Item $tempFile
```

확인:

```powershell
aws iam get-user-policy --user-name bedrock-rag-lab --policy-name bedrock-rag-lab-provisioning --profile default
```

> `Set-Content -Encoding utf8`은 Windows PowerShell 5.1에서 BOM을 붙여 AWS CLI가 파일을 못 읽는 문제가 있었다. 정책 JSON은 ASCII 범위 문자만 쓰므로 `-Encoding ascii`로 우회했다.

다시 프로젝트 profile로 전환 후 `terraform apply`를 재시도한다. 이미 생성된 리소스는 state에 남아있어 재생성하지 않고 나머지만 이어서 만든다. 실제로 이 단계는 `iam:CreateRole` → `s3vectors:CreateVectorBucket` → `iam:ListRolePolicies` → `s3vectors:ListTagsForResource` → `iam:ListInstanceProfilesForRole` 순으로 5번 정도 반복하며 정책을 채웠다.

## 9. Terraform 실행

```bash
cd infra
terraform fmt
terraform validate
terraform plan
terraform apply
```

`plan` 결과에서 생성되는 리소스 개수를 확인한다 (S3 Bucket, Public Access Block, S3 Object × 3, IAM Role, IAM Role Policy, S3 Vectors Bucket, S3 Vectors Index, Knowledge Base, Data Source).

## 10. Outputs

```bash
terraform output
```

```text
documents_bucket_name
vector_bucket_name
bedrock_service_role_arn
knowledge_base_id
knowledge_base_arn
data_source_id
```

## 11. AWS CLI로 확인

```bash
aws s3 ls --profile bedrock-rag-lab
aws iam get-role --role-name bedrock-rag-lab-kb-role --profile bedrock-rag-lab
aws bedrock-agent get-knowledge-base --knowledge-base-id <knowledge_base_id> --profile bedrock-rag-lab
aws bedrock-agent list-data-sources --knowledge-base-id <knowledge_base_id> --profile bedrock-rag-lab
aws s3vectors list-indexes --vector-bucket-name bedrock-rag-lab-vectors --profile bedrock-rag-lab
```

## 보안 체크

- Bedrock Service Role은 `bedrock-rag-lab` IAM User(로컬 실행 주체)와 분리되어 있다.
- Trust policy에 `aws:SourceAccount` / `aws:SourceArn` 조건을 걸어 다른 계정/리소스의 AssumeRole을 막는다.
- IAM 권한은 문서 버킷, embedding model, vector index 각각의 ARN으로 범위를 좁혔다 (와일드카드 없음).
- `terraform.tfstate`에는 리소스 ARN 등이 포함되므로 계속 `.gitignore`로 제외한다.
- `bedrock-rag-lab-provisioning.json`은 계정 ID를 `<ACCOUNT_ID>` 플레이스홀더로 남겨두고, 실행 시에만 로컬에서 실제 값으로 치환한다 (Account ID를 커밋하지 않기 위함).
- `bedrock-rag-lab` User에게 준 권한도 리소스 이름/ARN으로 범위를 좁혔다 (`iam:PassRole`은 `bedrock.amazonaws.com`으로 전달되는 경우로 제한).

## 20-bedrock-rag-infra 완료 (2026-08-24)

`terraform apply`로 S3 문서 버킷/오브젝트, Bedrock Service Role, S3 Vectors, Knowledge Base, Data Source까지 생성 확인했다. `bedrock-rag-lab` User 자체 권한 확장은 5차례 정도의 `AccessDenied` → 정책 추가를 거쳐 완료했다 (8번 참고).

## 다음 단계

Knowledge Base와 Data Source 연결까지 확인되면, 실제 ingestion과 질의는 다음 단계에서 진행한다.

```text
20-bedrock-rag-infra (인프라 구축)
        ↓
30-ingestion-retrieval
   ├─ Ingestion Job 실행
   ├─ Retrieve
   └─ RetrieveAndGenerate
```
