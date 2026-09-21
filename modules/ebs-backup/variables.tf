variable "project_tag" {
  description = "Project tag required on protected Minecraft data volumes."
  type        = string
}

variable "volume_ids" {
  description = "Minecraft EBS volumes keyed by stable server identifier."
  type        = map(string)
}
