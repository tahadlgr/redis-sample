variable "vpc" {
  type        = string
  description = "vpc id"
}

variable "private_subnets" {
  type        = string
  description = "comma separated list of private subnet ids in vpc"
}

variable "ecs_sg" {
  type        = string
  description = "ecs cluster security group id"
}

variable "mesh_zone" {
  type = string
}

variable "mesh_zone_id" {
  type = string
}

variable "mesh_id" {
  type = string
}
