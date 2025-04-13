provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "iam-threat-logs-bucket"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_iam_exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_s3_read" {
  name        = "lambda-s3-read-access"
  description = "Allow Lambda to read objects from the S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = "arn:aws:s3:::iam-threat-logs-bucket/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = "arn:aws:s3:::iam-threat-logs-bucket"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_s3_read_attach" {
  name       = "lambda-s3-read-attach"
  roles      = [aws_iam_role.lambda_exec.name]
  policy_arn = aws_iam_policy.lambda_s3_read.arn
}

resource "aws_lambda_function" "iam_alert" {
  function_name = "iam_alert_handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "iam_alert_handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "../iam_alert_handler.zip"
  source_code_hash = filebase64sha256("../iam_alert_handler.zip")

  environment {
    variables = {
      SLACK_WEBHOOK = var.slack_webhook_url
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_alert.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.cloudtrail_logs.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.iam_alert.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

variable "slack_webhook_url" {
  type        = string
  description = "Your Slack incoming webhook URL"
}

# Terraform: EventBridge integration

resource "aws_cloudwatch_event_rule" "iam_activity_rule" {
  name        = "iam-activity-alert"
  description = "Trigger Lambda for suspicious IAM actions"
  event_pattern = jsonencode({
    "source": ["aws.iam"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventName": ["CreateAccessKey", "AttachUserPolicy", "DeleteUser"]
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule      = aws_cloudwatch_event_rule.iam_activity_rule.name
  target_id = "iamAlertTarget"
  arn       = aws_lambda_function.iam_alert.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_activity_rule.arn
}

# CloudWatch Dashboard

resource "aws_cloudwatch_dashboard" "iam_threat_dashboard" {
  dashboard_name = "IAMThreatDetection"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0,
        y = 0,
        width = 24,
        height = 6,
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.iam_alert.function_name]
          ],
          period = 300,
          stat = "Sum",
          region = "us-east-1",
          title = "IAM Alert Lambda Invocations"
        }
      },
      {
        type = "log",
        x = 0,
        y = 6,
        width = 24,
        height = 6,
        properties = {
          query = "SOURCE '/aws/lambda/${aws_lambda_function.iam_alert.function_name}' | fields @timestamp, @message | filter @message like /Suspicious activity detected/ | sort @timestamp desc | limit 20",
          region = "us-east-1",
          title = "Recent Suspicious Activity Logs"
        }
      }
    ]
  })
}
