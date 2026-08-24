# 30. Ingestion & Retrieval

`20-bedrock-rag-infra`에서 만든 Knowledge Base/Data Source에 실제로 문서를 넣고(ingestion), 질의가 정상 동작하는지(Retrieve, RetrieveAndGenerate) 확인한다.

## 완료 기준

```text
샘플 문서 준비 (완료 - 20단계에서 자동 업로드됨)
        ↓
Knowledge Base ingestion job 실행
        ↓
ingestion 완료 상태 확인
        ↓
Retrieve로 관련 chunk 확인
        ↓
RetrieveAndGenerate로 실제 답변 생성 확인
```

바로 Lambda/API Gateway로 가지 않고, CLI에서 RAG 파이프라인이 정상 동작하는지 먼저 검증한다. 애플리케이션 계층은 이후 단계(`40-api`)에서 다룬다.

이 단계는 세 국면으로 나뉜다 — **Terraform**(생성 모델을 쓸 수 있도록 인프라 코드 변경) → **권한 부여**(그 인프라를 다루는 실행 주체의 IAM 권한 확장) → **검증**(ingestion부터 답변 생성까지 실제로 동작하는지 확인).

---

## Phase 1. Terraform — 생성 모델 지원 추가

### 1-1. 생성 모델(Generation Model) 선택

RetrieveAndGenerate는 검색된 문서를 근거로 실제 답변을 생성할 LLM이 하나 더 필요하다 (Knowledge Base의 embedding model과는 별개). `aws bedrock list-foundation-models`로 `ap-northeast-2`에서 **cross-region inference profile 없이 on-demand로 바로 호출 가능한** 텍스트 생성 모델을 직접 조회했다.

```powershell
aws bedrock list-foundation-models --region ap-northeast-2 `
  --query "modelSummaries[?contains(inferenceTypesSupported, 'ON_DEMAND')].[modelId,providerName,outputModalities[0]]" `
  --output table --profile bedrock-rag-lab
```

결과: `ap-northeast-2`에서 on-demand 텍스트 생성이 가능한 건 **Anthropic Claude 3 Haiku**와 **Claude 3.5 Sonnet**뿐이다. Titan Text, Nova, Llama, Mistral, Cohere 등은 이 리전에서 전부 cross-region inference profile이 필요하다 (AWS 문서 페이지 요약은 실행할 때마다 결과가 달라 신뢰할 수 없었고, 위 CLI 조회가 실제 근거다).

둘 중 가장 저렴하고 빠른 **Claude 3 Haiku**(`anthropic.claude-3-haiku-20240307-v1:0`)를 선택했다. inference profile 없이 foundation model ARN을 바로 쓸 수 있어 복잡도도 가장 낮다.

```text
Model ID: anthropic.claude-3-haiku-20240307-v1:0
ARN: arn:aws:bedrock:ap-northeast-2::foundation-model/anthropic.claude-3-haiku-20240307-v1:0
```

`infra/variables.tf`의 `generation_model_id`로 관리한다.

### 1-2. Service Role에 생성 모델 InvokeModel 권한 추가

RetrieveAndGenerate 시 Bedrock이 내부적으로 생성 모델을 호출하는 것도 `bedrock-rag-lab-kb-role`(Bedrock Service Role, `infra/iam.tf`)의 권한으로 이뤄진다. 기존에는 embedding model ARN만 허용했는데, 여기에 생성 모델 ARN을 추가했다.

- `infra/bedrock.tf` — `local.generation_model_arn` 추가
- `infra/iam.tf` — `BedrockInvokeModels` statement의 `resources`에 `local.generation_model_arn` 추가 (기존 `BedrockInvokeEmbeddingModel`을 `BedrockInvokeModels`로 통합)

### 1-3. Apply

```powershell
cd infra
terraform fmt
terraform validate
terraform plan
terraform apply
```

`aws_iam_role_policy.bedrock_kb`가 `Modifying...` → `Modifications complete`로 나오면 Service Role에 반영된 것이다 (리소스 추가/삭제 없이 policy 내용만 바뀐다).

---

## Phase 2. 권한 부여 — bedrock-rag-lab User

Terraform 인프라와 별개로, **CLI로 ingestion/retrieve/generate를 직접 호출하는 `bedrock-rag-lab` User 자신**에게도 권한이 필요하다.

필요해진 action:

- `bedrock:StartIngestionJob` / `GetIngestionJob` / `ListIngestionJobs`
- `bedrock:Retrieve` / `RetrieveAndGenerate`
- `bedrock:InvokeModel` (생성 모델 ARN에 한정)

`iam/bedrock-rag-lab-provisioning.json`에 `BedrockIngestionAndRetrieval`, `BedrockInvokeGenerationModel` statement로 추가했다. 적용은 managed policy의 새 버전을 만드는 방식이다 (inline policy는 20단계에서 이미 크기 제한으로 폐기했다) — 정확한 명령은 [iam/README.md](../../iam/README.md) 참고.

```powershell
# iam/README.md의 "적용 / 갱신" 절차를 그대로 따른다 (create-policy-version --set-as-default)
```

---

## Phase 3. 검증 — Ingestion → Retrieve → RetrieveAndGenerate

