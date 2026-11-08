# S3 bucket policy: Missing Principal, then Invalid principal

## Symptom
- Saving a policy in the S3 bucket policy editor failed with `Missing required field Principal`.
- After adding a Principal, it failed with `Invalid principal in policy`.

## Investigation
- The first policy was an identity policy (no Principal), so it belonged on the IAM role, not on the bucket.
- On the EC2 server, `aws sts get-caller-identity` showed `assumed-role/projectvision/...`, so the role was attached and its real name was `projectvision`.
- My policy named `visionhive-tools-role`, which did not exist in the account.

## Root cause
1. A bucket policy is a resource policy and always needs a `Principal`. An identity policy (attached to a role or user) does not.
2. S3 checks that the principal exists when you save. I used a role name that I had assumed instead of the real one.

## Fix
Attach the permissions to the role itself as an inline policy (`s3:PutObject` and `s3:GetObject` on `bucket/backups/*`, `s3:ListBucket` on the bucket), or use the correct ARN `arn:aws:iam::<account-id>:role/projectvision` as the Principal. Then test:
```bash
aws s3 cp /tmp/test.txt s3://<bucket>/backups/test.txt
aws s3 ls s3://<bucket>/backups/
```

## Prevention
- Prefer identity policies on roles for EC2 and workloads, and keep bucket policies for cross-account or deny rules.
- Copy the ARN from the IAM console instead of typing it.
- Use `aws sts get-caller-identity` to confirm which identity a server really has.
- Keep the policy least-privilege: only the `backups/` prefix.

## What I learned
The difference between identity-based and resource-based policies, and how to find the role name an instance is using.
