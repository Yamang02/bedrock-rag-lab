resource "aws_apigatewayv2_api" "rag" {
  name          = "bedrock-rag-lab-api"
  protocol_type = "HTTP"

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}

resource "aws_apigatewayv2_integration" "query" {
  api_id           = aws_apigatewayv2_api.rag.id
  integration_type = "AWS_PROXY"

  integration_method     = "POST"
  integration_uri        = aws_lambda_function.query.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "query" {
  api_id    = aws_apigatewayv2_api.rag.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.query.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.rag.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project     = "bedrock-rag-lab"
    Environment = "lab"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rag.execution_arn}/*/*"
}
