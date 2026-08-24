# 40. HTTP API

CLI에서 확인한 RAG 기능을 Lambda와 API Gateway를 이용해 HTTP API로 만든다.

## 이번 단계에서 할 일

- RAG 질의를 처리하는 Lambda 함수 생성
- Lambda IAM Role 설정
- API Gateway HTTP API 생성
- `POST /query` 연결
- HTTP 요청으로 RAG 답변 확인

## 전체 흐름

```text
사용자 질문
    ↓
API Gateway
    ↓
Lambda
    ↓
Bedrock Knowledge Base
    ↓
Nova Micro
    ↓
답변
```

## 1. Lambda 함수

`lambda/query/handler.py`에서 Bedrock의 `retrieve_and_generate` API를 호출한다.

```python
import json
import os
import boto3

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
```

Knowledge Base ID와 모델 ARN은 Terraform에서 Lambda 환경 변수로 전달한다.

## 2. Lambda IAM Role

Lambda가 실행되려면 별도의 IAM Role이 필요하다.

```text
Lambda
  ↓ IAM Role
  ├─ CloudWatch Logs 기록
  ├─ Knowledge Base 검색
  └─ Nova Micro 호출
```

`infra/lambda.tf`에서 Role, 권한, Lambda 함수를 함께 정의한다.

## 3. API Gateway 생성

`infra/api_gateway.tf`에서 HTTP API를 만든다.

```text
HTTP API
   ↓
POST /query
   ↓
Lambda
```

API Gateway가 Lambda를 호출할 수 있도록 `aws_lambda_permission`도 함께 생성한다.

## 4. Terraform 실행

Lambda와 API Gateway를 생성할 수 있도록 프로젝트 IAM 정책이 적용되어 있어야 한다.

정책은 [`iam/bedrock-rag-lab-provisioning.json`](../../iam/bedrock-rag-lab-provisioning.json)에서 관리한다.

```powershell
cd infra
terraform fmt
terraform validate
terraform plan
terraform apply
```

![Terraform plan](screenshots/000_infra_plan.png)

완료되면 `api_endpoint` Output을 확인한다.

```powershell
terraform output -raw api_endpoint
```

![API 생성 완료](screenshots/002_grant_auth.png)

## 5. HTTP 요청 테스트

```powershell
$endpoint = terraform output -raw api_endpoint

curl.exe -X POST $endpoint `
  -H "Content-Type: application/json" `
  -d '{"question": "이 프로젝트의 인증 방식은?"}'
```

정상적으로 동작하면 `answer`가 포함된 JSON 응답이 반환된다.

실제 Nova Micro 응답은 [curl-result.json](curl-result.json)에서 확인할 수 있다.

## 완료 확인

- Lambda 함수 생성
- Lambda IAM Role 생성
- API Gateway HTTP API 생성
- `POST /query`와 Lambda 연결
- HTTP 요청으로 RAG 답변 확인

## 다음 단계

[50. 비용과 리소스 정리](../50-cost-cleanup/README.md)에서 비용 알림을 설정하고 실습 리소스를 삭제한다.

---

## 참고

### APAC Cross-Region Inference Profile

최종 실습에서는 Nova Micro를 다음 profile로 호출한다.

```text
apac.amazon.nova-micro-v1:0
```

Cross-Region Inference Profile은 모델 요청을 APAC의 여러 AWS 리전 중 처리 가능한 리전으로 전달할 수 있게 해주는 Bedrock 기능이다.

```text
서울 리전의 Lambda / Knowledge Base
            ↓
APAC Inference Profile
            ↓
APAC 내 지원 리전에서 Nova Micro 추론
```

- Lambda와 Knowledge Base 자체가 다른 리전으로 이동하는 것은 아니다.
- 모델 추론 요청만 다른 APAC 리전에서 처리될 수 있다.
- 이 때문에 `bedrock:GetInferenceProfile`과 `bedrock:InvokeModel` 권한이 필요하다.

### Lambda에서 `AccessDenied`가 발생하는 경우

Lambda가 Bedrock을 호출할 때 `AccessDenied`가 발생하면 Lambda IAM Role의 권한을 확인한다.

이 실습에서는 다음 권한이 필요했다.

- `bedrock:Retrieve`
- `bedrock:RetrieveAndGenerate`
- `bedrock:InvokeModel`
- `bedrock:GetInferenceProfile`

오류 원인은 CloudWatch Logs에서 확인할 수 있다.

### API Gateway 생성 중 `AccessDenied`가 발생하는 경우

Terraform을 실행하는 `bedrock-rag-lab` IAM User에는 Lambda와 API Gateway를 생성할 권한이 필요하다.

![API Gateway 및 Lambda 권한 오류 예시](screenshots/001E_auth_error.png)

프로젝트용 정책은 [`iam/bedrock-rag-lab-provisioning.json`](../../iam/bedrock-rag-lab-provisioning.json)에서 확인한다.

### Anthropic 모델 대신 Nova Micro를 사용한 이유

처음에는 Claude 3 Haiku를 사용했지만 Anthropic Model use case 제출과 AWS Marketplace 관련 권한이 추가로 필요했다.

![Anthropic 모델 사용 등록 화면](screenshots/003E_anthropic_model_grant.png)

이 실습에서는 설정을 단순하게 유지하기 위해 Amazon Nova Micro로 변경했다.

### 모델에 따라 답변 범위가 달라질 수 있음

30단계에서 Claude 3 Haiku로 같은 질문을 테스트했을 때는 인증 방식만 짧게 답했다.

반면 40단계에서 Nova Micro로 테스트했을 때는 질문을 좁혀도 검색된 여러 문서의 내용을 넓게 답하는 경우가 있었다.

RAG에서 검색 결과가 같아도 최종 답변은 생성 모델의 특성에 따라 달라질 수 있다.

### Windows에서 응답 한글이 깨지는 경우

```powershell
chcp 65001
```

또는 응답을 파일로 저장한 뒤 UTF-8을 지원하는 에디터에서 확인한다.
