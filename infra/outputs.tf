output "documents_bucket_name" {
  value = aws_s3_bucket.documents.bucket
}

output "vector_bucket_name" {
  value = aws_s3vectors_vector_bucket.rag.vector_bucket_name
}

output "bedrock_service_role_arn" {
  value = aws_iam_role.bedrock_kb.arn
}

output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.rag.id
}

output "knowledge_base_arn" {
  value = aws_bedrockagent_knowledge_base.rag.arn
}

output "data_source_id" {
  value = aws_bedrockagent_data_source.documents.data_source_id
}

output "api_endpoint" {
  value = "${aws_apigatewayv2_api.rag.api_endpoint}/query"
}
