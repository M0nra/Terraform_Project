variable "aws_region" {  #Provide region in which everthing will get deployed 
  default = "us-east-1"  
}

variable "instance_type" {
  default = "t2.micro"  #Provide appropriate instance type supported by the region
}

variable "access_key" { #Provide access key for a user with the right terraform permissions
}

variable "secret_key" {#Provide secret key for a user with the right terraform permissions
}

variable "own_IP" {# Provide Cidre block of own IP IP 
    default =  ["77.83.137.134/32"] 
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 80
}

variable "elb_port" {
  description = "The port the ELB will use for HTTP requests"
  type        = number
  default     = 80
}