### 3-0. 샘플 문서는 이미 S3에 있다

`20-bedrock-rag-infra`의 `infra/s3.tf`에 있는 `aws_s3_object.documents`가 `terraform apply` 시점에 `documents/*.md`를 이미 버킷에 올려뒀다. 별도로 `aws s3 cp`를 다시 할 필요는 없다.

```powershell
cd infra
$bucket = terraform output -raw documents_bucket_name
aws s3 ls s3://$bucket --profile bedrock-rag-lab
```

### 3-1. Ingestion Job 실행

```powershell
cd infra
$kbId = terraform output -raw knowledge_base_id
$dsId = terraform output -raw data_source_id

$jobId = aws bedrock-agent start-ingestion-job `
  --knowledge-base-id $kbId --data-source-id $dsId `
  --query "ingestionJob.ingestionJobId" --output text --profile bedrock-rag-lab

Write-Output "Ingestion Job ID: $jobId"
```

### 3-2. Ingestion 완료 상태 확인

```powershell
aws bedrock-agent get-ingestion-job `
  --knowledge-base-id $kbId --data-source-id $dsId --ingestion-job-id $jobId `
  --profile bedrock-rag-lab
```

`status`가 `STARTING` → `IN_PROGRESS` → `COMPLETE`로 바뀌는지 확인한다. `statistics`에서 `numberOfDocumentsScanned: 3`, `numberOfNewDocumentsIndexed: 3` 정도가 나오면 정상이다.

### 3-3. Retrieve 테스트

```powershell
aws bedrock-agent-runtime retrieve `
  --knowledge-base-id $kbId `
  --retrieval-query text="이 프로젝트의 인증 방식은?" `
  --profile bedrock-rag-lab
```

`retrievalResults`에 `project-overview.md`의 JWT 관련 chunk가 나오면 검색 파이프라인(embedding → S3 Vectors 저장 → 유사도 검색)이 정상이다. 결과 예시는 [retrieve-result.json](retrieve-result.json) 참고.

> 참고: Windows에서 결과를 파일로 리다이렉트할 때 한글이 깨지면(콘솔 코드페이지 문제), `PYTHONUTF8=1` / `PYTHONIOENCODING=utf-8` 환경변수를 설정하고 다시 실행한다. 환경마다 다를 수 있는 문제라 여기서는 참고만 남긴다.

### 3-4. RetrieveAndGenerate 테스트

`--retrieve-and-generate-configuration`은 중첩된 JSON 구조라, `iam/`에서 이미 겪었던 것과 같은 문제(PowerShell이 네이티브 실행 파일에 큰따옴표 포함 인자를 넘길 때 깨지는 문제)가 반복될 가능성이 높다. 처음부터 임시 파일 + `file://`로 넘긴다.

```powershell
$modelArn = "arn:aws:bedrock:ap-northeast-2::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"

$config = @{
  type = "KNOWLEDGE_BASE"
  knowledgeBaseConfiguration = @{
    knowledgeBaseId = $kbId
    modelArn        = $modelArn
  }
} | ConvertTo-Json -Depth 5

$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $config -Encoding ascii

aws bedrock-agent-runtime retrieve-and-generate `
  --input text="이 프로젝트의 인증 방식은?" `
  --retrieve-and-generate-configuration file://$tempFile `
  --profile bedrock-rag-lab

Remove-Item $tempFile
```

`output.text`에 "JWT" 언급이 포함된 답변이 나오고, `citations`에 근거 문서가 함께 나오면 RAG 파이프라인 전체(ingestion → retrieve → generate)가 검증된 것이다. 결과 예시는 [retrieve-and-generate-result.json](retrieve-and-generate-result.json) 참고 — `output.text`가 "이 프로젝트는 JWT 기반 인증을 사용한다."로 정확히 나왔고, `citations`도 `project-overview.md`를 정확히 가리켰다.

---

## 보안 체크

- 생성 모델 호출 권한(`bedrock:InvokeModel`)은 `bedrock-rag-lab` User와 Service Role 양쪽 모두 Claude 3 Haiku의 특정 ARN으로 범위를 좁혔다 (와일드카드 없음).
- ingestion/retrieve 권한은 이 프로젝트의 Knowledge Base ARN(`knowledge-base/*`)으로 범위를 좁혔다.
- `retrieve-result.json`, `retrieve-and-generate-result.json`에는 계정 ID/Access Key 등 민감정보가 없는 것을 확인했다 (버킷 이름, chunk ID, 샘플 문서 내용뿐).

## 30-ingestion-retrieval 완료 (2026-08-24)

Ingestion job(`COMPLETE`, 문서 3개 인덱싱) → Retrieve(관련 chunk 정상 검색) → RetrieveAndGenerate(정확한 답변 + citation)까지 CLI로 RAG 파이프라인 전체를 검증했다.

## 다음 단계

CLI로 RAG 파이프라인이 검증되면, 애플리케이션 계층(Lambda + API Gateway)으로 넘어간다.

```text
30-ingestion-retrieval (CLI 검증)
        ↓
40-api
   ├─ Lambda (Retrieve/RetrieveAndGenerate 래핑)
   └─ API Gateway
```
