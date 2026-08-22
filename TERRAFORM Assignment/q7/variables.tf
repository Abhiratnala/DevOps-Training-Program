variable "region" {
  default = "ap-southeast-2"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  default = "lab-key"
}

variable "private_key_path" {
  default = "lab-key.pem"
}

variable "mysql_root_password" {
  default = "RootPass123!"
}
