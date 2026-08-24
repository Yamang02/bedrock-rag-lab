data "archive_file" "query" {
  type        = "zip"
  source_file = "${path.module}/../lambda/query/handler.py"
  output_path = "${path.module}/../lambda/query/handler.zip"
}

data "aws_iam_policy_document" "lambda_query_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_query" {
  name               = "bedrock-rag-lab-lambda-query-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_query_trust.json

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_query_logs" {
  role       = aws_iam_role.lambda_query.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_query_permissions" {
  # CLI에서 30단계 때 검증한 것과 동일한 권한 조합 (RetrieveAndGenerate + 생성 모델 InvokeModel).
  statement {
    sid    = "RetrieveAndGenerate"
    effect = "Allow"
    # RetrieveAndGenerate 호출 시 내부적으로 Retrieve도 함께 요구된다.
    actions   = ["bedrock:RetrieveAndGenerate", "bedrock:Retrieve"]
    resources = [aws_bedrockagent_knowledge_base.rag.arn]
  }

  statement {
    sid       = "InvokeGenerationModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.generation_model_arn]
  }
}

resource "aws_iam_role_policy" "lambda_query" {
  name   = "bedrock-rag-lab-lambda-query-policy"
  role   = aws_iam_role.lambda_query.id
  policy = data.aws_iam_policy_document.lambda_query_permissions.json
}

resource "aws_lambda_function" "query" {
  function_name = "bedrock-rag-lab-query"
  role          = aws_iam_role.lambda_query.arn

  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256

  handler = "handler.handler"
  runtime = "python3.13"
  timeout = 30

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.rag.id
      MODEL_ARN         = local.generation_model_arn
    }
  }

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}
