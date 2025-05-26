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

variable "organization-id" {
  type        = string
  default     = ""
  description = "Organization Id"
}

data "google_project" "project" {
  project_id = var.project-id
}

resource "google_project_service" "enable-logging-api" {
  service = "logging.googleapis.com"
  project = data.google_project.project.project_id
}

resource "google_pubsub_topic" "sentinel-nat-topic" {
  name    = "sentinel-nat-topic"
  project = data.google_project.project.project_id
}

resource "google_pubsub_topic" "sentinel-audit-topic" {
  name    = "sentinel-audit-topic"
  project = data.google_project.project.project_id
}

resource "google_pubsub_subscription" "sentinel-nat-subscription" {
  project = data.google_project.project.project_id
  name    = "sentinel-nat-subscription"
  topic   = google_pubsub_topic.sentinel-nat-topic.name
  depends_on = [google_pubsub_topic.sentinel-nat-topic]
}

resource "google_pubsub_subscription" "sentinel-audit-subscription" {
  project = data.google_project.project.project_id
  name    = "sentinel-audit-subscription"
  topic   = google_pubsub_topic.sentinel-audit-topic.name
  depends_on = [google_pubsub_topic.sentinel-audit-topic]
}

resource "google_logging_project_sink" "sentinel-nat-sink" {
  project    = data.google_project.project.project_id
  name       = "sentinel-nat-sink"
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${google_pubsub_topic.sentinel-nat-topic.name}"
  filter     = <<EOT
logName="projects/${data.google_project.project.project_id}/logs/compute.googleapis.com%2Fnat_flows" 
EOT
  unique_writer_identity = true
  depends_on = [google_pubsub_topic.sentinel-nat-topic]
}

resource "google_logging_project_sink" "sentinel-audit-sink" {
  project    = data.google_project.project.project_id
  name       = "sentinel-audit-sink"
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${google_pubsub_topic.sentinel-audit-topic.name}"
  filter     = <<EOT
(resource.type="gce_router" AND protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:"v1.compute.routers.")
EOT
  unique_writer_identity = true
  depends_on = [google_pubsub_topic.sentinel-audit-topic]
}

resource "google_logging_organization_sink" "sentinel-nat-org-sink" {
  count      = var.organization-id == "" ? 0 : 1
  name       = "nat-logs-organization-sentinel-sink"
  org_id     = var.organization-id
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${google_pubsub_topic.sentinel-nat-topic.name}"
  filter     = <<EOT
logName="projects/${data.google_project.project.project_id}/logs/compute.googleapis.com%2Fnat_flows" 
EOT
  include_children = true
}

resource "google_logging_organization_sink" "sentinel-audit-org-sink" {
  count      = var.organization-id == "" ? 0 : 1
  name       = "audit-logs-organization-sentinel-sink"
  org_id     = var.organization-id
  destination = "pubsub.googleapis.com/projects/${data.google_project.project.project_id}/topics/${google_pubsub_topic.sentinel-audit-topic.name}"
  filter     = <<EOT
resource.type="gce_router" AND protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName:"v1.compute.routers."
EOT
  include_children = true
}

resource "google_project_iam_binding" "log-writer" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_project_sink.sentinel-nat-sink.writer_identity,
    google_logging_project_sink.sentinel-audit-sink.writer_identity
  ]
}

resource "google_project_iam_binding" "log-writer-organization" {
  count   = var.organization-id == "" ? 0 : 1
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_logging_organization_sink.sentinel-nat-org-sink[0].writer_identity,
    google_logging_organization_sink.sentinel-audit-org-sink[0].writer_identity
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

output "GCP_NAT_subscription_name" {
  value = google_pubsub_subscription.sentinel-nat-subscription.name
}

output "GCP_AUDIT_subscription_name" {
  value = google_pubsub_subscription.sentinel-audit-subscription.name
}
