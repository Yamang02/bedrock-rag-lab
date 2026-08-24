resource "aws_s3vectors_vector_bucket" "rag" {
  vector_bucket_name = "bedrock-rag-lab-vectors"
}

resource "aws_s3vectors_index" "rag" {
  index_name         = "bedrock-rag-lab-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.rag.vector_bucket_name

  data_type       = "float32"
  dimension       = var.vector_dimension
  distance_metric = var.vector_distance_metric
}
