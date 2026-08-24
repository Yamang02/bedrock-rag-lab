resource "aws_s3_bucket" "documents" {
  bucket_prefix = "bedrock-rag-lab-"

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}
