variable "hubs" {
  description = "Event Hubs"
  type = list(object({
    name                                           = string
    partition_count                                = number
    message_retention                              = number
  }))
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Location in which to deploy"
  type        = string
}

variable "namespace_name" {
  description = "Namespace name"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies tags for all the resources"
  default     = {
    createdWith = "Terraform"
  }
}

variable "capacity" {
  description = "Specifies the EH capacity"
  type        = number
  default     = 1
}

variable "sku" {
  description = "(Optional) The SKU name of the eventhub. Possible values are Basic, Standard and Premium. Defaults to Basic"
  type        = string
  default     = "Standard"

  validation {
    condition = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "The eventhub sku is invalid."
  }
}

variable "allowed_subnets" {
  description = "subnets"
  type = list(string)
  default = []
}

variable "allowed_ips" {
  description = "permitted ip ranges"
  type = list(string)
  default = []
}