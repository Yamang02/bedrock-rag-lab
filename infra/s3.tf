resource "aws_s3_bucket" "documents" {
  bucket_prefix = "bedrock-rag-lab-docs-"

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "documents" {
  for_each = fileset("${path.module}/../documents", "*.md")

  bucket = aws_s3_bucket.documents.id
  key    = each.value
  source = "${path.module}/../documents/${each.value}"
  etag   = filemd5("${path.module}/../documents/${each.value}")
}
