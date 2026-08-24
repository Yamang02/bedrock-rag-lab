# 계정에 다른 프로젝트도 있어서, 계정 전체가 아니라 이 프로젝트 태그(Project=bedrock-rag-lab)로 좁힌다.
# 리소스 태그 활성화 자체가 비용 할당 태그(cost allocation tag) 등록이라, Budgets가 이걸 필터로 쓸 수 있으려면
# 먼저 활성화해야 한다. 활성화 후 실제 비용 데이터에 반영되기까지 최대 24시간 걸릴 수 있다 (AWS 공식 안내).
resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

# 실제 예상 지출은 0에 가깝다 (docs/50-cost-cleanup/README.md 비용 분석 참고).
# 이 예산은 "얼마나 쓸지 예상"이 아니라 무한루프 등 오작동으로 비용이 튀는 상황을 잡는 트립와이어다.
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

  depends_on = [aws_ce_cost_allocation_tag.project]

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
