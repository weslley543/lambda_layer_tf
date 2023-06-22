terraform {
  required_version = "~> 1.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.40"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  layer_name  = "moment-joi"
  layers_path = "${path.module}/../layers/${local.layer_name}/nodejs"
  lambda_name = "convert-date"
  lambda_path = "${path.module}/../src"
  runtime     = "nodejs14.x"
}

resource "null_resource" "build_lambda_layers" {
  provisioner "local-exec" {
    working_dir = "${local.layers_path}"
    command     = "npm install --production && cd ../ && zip -9 -r --quiet ${local.layer_name}.zip *"
  }

  triggers = {
    layer_build = "${md5(file("${local.layers_path}/package.json"))}"
  }
}

resource "aws_lambda_layer_version" "this" {
  filename    = "${local.layers_path}/../${local.layer_name}.zip"
  layer_name  = "${local.layer_name}"
  description = "joi: 14.3.1, moment: 2.24.0"

  compatible_runtimes = ["${local.runtime}"]

  depends_on = [null_resource.build_lambda_layers]
}

data "archive_file" "convert-date" {
  type        = "zip"
  output_path = "${local.lambda_path}/${local.lambda_name}.zip"

  source {
    content  = "${file("${local.lambda_path}/index.js")}"
    filename = "index.js"
  }
}

resource "aws_iam_role" "lambda" {
  name = "Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "LambdaLogging"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
      Effect   = "Allow"
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 3
}


resource "aws_lambda_function" "convert-date" {
  function_name = "${local.lambda_name}"
  handler       = "index.handler"
  runtime       = "${local.runtime}"
  role          = "${aws_iam_role.lambda.arn}"
  layers        = ["${aws_lambda_layer_version.this.arn}"]

  filename         = "${data.archive_file.convert-date.output_path}"
  source_code_hash = "${data.archive_file.convert-date.output_base64sha256}"

  timeout     = 30
  memory_size = 128

  depends_on    = [aws_cloudwatch_log_group.lambda]
}
