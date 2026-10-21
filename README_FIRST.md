# EC2-only AWS DR code preparation (v2)

Source files in this ZIP are **not yet committed to GitHub**. No EC2/CloudFront resource has been started or stopped by generating this package.

1. Back up local checkout `D:\skripsi-aws` and both Terraform states securely outside the git checkout.
2. Copy the ZIP files into the matching repo paths, carefully review diffs, and inspect `docs/TODAY_READY_CHECKLIST.md`.
3. IMPORTANT: This archive does **not** contain your current Region-A main.tf/failover.tf or Region-B main.tf/github-oidc.tf. Those updated local EC2-only files MUST be pushed to GitHub as well. Existing remote main may still deploy EKS.
4. The included Region-A/cloudfront-dr.tf **removes the hardcoded Tokyo IP default**. After current Region B is available, run `powershell -ExecutionPolicy Bypass -File .\scripts\write-region-a-vars.ps1` to write gitignored `Region-A/dr.auto.tfvars` before any Terraform plan/destroy.
5. Commit only safe source files. Verify `git status`, `git diff --cached --name-only`, and **never commit state, plans, keys, secrets, PAT, or `.tfvars`**.
6. Configure GitHub Environment `dr-lab` and optional read-only OIDC preflight while resources still exist today. Do not run the actual DR failover until tomorrow.
7. Do not destroy AWS until code has reached GitHub main and you have captured preflight status; no claim of end-to-end PASS until real experiment.

See `docs/TODAY_READY_CHECKLIST.md` and `docs/OVERNIGHT_TEARDOWN_AND_TOMORROW.md`.
