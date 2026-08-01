variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "travelmemory"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for both servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 key pair to create"
  type        = string
  default     = "travelmemory-key"
}

variable "public_key_path" {
  description = "Path to the local SSH public key"
  type        = string
  default     = "~/.ssh/travelmemory.pub"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 1.2.3.4/32. SSH is restricted to this."
  type        = string
}

variable "allow_http_from" {
  description = "CIDR allowed to reach the web server over HTTP"
  type        = string
  default     = "0.0.0.0/0"
}
