# Preparations before any AWS teardown (2026-10-21)

## Non-negotiable

- [ ] Main branch has current **EC2-only** Terraform for **both** regions: NO aws_eks_cluster, aws_eks_node_group, Kubernetes manifests deployed by main, or old EKS workflow.
- [ ] Main branch has `.github/workflows/dr-failover.yml`, `.github/workflows/dr-oidc-preflight.yml`, `ansible/failover-playbook.yml`, `scripts/verify_dr.py`, `.gitignore`.
- [ ] The current Region A `cloudfront-dr.tf` is committed **without any hardcoded EIP default**. After tomorrow's Region B apply, run `scripts/write-region-a-vars.ps1` before Region A plan/apply. This creates a gitignored input file.
- [ ] **Every Terraform file** that produced the successful AWS deployments is committed, including Region-A main.tf/failover.tf and Region-B main.tf/github-oidc.tf. Only safe HCL source is committed: never Terraform state, plans, tfvars, SSH key, or PAT.
- [ ] GitHub Environment `dr-lab` allows only `main` branch.
- [ ] Environment var `AWS_DR_ROLE_ARN` set to `arn:aws:iam::853679583110:role/skripsi-github-dr-ec2-start-and-ssh`.
- [ ] Environment var `REGION_B_INSTANCE_ID` set to current ID for an optional OIDC-only preflight today, then update tomorrow after redeploy.
- [ ] Optionally run `AWS DR OIDC Preflight (No Failover)` today to verify real OIDC trust and DescribeInstances. This does not start/stop any EC2 or simulate failure.
- [ ] GitHub repository variable `DR_ALLOW_AUTO` is `false` or absent.
- [ ] EventBridge dispatch rule stays disabled before controlled automatic trial.
- [ ] Record current source Git commit SHA, `terraform validate` output, and reviewed plans. Workflow code not yet executed is **not** proven recovery-ready.

## Tomorrow after full destroy and recreate

1. Apply Region B first (will recreate EC2/key/IP); apply Region A second using refreshed Region B EIP (`scripts/write-region-a-vars.ps1`). `github_pat` must be provided securely during Region A apply.
2. Update GitHub Environment variables:
   - `AWS_DR_ROLE_ARN`: role ARN; same name/account after recreation
   - `REGION_B_INSTANCE_ID`: new EC2 ID
   - `REGION_B_SECURITY_GROUP_ID`: new SG ID
   - `REGION_B_EIP`: new Elastic IP
   - `REGION_B_SSH_HOSTKEY_SHA256`: independently verified **new** EC2 SSH host key fingerprint
   - `CLOUDFRONT_URL`: newly deployed CloudFront HTTPS URL
3. Update GitHub Environment secret `ANSIBLE_SSH_KEY` from the **new** Region B `ansible_private_key` output using a secure local method. Never paste it in chat or logs. Do not commit it.
4. Confirm EC2 A serves correct HTTP 200 and `X-DR-Region: region-a`. Confirm CloudFront returns same.
5. Confirm EC2 B has finished bootstrapping and has known host fingerprint, then put B in `stopped`. NGINX must remain inactive until Ansible recovery.
6. For manual trial: keep EventBridge disabled and DR_ALLOW_AUTO false. Run continuous external HTTP probe, inject controlled failure of A, then run manual workflow.
7. For automatic trial: first restore the same baseline, then deliberately enable EventBridge dispatch and DR_ALLOW_AUTO true for controlled automation. Capture timestamps/artifacts.

## Security and validation caveats

- The GitHub connector currently returns HTTP 403 when creating branches; make Git commits/pushes via authenticated Git CLI on the user's computer.
- The GitHub main branch was previously still EKS-based: merging only workflow files is NOT enough. Commit all current Terraform source together.
- EC2 SSH *host key* fingerprint is **not** the fingerprint of the PEM key pair used to authenticate SSH clients.
- CloudFront origin failover is request-level and not persistent switching; avoid saying Route 53 DNS failover.
- Source readiness is distinct from an end-to-end DR PASS; functional run is deferred until tomorrow.
- Full Terraform destroy deletes deployed resources and resets runtime identities; GitHub code and environment settings persist, but runtime-dependent variables/secrets must be refreshed.
