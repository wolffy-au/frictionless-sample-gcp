# Infrastructure for sample-gcp: the GCP counterpart of sample-azure's main.bicep.
#
# Declares the APIs, the Firestore (default) database and its security rules.
# Hosting content is uploaded by `firebase deploy --only hosting` in deploy.sh,
# because Terraform cannot upload site files. Everything here works on the
# free Spark plan: no billing account is required.

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

variable "project_id" {
  description = "Firebase / GCP project ID."
  type        = string
}

variable "location" {
  description = "Firestore database location. Keep it in a US free-tier region; it cannot be changed after creation."
  type        = string
  default     = "us-central1"
}

provider "google" {
  project = var.project_id

  # Firebase APIs called with user credentials (gcloud application-default
  # login) need a quota project; use this project rather than gcloud's default.
  user_project_override = true
  billing_project       = var.project_id
}

locals {
  services = [
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "firebaserules.googleapis.com",
    "firestore.googleapis.com",
  ]
}

resource "google_project_service" "services" {
  for_each = toset(local.services)

  service            = each.value
  disable_on_destroy = false
}

# Newly enabled APIs take a short while to propagate; without this the first
# database create can fail with "API has not been used in project ... before".
resource "time_sleep" "services_propagation" {
  create_duration = "60s"

  depends_on = [google_project_service.services]
}

resource "google_firestore_database" "default" {
  name             = "(default)"
  location_id      = var.location
  type             = "FIRESTORE_NATIVE"
  database_edition = "STANDARD" # only the (default) Standard database gets the free quota

  delete_protection_state = "DELETE_PROTECTION_DISABLED"
  # Keep the data if this configuration is destroyed; delete the project to tear down.
  deletion_policy = "ABANDON"

  depends_on = [time_sleep.services_propagation]
}

resource "google_firebaserules_ruleset" "firestore" {
  source {
    files {
      name    = "firestore.rules"
      content = file("${path.module}/firestore.rules")
    }
  }

  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_release" "firestore" {
  # "cloud.firestore" is the release name for the (default) database's rules.
  name         = "cloud.firestore"
  ruleset_name = "projects/${var.project_id}/rulesets/${google_firebaserules_ruleset.firestore.name}"

  lifecycle {
    replace_triggered_by = [google_firebaserules_ruleset.firestore]
  }
}

output "firestore_database" {
  value = google_firestore_database.default.name
}

output "hosting_url" {
  value = "https://${var.project_id}.web.app"
}
