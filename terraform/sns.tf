# SNS Alerts
resource "aws_sns_topic" "terminator" {
  name = "sre-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.terminator.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
