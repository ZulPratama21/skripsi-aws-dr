# AWS DR - Preparation, Teardown, and Next-Day Redeployment

Target: EC2-only Singapore/Tokyo with CloudFront origin failover. No test today.

## Before teardown (today)

1. Keep Terraform files on disk, including Region-A/cloudfront-dr.tf and Region-B/github-oidc.tf.
2. Confirm GitHub workflow and Ansible files have been copied into the local checkout.
3. Review git status. Never commit .tfstate, .tfplan, SSH private keys, GitHub PAT, or credential files.
4. Commit/push code to main **only after review**. The current GitHub main may still contain legacy EKS code, so sync the entire EC2-only configuration coherently.
5. Back up BOTH local Terraform state files securely outside the Git checkout (sensitive; includes PAT and private SSH key). Archive these as historical backups only: do not restore a pre-destroy state over the post-destroy state.
6. Ensure GitHub EventBridge dispatch is disabled and automatic workflow flag DR_ALLOW_AUTO is unset/false.

## Tear down ALL lab AWS resources tonight (charge-minimization)

Use PowerShell from the repository checkout. The commands are destructive and must only target the isolated thesis lab in AWS account 853679583110.

```powershell
aws sts get-caller-identity
cd D:\skripsi-aws\Region-A
terraform plan -destroy '-out=destroy-a.tfplan'
terraform show destroy-a.tfplan
terraform apply destroy-a.tfplan
# The saved destroy plan executes without an extra yes prompt.

cd D:\skripsi-aws\Region-B
terraform plan -destroy '-out=destroy-b.tfplan'
terraform show destroy-b.tfplan
terraform apply destroy-b.tfplan
# Verify resource list before applying saved plan.
```

Region A first: CloudFront, health check, EventBridge, monitoring, EC2, EIP.
Region B second: EC2, EIP, IAM OIDC, and generated key pair.
CloudFront deletion may take several minutes and can require propagation of Disabled status.

**Avoid deleting local source or state files manually.** Do not run destroy if any state references non-lab resources.

Verify no lab resources remain:

```powershell
aws ec2 describe-instances --region ap-southeast-1 --query "Reservations[].Instances[?State.Name!='terminated'].InstanceId" --output json
aws ec2 describe-instances --region ap-northeast-1 --query "Reservations[].Instances[?State.Name!='terminated'].InstanceId" --output json
aws ec2 describe-addresses --region ap-southeast-1 --query "Addresses[].PublicIp" --output json
aws ec2 describe-addresses --region ap-northeast-1 --query "Addresses[].PublicIp" --output json
aws ec2 describe-volumes --region ap-southeast-1 --query "Volumes[].VolumeId" --output json
aws ec2 describe-volumes --region ap-northeast-1 --query "Volumes[].VolumeId" --output json
aws cloudfront get-distribution --id E1SK4CQJJGKSNA
aws route53 list-health-checks --query "HealthChecks[].Id" --output json
aws sqs list-queues --region us-east-1 --queue-name-prefix skripsi-dr-github-dispatch-dlq
aws iam list-open-id-connect-providers
```

After destroy, `cloudfront get-distribution` should return NoSuchDistribution. Billing can lag and charges already incurred are not reversed. Check Billing/Cost Explorer too. Other account resources not managed by Terraform are not covered.

## Tomorrow: rebuild BEFORE testing

1. Reapply Terraform Region A then Region B (validate and inspect plans first). New EIP/CloudFront hostname likely differ.
2. Set GitHub Environment dr-lab variables AWS_DR_ROLE_ARN, REGION_B_INSTANCE_ID, REGION_B_SECURITY_GROUP_ID, REGION_B_EIP, CLOUDFRONT_URL, REGION_B_SSH_HOSTKEY_SHA256 to **new** values.
3. Add environment secret ANSIBLE_SSH_KEY from the **new** Region B Terraform output. Never print/paste this key in tickets, chats, logs, or Git.
4. Obtain/verify SSH host key fingerprint through a trusted source, e.g. instance console system log, before writing REGION_B_SSH_HOSTKEY_SHA256. Network-only ssh-keyscan is not an independent verification.
5. Region A: verify `/healthz` and CloudFront returns X-DR-Region=region-a.
6. Region B: stop instance, wait for stopped, preserve Elastic IP association; confirm initial standby is stopped.
7. Keep GitHub REPOSITORY variable DR_ALLOW_AUTO=false (or unset); EventBridge rule remains disabled during manual trial. GitHub Environment variables alone are not visible to the job-level automatic trigger guard.
8. Start external HTTP/JMeter probe on the CloudFront URL. Fault Region A; start manual workflow_dispatch with verify_cloudfront=true. Measure T0-T1 from probe external timestamps.
9. Recover/reset both regions to the same baseline. Only then activate automation and conduct automatic trial.
10. After experiments, tear down again if no longer needed.

Important: no DNS failover is measured. CloudFront origin failover is the public access layer. These procedures do NOT by themselves prove measured recovery time. The first full end-to-end test is tomorrow.
