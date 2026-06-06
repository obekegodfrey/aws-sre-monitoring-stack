variable "region" {
    type = string
    default = "us-east-1"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "alert_email" {
  description = "Email to receive CloudWatch alerts"
  type        = string
  default = "obekegodfrey4@gmail.com"
}