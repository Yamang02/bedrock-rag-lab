# 40. API Layer

CLI(`aws bedrock-agent-runtime retrieve-and-generate`)에서만 되던 RAG 질의를 HTTP API로 노출한다.

```text
Client
  ↓
API Gateway (HTTP API)
  ↓
Lambda (boto3)
  ↓
Bedrock Agent Runtime — RetrieveAndGenerate
  ↓
Response
```

## 완료 기준

```text
Lambda 함수 + 실행 Role 생성
        ↓
Lambda에 bedrock:RetrieveAndGenerate / InvokeModel 권한 부여
        ↓
API Gateway HTTP API + POST /query 라우트 연결
        ↓
curl로 실제 질의 테스트
```

## 폴더 구조

```text
bedrock-rag-lab/
├── lambda/
│   └── query/
│       └── handler.py
│
├── iam/
│   ├── README.md
│   └── bedrock-rag-lab-provisioning.json
│
└── infra/
    ├── lambda.tf
    ├── api_gateway.tf
    └── ...
```

## 1. Lambda 코드 (boto3 직접 호출)

30단계에서 CLI로 이미 검증한 `retrieve_and_generate` 호출을 그대로 boto3로 옮긴다. 프레임워크 없이 표준 라이브러리 + boto3만 쓴다.

```python
# lambda/query/handler.py
import json, os, boto3

client = boto3.client("bedrock-agent-runtime")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ["MODEL_ARN"]

def handler(event, context):
    body = json.loads(event.get("body") or "{}")
    question = body.get("question")
    if not question:
        return _response(400, {"error": "question is required"})

    result = client.retrieve_and_generate(
        input={"text": question},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                "modelArn": MODEL_ARN,
            },
        },
    )
    return _response(200, {"answer": result["output"]["text"]})

def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload, ensure_ascii=False),
    }
```

`ensure_ascii=False`를 빼먹으면 응답의 한글이 `\uXXXX` 이스케이프로 나온다 (30단계에서 겪은 인코딩 문제와 같은 종류라 미리 처리해뒀다).

Lambda 런타임(Python 3.13)에는 boto3가 기본 포함되어 있어 별도 패키징이 필요 없다.

## 2. Lambda 실행 Role + 함수 (`infra/lambda.tf`)

- **Trust policy**: `lambda.amazonaws.com`만 assume 가능.
- **권한**: `AWSLambdaBasicExecutionRole`(CloudWatch Logs, AWS 관리형) + `bedrock:RetrieveAndGenerate`/`bedrock:Retrieve`(이 Knowledge Base ARN 한정) + `bedrock:InvokeModel`(생성 모델 ARN 한정). `RetrieveAndGenerate`가 내부적으로 `Retrieve`도 요구한다는 건 처음엔 몰랐다 — 첫 curl 테스트가 `RetrieveAndGenerate`를 호출하는 Lambda 안에서 "not authorized to perform: bedrock:Retrieve"로 실패해서 CloudWatch Logs로 확인한 뒤 추가했다.
- **패키징**: `data "archive_file"`로 `handler.py`를 zip으로 묶고 `source_code_hash`로 변경을 감지한다.
- **환경변수**: `KNOWLEDGE_BASE_ID`, `MODEL_ARN`을 Terraform 리소스 참조로 주입 (하드코딩 없음).

## 3. API Gateway (`infra/api_gateway.tf`)

HTTP API(REST API 대비 더 단순하고 저렴)로 구성한다.

```text
aws_apigatewayv2_api (HTTP)
  → aws_apigatewayv2_integration (AWS_PROXY, payload_format_version = "2.0")
  → aws_apigatewayv2_route ("POST /query")
  → aws_apigatewayv2_stage ("$default", auto_deploy = true)

aws_lambda_permission으로 API Gateway가 이 Lambda를 호출할 수 있도록 허용
```

`payload_format_version = "2.0"`을 명시했다 (기본값은 `1.0`인데, 2.0이 event/response 구조가 더 단순해서 Lambda 코드가 짧아진다).

## 4. 실행 주체(bedrock-rag-lab User) 권한 확장

Lambda/API Gateway를 만드는 것도 `bedrock-rag-lab` User 자신의 권한이 필요하다. 이번엔 접근을 조금 바꿨다 — 이 프로젝트는 짧게 쓰고 버릴 실습이고 CI/CD(50단계)도 하지 않기로 해서, Role마다 개별 statement를 추가하는 대신 **`role/bedrock-rag-lab-*` 명명 규칙 기준 와일드카드**로 단순화했다 (`ProjectRoleManage`).

추가된 권한 요약:

| 대상 | 목적 |
| --- | --- |
| IAM Role 관리 범위 확장 | `bedrock-rag-lab-kb-role` 하나만 → `bedrock-rag-lab-*` 전체 (Lambda Role 포함) |
| `iam:PassRole` to `lambda.amazonaws.com` | Lambda 생성 시 실행 Role을 넘겨주기 위해 |
| `lambda:*` 관리 action | 함수 ARN(`function:bedrock-rag-lab-*`)에 한정 |
| `apigateway:*` | HTTP API 리소스 경로(`/apis*`)에 한정하되, action은 넓게 허용 |

