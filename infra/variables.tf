variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_profile" {
  type    = string
  default = "bedrock-rag-lab"
}

variable "embedding_model_id" {
  type    = string
  default = "amazon.titan-embed-text-v2:0"
}

variable "generation_model_id" {
  type    = string
  default = "apac.amazon.nova-micro-v1:0"
}

variable "generation_base_model_id" {
  type    = string
  default = "amazon.nova-micro-v1:0"
}

variable "vector_dimension" {
  type    = number
  default = 1024
}

variable "vector_distance_metric" {
  type    = string
  default = "cosine"
}
