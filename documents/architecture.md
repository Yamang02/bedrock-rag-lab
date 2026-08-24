# Architecture

이 프로젝트의 인프라는 Terraform으로 관리한다.

## Storage

문서는 S3 Bucket에 저장한다.

## Vector Store

임베딩 벡터는 S3 Vectors에 저장한다.

## Knowledge Base

Amazon Bedrock Knowledge Base가 S3 문서를 임베딩하여 Vector Store에 저장하고, 질의 시 관련 문서를 검색한다.
