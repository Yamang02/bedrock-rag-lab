locals {
  # Foundation model ARN은 계정 ID 없이 리전만으로 구성된다.
  embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"

  # 생성 모델은 ap-northeast-2에서 on-demand 직접 호출이 안 되는 Anthropic(Marketplace 구독 필요) 대신,
  # Marketplace 구독이 필요 없는 Amazon 자체 모델(Nova Micro)을 cross-region inference profile로 사용한다.
  # inference profile ARN은 foundation-model과 달리 계정 ID를 포함한다.
  generation_model_arn = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.generation_model_id}"

  # inference profile이 실제로 요청을 라우팅하는 대상 리전들에 대한 InvokeModel 권한도 필요하다 (IAM 전용, 리전 와일드카드).
  generation_base_model_arn_pattern = "arn:aws:bedrock:*::foundation-model/${var.generation_base_model_id}"
}

resource "aws_bedrockagent_knowledge_base" "rag" {
  name     = "bedrock-rag-lab-kb"
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

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }

  depends_on = [aws_iam_role_policy.bedrock_kb]
}

resource "aws_bedrockagent_data_source" "documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.rag.id
  name              = "bedrock-rag-lab-docs"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.documents.arn
    }
  }
}
