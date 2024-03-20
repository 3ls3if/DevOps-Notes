terraform {
  backend "gcs" {
    bucket = "devops-directive-storybooks-terraform"
    prefix = "/state/storybooks"
  }
}
