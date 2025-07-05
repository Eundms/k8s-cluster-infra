variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Prefix for naming AWS resources"
  type        = string
  default     = "vvue-k8s-cluster"
}

variable "bastion_instance_type" {
  description = "Instance type for Bastion"
  type        = string
  default     = "t3.micro"
}

variable "master_instance_type" {
  description = "Instance type for Kubernetes Master"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes Worker"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "AWS EC2 SSH key pair name"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your local machine's public IP in CIDR format (e.g. 203.0.113.5/32)"
  type        = string
}