`apigateway:*`는 다른 statement들보다 의도적으로 넓다 — API Gateway v2의 세분화된 하위 리소스 ARN 패턴(라우트/통합/스테이지마다 다름)을 하나씩 맞추기보다 편의 우선으로 갔고, 나중에 좁히는 걸 학습 포인트로 남겨둔다 (`00-aws-setup`에서 이미 정한 원칙과 같다).

적용 방법은 [iam/README.md](../../iam/README.md) 참고 (managed policy version 갱신).

## 5. Terraform 적용

```powershell
cd infra
terraform fmt
terraform validate
terraform plan
terraform apply
```

`plan`에서 9개 리소스(IAM Role, Role Policy, Role Policy Attachment, Lambda Function, API Gateway API/Integration/Route/Stage, Lambda Permission)가 추가되는지 확인한다.

## 6. curl로 테스트

```powershell
cd infra
$endpoint = terraform output -raw api_endpoint

curl.exe -X POST $endpoint `
  -H "Content-Type: application/json" `
  -d '{"question": "이 프로젝트의 인증 방식은?"}'
```

예상 응답:

```json
{"answer": "JWT 기반 인증을 사용합니다."}
```

Windows에서 한글이 깨지면 30단계에서 겪었던 것과 같은 콘솔 인코딩 문제일 수 있다 — `chcp 65001` 후 재시도하거나, 응답을 파일로 리다이렉트해서 에디터로 확인한다.

## 부록: Anthropic 모델 "Model use case details" 에러

첫 curl 테스트에서 Lambda 로그에 `bedrock:Retrieve` 권한 누락 에러가 나와 `infra/lambda.tf`에 추가했는데(2번 참고), 그 다음엔 전혀 다른 에러가 나왔다.

```text
ValidationException: Model use case details have not been submitted for this account.
Fill out the Anthropic use case details form before using the model.
If you have already filled out the form, try again in 15 minutes.
```

**중요: IAM/Terraform 문제가 아니다.** 같은 계정의 `bedrock-rag-lab` User로 CLI에서 raw `retrieve-and-generate`와 `bedrock-runtime converse`를 직접 호출해도 동일하게 막혀서, Lambda나 코드 쪽 문제가 아니라 **계정 단위로 Anthropic 모델에 걸려있는 게이트**임을 확인했다. 30단계에서는 같은 모델(Claude 3 Haiku)로 성공했었는데, 이 시점에는 막혀 있었다 — 정확한 재현 조건은 알 수 없다.

- 예전 "Model access" 페이지는 폐지됐고, AWS 서버리스 foundation model은 첫 호출 시 계정 단위로 자동 활성화되는 방식으로 바뀌었다. **다만 Anthropic 모델은 예외적으로 use case 양식 제출이 필요**하다 (AWS Marketplace로 제공되는 모델도 별도로 "Marketplace 권한 있는 사용자가 한 번 invoke"해야 하는 등 각자 다른 규칙이 있다). Amazon 자체 모델(Titan, Nova 등)은 이 게이트가 없다.
- 확인 경로: Bedrock 콘솔 → Model catalog → 해당 모델 페이지. 이번 실습에서는 여기서 특별히 이상한 표시는 못 봤고, use case 양식을 다시 제출한 뒤 AWS 안내대로 15분 정도 기다려야 했다 (제출 직후 바로 재시도하면 여전히 막힌다).
- 스크린샷: [003E_anthropic_model_grant.png](screenshots/003E_anthropic_model_grant.png), [003E_anthropic_model_usecase_form.png](screenshots/003E_anthropic_model_usecase_form.png)

**시사점**: 앞으로 이 프로젝트에서 Anthropic 계열 모델을 처음 쓸 때(리전을 바꾸거나 다른 Claude 모델로 바꿀 때 포함)마다 이 게이트를 다시 만날 수 있다. Amazon 자체 모델로 바꾸면 이 문제 자체가 없어진다.

## 보안 체크

- Lambda 실행 Role은 `bedrock:RetrieveAndGenerate`/`Retrieve`/`InvokeModel`을 이 Knowledge Base/생성 모델 ARN으로만 한정했다 (와일드카드 없음).
- API Gateway → Lambda 호출 권한(`aws_lambda_permission`)은 이 API의 `execution_arn`으로 범위를 좁혔다.
- `bedrock-rag-lab` User의 `apigateway:*`는 의도적으로 넓게 잡은 예외다 — 위 4번 참고.
- API에 인증/인가가 없다 (누구나 호출 가능). 이 실습에서는 의도적으로 생략했고, 운영이라면 API Key, IAM 인증, Cognito Authorizer 등을 붙여야 한다.

## 40-api 진행 상태 (2026-08-24)

Terraform apply는 완료됐다 (Lambda, API Gateway, IAM 모두 정상 생성/배포). `curl` 요청도 API Gateway → Lambda까지는 정상 도달하는 것을 로그로 확인했다. 다만 위 부록의 Anthropic use case 게이트 때문에 실제 답변 생성까지는 아직 end-to-end로 확인하지 못했다 — use case 재제출 후 전파 대기 중이다. 전파 완료되는 대로 `curl` 재테스트하고 이 섹션을 갱신한다.

## 다음 단계

CI/CD(GitHub Actions + OIDC)는 이번 실습 범위에서 제외했다. 바로 비용 확인 및 정리로 넘어간다.

```text
40-api (HTTP API 동작 확인)
        ↓
60-cost-cleanup
   ├─ 비용 확인
   └─ terraform destroy
```
