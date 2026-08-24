# IAM: bedrock-rag-lab 실행 주체 권한

`infra/`가 Terraform으로 관리하는 AWS 리소스라면, 여기(`iam/`)는 그 Terraform을 실행하는 사람 — `bedrock-rag-lab` IAM User 자신 — 의 권한이다. Terraform이 자기 자신에게 권한을 줄 수 없으므로 AWS CLI로 별도 관리한다.

특정 단계(20, 30, ...) 전용이 아니라, 단계가 진행될수록 계속 자라나는 공용 아티팩트다. 각 단계 문서(`docs/*/README.md`)는 "이 단계에서 어떤 action이 왜 추가됐는지"만 언급하고, 실제 적용 방법은 이 문서를 참조한다.

## 파일

- `bedrock-rag-lab-provisioning.json` — customer-managed policy 본문. 계정 ID는 `<ACCOUNT_ID>` 플레이스홀더로 남겨두고 커밋한다 (Account ID를 커밋하지 않기 위함).

## 왜 필요한가

`docs/00-aws-setup`에서 `bedrock-rag-lab` User에 `AmazonS3FullAccess`만 부여했다. 이후 단계에서 Terraform으로 IAM Role, S3 Vectors, Bedrock Knowledge Base 등을 만들거나, ingestion job을 실행하거나, Retrieve를 호출하려면 그 User 자신도 해당 action에 대한 권한이 있어야 한다.

AWS 공식 문서(`kb-permissions.html`)는 *Bedrock 서비스가 실행 시점에* 필요한 권한(Service Role 쪽)만 안내하고, *Terraform/CLI로 이 리소스들을 다루는 사람*에게 필요한 IAM 권한은 별도로 정리되어 있지 않다. 이 정책은 실제 명령을 반복 실행하며 `AccessDenied` 에러 메시지에 나온 action을 하나씩 추가해 완성한 것이다. Terraform AWS Provider나 Bedrock/S3 Vectors API가 업데이트되면 필요한 action이 달라질 수 있다 — 다시 `AccessDenied`가 나오면 에러 메시지의 action 이름을 그대로 이 정책에 추가하고 재부여하면 된다.

## 왜 managed policy인가

처음엔 inline policy(`put-user-policy`)로 시작했지만, `30-ingestion-retrieval`에서 ingestion/retrieve 권한을 추가하는 시점에 inline policy 최대 크기(2048바이트)를 초과해 `LimitExceeded` 에러가 났다. Customer-managed policy(최대 6144자)로 전환했다.

## 적용 / 갱신 (PowerShell, Admin profile)

계정 ID가 박힌 파일을 저장소나 로컬에 남기지 않도록 임시 파일로 처리한다.

```powershell
$accountId = aws sts get-caller-identity --profile default --query Account --output text

$policy = (Get-Content iam\bedrock-rag-lab-provisioning.json -Raw) -replace '<ACCOUNT_ID>', $accountId

$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $policy -Encoding ascii

$policyArn = "arn:aws:iam::$accountId:policy/bedrock-rag-lab-provisioning"

# 최초 1회
aws iam create-policy --policy-name bedrock-rag-lab-provisioning --policy-document file://$tempFile --profile default
aws iam attach-user-policy --user-name bedrock-rag-lab --policy-arn $policyArn --profile default

# 이후 정책 내용을 바꿀 때마다 (최초 1회는 생략)
aws iam create-policy-version --policy-arn $policyArn --policy-document file://$tempFile --set-as-default --profile default

Remove-Item $tempFile
```

확인:

```powershell
aws iam list-attached-user-policies --user-name bedrock-rag-lab --profile default
aws iam get-policy-version --policy-arn $policyArn --version-id (aws iam get-policy --policy-arn $policyArn --query "Policy.DefaultVersionId" --output text --profile default) --profile default
```

> `Set-Content -Encoding utf8`은 Windows PowerShell 5.1에서 BOM을 붙여 AWS CLI가 파일을 못 읽는 문제가 있었다. 정책 JSON은 ASCII 범위 문자만 쓰므로 `-Encoding ascii`로 우회했다.

> Managed policy는 새 버전을 만드는 방식으로 갱신하며, 계정당 버전은 최대 5개까지 유지된다. 5개를 넘기기 전에 오래된 버전을 정리한다(`aws iam list-policy-versions` / `delete-policy-version`).

Terraform을 쓰는 단계라면, 정책 갱신 후 다시 프로젝트 profile로 전환해 `terraform apply`를 재시도한다. 이미 생성된 리소스는 state에 남아있어 재생성하지 않고 나머지만 이어서 만든다.

## 변경 이력

| 단계 | 추가된 권한 | 이유 |
| --- | --- | --- |
| `20-bedrock-rag-infra` | IAM Role CRUD/라이프사이클, `iam:PassRole`, S3 Vectors CRUD/태그, Bedrock KB/DataSource CRUD/태그 | Terraform으로 이 리소스들을 생성. 5차례 정도 `AccessDenied` → 정책 추가를 반복했다 (`iam:CreateRole` → `s3vectors:CreateVectorBucket` → `iam:ListRolePolicies` → `s3vectors:ListTagsForResource` → `iam:ListInstanceProfilesForRole`). 이 시점에 inline → managed policy로도 전환했다. |
| `30-ingestion-retrieval` | `bedrock:StartIngestionJob`/`GetIngestionJob`/`ListIngestionJobs`, `bedrock:Retrieve`/`RetrieveAndGenerate`, `bedrock:ListFoundationModels`/`ListInferenceProfiles` | ingestion 실행 및 질의 테스트. `ListInferenceProfiles`는 `ap-northeast-2`에서 Claude 계열 생성 모델이 on-demand invocation을 지원하지 않고 cross-region inference profile을 요구하기 때문에, 실제 사용할 modelArn을 조회하기 위해 추가했다. |
