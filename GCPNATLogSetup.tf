terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.73.0"
    }
  }

  required_version = ">= 0.15.0"
}

variable "project-id" {
  type        = string
  description = "Enter your project ID"
}

variable "topic-name" {
  type        = string
  default     = "sentinel-natlogs-topic"
  description = "Name of existing topic"
}

variable "organization-id" {
  type        = string
  default     = ""
  description = "Organization id"
}

data "google_project" "project" {
  project_id = var.project-id
}

resource "google_project_service" "enable-logging-api" {
  service = "logging.googleapis.com"
  project = data.google_project.project.project_id
}

resource "google_pubsub_topic" "sentinel-natlogs-topic" {
  count   = "${var.topic-name != "sentinel-natlogs-topic" ? 0 : 1}"
  name    = var.topic-name
  project = data.google_project.project.project_id
}

resource "google_pubsub_subscription" "sentinel-subscription-nat" {
  project = data.google_project.project.project_id
  name    = "sentinel-subscription-gcpnatlogs"
  topic   = var.topic-name
  depends_on = [google_pubsub_topic.sentinel-natlogs-topic]
}

resource "google_pubsub_subscription" "sentinel-subscription-audit" {
  project = data.google_project.project.project_id
  name    = "sentinel-subscription-gcpauditlogs"
  topic   = var.topic-name
  depends_on = [google_pubsub_topic.sentinel-natlogs-topic]
}


# NAT Logs Sink
resource "google_logging_project_sink" "sentinel-sink-nat" {
  project    = data.google_project.project.project_id
  count      = var.organization-id == "" ? 1 : 0
  name       = "natlogs-sentinel-sink"
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${var.topic-name}"
  depends_on = [google_pubsub_topic.sentinel-natlogs-topic]

  filter = <<EOT
  logName="projects/${data.google_project.project.project_id}/logs/compute.googleapis.com%2Fnat_flows" OR
  (resource.type="gce_router" AND protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:"v1.compute.routers.")
  EOT

  unique_writer_identity = true
}

# Audit Logs Sink
resource "google_logging_project_sink" "sentinel-sink-audit" {
  project    = data.google_project.project.project_id
  count      = var.organization-id == "" ? 1 : 0
  name       = "audit-logs-sentinel-sink"
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${var.topic-name}"
  depends_on = [google_pubsub_topic.sentinel-natlogs-topic]

  filter = <<EOT
  logName="projects/${data.google_project.project.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
  EOT

  unique_writer_identity = true
}

resource "google_logging_organization_sink" "sentinel-org-sink-nat" {
  count = var.organization-id == "" ? 0 : 1
  name   = "nat-logs-organization-sentinel-sink"
  org_id = var.organization-id
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${var.topic-name}"

  filter = <<EOT
  logName="projects/${data.google_project.project.project_id}/logs/compute.googleapis.com%2Fnat_flows" OR
  (resource.type="gce_router" AND protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:"v1.compute.routers.")
  EOT

  include_children = true
}

resource "google_logging_organization_sink" "sentinel-org-sink-audit" {
  count = var.organization-id == "" ? 0 : 1
  name   = "audit-logs-organization-sentinel-sink"
  org_id = var.organization-id
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${var.topic-name}"

  filter = <<EOT
  logName="projects/${data.google_project.project.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
  EOT

  include_children = true
}

# IAM Bindings for NAT sink
resource "google_project_iam_binding" "log-writer-nat" {
  count   = var.organization-id == "" ? 1 : 0
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_project_sink.sentinel-sink-nat[0].writer_identity
  ]
}

resource "google_project_iam_binding" "log-writer-org-nat" {
  count   = var.organization-id == "" ? 0 : 1
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_organization_sink.sentinel-org-sink-nat[0].writer_identity
  ]
}

# IAM Bindings for Audit sink
resource "google_project_iam_binding" "log-writer-audit" {
  count   = var.organization-id == "" ? 1 : 0
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_project_sink.sentinel-sink-audit[0].writer_identity
  ]
}

resource "google_project_iam_binding" "log-writer-org-audit" {
  count   = var.organization-id == "" ? 0 : 1
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_organization_sink.sentinel-org-sink-audit[0].writer_identity
  ]
}

output "An_output_message" {
  value = "Please copy the following values to Sentinel"
}

output "GCP_project_id" {
  value = data.google_project.project.project_id
}

output "GCP_project_number" {
  value = data.google_project.project.number
}

output "GCP_subscription_names" {
  value = [
    google_pubsub_subscription.sentinel-subscription-nat.name,
    google_pubsub_subscription.sentinel-subscription-audit.name
  ]
}
