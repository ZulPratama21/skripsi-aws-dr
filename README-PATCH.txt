AWS EC2-ONLY DISASTER RECOVERY RESEARCH PATCH

OBJECTIVE
Remove EKS and Kubernetes from the primary AWS DR experiment and lower cost by
keeping EC2 Region B STOPPED between trials. Retain Terraform + GitHub Actions
+ Ansible, manual and automatic trigger paths, CloudWatch/Route53 detection.

HOW TO APPLY
1. First read docs/MIGRATION.md and docs/RESEARCH_PROTOCOL.md.
2. Unzip into a CLEAN copy/branch of the existing repository, replacing files.
3. Remove obsolete tracked Region-A/k8s directory (git rm -r Region-A/k8s).
4. Backup both Terraform states, run terraform fmt, validate and inspect PLAN.
5. DO NOT terraform apply blindly: it will propose removing managed EKS resources.
6. Configure GitHub environment/secrets and hosted zone; test manually first.
7. Between trials, stop secondary EC2 only after confirming NGINX is disabled.

This package does NOT execute AWS changes. Existing BAB IV RTO and cost results
are NOT valid measurements of the new EC2-only design: collect new data.
