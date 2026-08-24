locals {
  # Foundation model ARN은 계정 ID 없이 리전만으로 구성된다.
  embedding_model_arn  = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
  generation_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
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
