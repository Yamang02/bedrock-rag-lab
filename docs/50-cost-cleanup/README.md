# 50. 비용과 리소스 정리

AWS Budget으로 비용 알림을 설정하고 실습에서 만든 리소스를 삭제한다.

## 이번 단계에서 할 일

- 주요 서비스의 과금 기준 확인
- 월 $10 Budget 설정
- 비용 알림 설정
- `terraform destroy`로 실습 리소스 삭제

## 전체 흐름

```text
비용 구조 확인
    ↓
AWS Budget 생성
    ↓
비용 알림 설정
    ↓
terraform destroy
    ↓
삭제 확인
```

## 1. 비용 구조 확인

이 프로젝트에서 비용이 발생할 수 있는 주요 서비스와 과금 기준은 다음과 같다.

| 서비스 | 주요 과금 기준 |
| --- | --- |
| Titan Text Embeddings V2 | 입력 토큰 |
| Nova Micro | 입력/출력 토큰 |
| S3 Vectors | 저장량 및 요청 |
| S3 | 저장량 및 요청 |
| Lambda | 요청 수 및 실행 시간 |
| API Gateway | API 요청 수 |

이번 실습은 문서와 호출 수가 적어 예상 비용이 작지만, 실제 비용은 사용량과 AWS 가격 정책에 따라 달라질 수 있다.

## 2. Budget 설정

`infra/budget.tf`에서 월 $10 Budget을 만든다.

```hcl
resource "aws_budgets_budget" "monthly_cap" {
  name         = "bedrock-rag-lab-monthly-cap"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["Project$bedrock-rag-lab"]
  }
}
```

이 실습에서 만든 주요 리소스에는 다음 태그를 사용한다.

```text
Project = bedrock-rag-lab
```

같은 태그를 사용하면 프로젝트 리소스를 구분하고 비용을 확인하기 쉽다.

비용 알림은 다음 기준으로 설정한다.

- 실제 비용 50%
- 실제 비용 80%
- 실제 비용 100%
- 예상 비용 100%

## 3. 알림 이메일 설정

실제 이메일 주소는 GitHub에 올리지 않고 로컬 `terraform.tfvars`에서 설정한다.

`infra/terraform.tfvars.example`을 복사한다.

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

`terraform.tfvars`에 알림을 받을 이메일을 입력한다.

```hcl
budget_alert_email = "your-email@example.com"
```

`*.tfvars`는 `.gitignore`에 포함되어 있어야 한다.

## 4. Budget 생성

Budget을 생성할 수 있도록 프로젝트 IAM 정책이 적용되어 있어야 한다.

```bash
cd infra
terraform fmt
terraform validate
terraform plan
terraform apply
```

AWS Budgets 콘솔 또는 CLI에서 생성 여부를 확인한다.

```bash
aws budgets describe-budget \
  --account-id <ACCOUNT_ID> \
  --budget-name bedrock-rag-lab-monthly-cap \
  --profile bedrock-rag-lab
```

![AWS Budget 생성 확인](screenshots/000_budget_console.png)

## 5. 실습 리소스 삭제

모든 테스트가 끝났다면 Terraform으로 생성한 리소스를 삭제한다.

```bash
cd infra
terraform destroy
```

Terraform이 리소스 간의 관계를 확인해 필요한 순서대로 삭제한다.

## 6. 삭제 확인

필요한 리소스를 직접 조회해 삭제되었는지 확인한다.

```bash
aws lambda get-function \
  --function-name bedrock-rag-lab-query \
  --profile bedrock-rag-lab

aws iam get-role \
  --role-name bedrock-rag-lab-kb-role \
  --profile bedrock-rag-lab

aws bedrock-agent list-knowledge-bases \
  --profile bedrock-rag-lab

aws s3vectors list-vector-buckets \
  --profile bedrock-rag-lab

aws s3 ls --profile bedrock-rag-lab
```

`ResourceNotFoundException`, `NoSuchEntity` 또는 빈 결과가 나오면 해당 리소스가 삭제된 것이다.

전체 확인 결과는 [destroy-verification.txt](destroy-verification.txt)에서 볼 수 있다.

## 완료 확인

- 월 $10 Budget 생성 확인
- 비용 알림 설정 확인
- `terraform destroy` 완료
- Lambda, API Gateway, Knowledge Base, S3 Vectors, S3 등 실습 리소스 삭제 확인

여기까지 진행하면 Bedrock RAG 실습이 완료된다.

---

## 참고

### Budget은 비용을 자동으로 막지 않는다

- AWS Budget은 설정한 금액에 도달했을 때 알림을 보내는 기능이다.
- 월 $10 Budget을 만들어도 실제 비용이 $10에서 자동으로 멈추지는 않는다.

### 태그로 프로젝트 비용 구분하기

이 실습에서는 다음 태그를 사용한다.

```text
Project = bedrock-rag-lab
```

- 같은 태그를 사용하면 Cost Explorer나 Budget에서 프로젝트 비용을 구분하기 쉽다.
- 비용 화면에 태그가 바로 보이지 않을 수 있으며 반영까지 시간이 걸릴 수 있다.

### `AccessDenied`가 발생하는 경우

Budget 생성 중 권한 오류가 발생하면 `bedrock-rag-lab` IAM User에 프로젝트용 IAM 정책이 적용되어 있는지 확인한다.

정책 파일:

[`iam/bedrock-rag-lab-provisioning.json`](../../iam/bedrock-rag-lab-provisioning.json)

### 가격 확인

- AWS 가격은 리전과 시점에 따라 달라질 수 있다.
- 정확한 비용은 AWS 공식 Pricing 페이지에서 확인한다.
