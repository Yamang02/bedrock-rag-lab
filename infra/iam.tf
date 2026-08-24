data "aws_caller_identity" "current" {}

# Bedrock가 이 Role을 assume할 때 자기 자신 계정의 knowledge base 요청만 신뢰하도록 제한한다.
# (Confused deputy 방지 - AWS 권장 조건)
data "aws_iam_policy_document" "bedrock_kb_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "bedrock-rag-lab-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_trust.json

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}

data "aws_iam_policy_document" "bedrock_kb_permissions" {
  statement {
    sid       = "BedrockListModels"
    effect    = "Allow"
    actions   = ["bedrock:ListFoundationModels", "bedrock:ListCustomModels"]
    resources = ["*"]
  }

  statement {
    sid     = "BedrockInvokeModels"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel"]
    # generation_model_arn은 inference profile 자체, generation_base_model_arn_pattern은
    # 그 profile이 라우팅하는 실제 리전들의 foundation model (cross-region inference 문서에서 요구).
    resources = [local.embedding_model_arn, local.generation_model_arn, local.generation_base_model_arn_pattern]
  }

  statement {
    sid       = "BedrockGetInferenceProfile"
    effect    = "Allow"
    actions   = ["bedrock:GetInferenceProfile"]
    resources = [local.generation_model_arn]
  }

  statement {
    sid       = "S3ListDocumentsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.documents.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "S3GetDocuments"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # S3 Vectors 리소스 자체의 ARN 형식(bucket/{name}/index/{name})을 그대로 사용한다.
  statement {
    sid    = "S3VectorsAccess"
    effect = "Allow"
    actions = [
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
      "s3vectors:GetIndex",
    ]
    resources = [aws_s3vectors_index.rag.index_arn]
  }
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "bedrock-rag-lab-kb-policy"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_permissions.json
}
