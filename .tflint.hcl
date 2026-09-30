# task3-lambda-troubleshooting/original/ holds the challenge's broken files,
# preserved byte for byte as evidence for FIXES.md. Linting them would report
# the very defects the document explains, which is noise, and "fixing" them
# would destroy the evidence.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
