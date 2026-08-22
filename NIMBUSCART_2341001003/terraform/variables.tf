variable "aws_region" {
  description = "AWS region for NimbusCart."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used in resource names."
  type        = string
  default     = "nimbuscart"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "availability_zones" {
  description = "Two AZs used by the three VPCs."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "web_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "app_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "data_vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "web_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "app_subnet_cidr" {
  type    = string
  default = "10.20.1.0/24"
}

variable "nat_subnet_cidr" {
  type    = string
  default = "10.20.2.0/24"
}

variable "db_subnet_a_cidr" {
  type    = string
  default = "10.30.1.0/24"
}

variable "db_subnet_b_cidr" {
  type    = string
  default = "10.30.2.0/24"
}

variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "api_port" {
  type    = number
  default = 5000
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type    = string
  default = "nimbuscart"
}

variable "db_username" {
  type    = string
  default = "nimbusadmin"
}

variable "db_password" {
  description = "RDS master password. Keep the tfvars file out of Git."
  type        = string
  sensitive   = true
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name used for Terraform SSH provisioners."
  type        = string
}

variable "private_key_path" {
  description = "Local path to the private SSH key matching key_pair_name."
  type        = string
}

variable "admin_cidr" {
  description = "Public IPv4 CIDR allowed to SSH to the Web EC2. Use your IP/32, not 0.0.0.0/0."
  type        = string
}
