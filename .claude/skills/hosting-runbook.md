---
name: hosting-runbook
description: Use when the user asks for hosting / deployment help — "help me self-host", "set up hosting for this PS", "deploy parking to AWS", "I have a VPS", "stand this up on a server", "deploy to Kubernetes". Walks `deploy/HOSTING.md` tailored to the user's environment (cloud / cluster / VPS), generating secrets and tfvars as needed.
---

# hosting-runbook

Walk a user through deploying a PublicStack Public Service. Tailors
`deploy/HOSTING.md` to their context — cloud, cluster, budget — and
helps them get to a live `curl /health` response.

## When this fires

User says any of:

- "Help me self-host this"
- "Deploy parking to AWS"
- "Set up hosting on a VPS"
- "I have a Kubernetes cluster"
- "Stand this up on a server"
- "What's the cheapest way to host this"

Do NOT use this skill for blueprint development itself — only for
deploying generated Public Services.

## Prerequisites (verify first)

1. CWD is inside a Public Service. Walk up looking for
   `BLUEPRINT_VERSION`. If missing → suggest `new-service`. HALT.

2. `BLUEPRINT_VERSION` ≥ `0.4.0`. The `deploy/` tree ships in v0.4.0;
   prior versions had empty placeholders. If on an earlier version,
   suggest `upgrade-blueprint` first.

3. Read `deploy/HOSTING.md` to confirm the three on-ramps are there.

## Primary flow

1. **Ask about context.** Via AskUserQuestion:

   - **On-ramp:** VPS docker-compose / Helm chart / AWS Terraform /
     other-cloud Terraform.
   - **Environment:** dev / staging / prod.
   - **Budget hint:** "< $30/mo" / "$50-200/mo" / "managed prod with
     HA / multi-AZ".

2. **Recommend on-ramp** if user hasn't picked or budget conflicts
   with their pick:

   - Budget < $30/mo → strongly recommend VPS docker-compose.
   - Already has K8s cluster → recommend Helm chart (cluster cost
     already paid).
   - Wants HA / multi-AZ / "managed" → recommend AWS Terraform prod.
   - GCP / Hetzner / R2 picked → tell them those modules are stubs in
     v0.4.0; they'll fill in real impls. Suggest bare-k8s instead if
     they want cloud-neutral.

3. **Walk the chosen path** (see per-path sections below).

4. **Verify the deploy.** Final step regardless of path:

   ```bash
   curl -fsSL https://<public-hostname>/health
   # → {"status":"ok","service":"<ps-slug>"}

   curl -fsSL https://<public-hostname>/
   # → Flutter resident-app HTML
   ```

   Open the URL in a browser; confirm the resident app loads.

## Per-path walkthroughs

### VPS docker-compose

Reference: `deploy/compose/README.md` (the runbook lives there).

1. **Prereqs:**
   - Ubuntu 22.04+ VPS with ≥ 2 GB RAM (Hetzner CX21 €5/mo, DO
     basic-2gb $12/mo, Vultr 2 GB $12/mo all qualify; see
     `blueprint/docs/cost-floor.md` for the budget table).
   - DNS A record pointing at the VPS — required BEFORE first boot so
     Caddy can complete the Let's Encrypt HTTP-01 challenge.
   - Docker Engine + Docker Compose v2 installed (`curl -fsSL
     https://get.docker.com | sh`).

2. **On the VPS:**

   ```bash
   git clone https://github.com/<org>/<ps>.git
   cd <ps>
   cp deploy/compose/.env.prod.example .env.prod
   vi .env.prod
   ```

3. **Fill in .env.prod.** Help the user generate secrets:

   ```bash
   openssl rand -hex 32    # POSTGRES_PASSWORD
   openssl rand -hex 32    # REDIS_PASSWORD
   caddy hash-password     # METRICS_BASIC_AUTH
   ```

   Required fields:
   - `PUBLIC_HOSTNAME` — must match DNS
   - `IMAGE_TAG` — `latest` for cheap rolling; `git-<sha>` for
     reproducibility
   - `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `METRICS_BASIC_AUTH`

4. **Build the Flutter web apps.** Either on the VPS (requires Flutter
   installed) or build locally and rsync up:

   ```bash
   cd apps/resident && flutter build web --release && cd -
   cd apps/staff    && flutter build web --release && cd -
   cd apps/kiosk    && flutter build web --release && cd -
   ```

5. **Pull + start:**

   ```bash
   docker compose -f deploy/compose/prod.yml --env-file .env.prod pull
   docker compose -f deploy/compose/prod.yml --env-file .env.prod up -d
   ```

   Caddy acquires a Let's Encrypt cert on first request. Watch logs:
   `docker compose -f deploy/compose/prod.yml logs -f caddy`.

6. **Verify** (see §Primary flow step 4).

### Helm chart

Reference: `deploy/k8s/README.md`.

1. **Prereqs:**
   - K8s cluster (EKS / GKE / AKS / kind / on-prem) with kubectl
     context set up.
   - `helm` v3.12+.
   - Ingress controller (nginx-ingress by default; ALB-ingress for EKS;
     GCE-ingress for GKE).
   - cert-manager for HTTPS (or use the cluster's existing cert
     setup).

2. **Update Helm dependencies + values:**

   ```bash
   helm dep update ./deploy/k8s
   ```

   Create `values-prod.yaml` with cluster-specific overrides:

   ```yaml
   publicHostname: <ps>.example.org

   api:
     replicaCount: 3
     autoscaling:
       enabled: true

   ingress:
     className: alb      # or nginx, gce
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
   ```

3. **For bring-your-own DB / Redis** (disable Bitnami subcharts):

   ```yaml
   postgresql:
     enabled: false
   externalPostgres:
     enabled: true
     url: postgresql+asyncpg://user:pass@hostname:5432/dbname
     secretName: pg-creds

   redis:
     enabled: false
   externalRedis:
     enabled: true
     url: redis://:pass@hostname:6379/0
     secretName: redis-creds
   ```

4. **Install:**

   ```bash
   helm install <ps> ./deploy/k8s \
     --namespace <ps> \
     --create-namespace \
     -f values-prod.yaml \
     --set postgresPassword=$(openssl rand -hex 32) \
     --set redisPassword=$(openssl rand -hex 32)
   ```

5. **Verify:**

   ```bash
   kubectl rollout status deploy/<ps>-api -n <ps>
   kubectl port-forward svc/<ps>-api 8000:8000 -n <ps>
   curl http://localhost:8000/health
   ```

### AWS Terraform (default cloud)

Reference: `deploy/HOSTING.md` §3 + `deploy/terraform/modules/`.

1. **Prereqs:**
   - AWS account + IAM credentials with permissions for RDS, S3, ECS,
     ELB, CloudFront, ACM, CloudWatch Logs, ElastiCache, IAM (for
     ECS task roles).
   - VPC with public + private subnets across ≥ 2 AZs (bring-your-own;
     not provisioned by these modules).
   - ACM cert in **us-east-1** for CloudFront (CloudFront
     requirement; rest of infra in any region).
   - `terraform` ≥ 1.6 installed.

2. **Choose environment:** dev / staging / prod. Default to prod for
   real deployments.

3. **Copy + fill tfvars:**

   ```bash
   cd deploy/terraform/environments/prod
   cp terraform.tfvars.example terraform.tfvars
   vi terraform.tfvars
   ```

   Help the user fill in:
   - `vpc_id`, `public_subnet_ids`, `private_subnet_ids` — from
     existing VPC.
   - `image_prefix` — `ghcr.io/<owner>/<repo>` (CI publishes this
     prefix; see `template/{{…}}/.github/workflows/ci.yml`
     docker-push job).
   - `image_tag` — `latest` for rolling; `git-<sha>` for pinned.
   - `aliases` — `["<ps>.example.org"]` (must match the ACM cert).
   - `cloudfront_certificate_arn` — ACM cert ARN, MUST be in
     us-east-1.
   - `alb_certificate_arn` — optional ACM cert in the ALB's region.
   - `postgres_master_password` — load from your secret manager;
     never commit.

4. **Apply:**

   ```bash
   terraform init
   terraform plan       # review what'll change
   terraform apply
   ```

5. **Run the migrator** (one-shot ECS task after each deploy):

   ```bash
   aws ecs run-task \
     --cluster $(terraform output -raw ecs_cluster_name) \
     --task-definition $(terraform output -raw migrator_task_definition_arn) \
     --launch-type FARGATE \
     --network-configuration "awsvpcConfiguration={subnets=[\"<subnet1>\",\"<subnet2>\"],securityGroups=[\"<sg>\"]}"
   ```

6. **Upload Flutter web builds** to the static S3 bucket:

   ```bash
   STATIC_BUCKET=$(terraform output -raw static_bucket_name)
   for app in resident staff kiosk; do
     (cd apps/$app && flutter build web --release)
     aws s3 sync apps/$app/build/web s3://$STATIC_BUCKET/$app/
   done
   ```

   Adjust S3 paths if CloudFront expects different prefixes.

7. **Point DNS:** Route 53 alias record from `<ps>.example.org` to
   `$(terraform output -raw cdn_distribution_domain_name)`.

8. **Verify** (see §Primary flow step 4).

### Cloud swap (advanced)

Reference: `deploy/HOSTING.md` §Swapping to another cloud.

`terraform apply -var cloud=bare-k8s` against the same environment
provisions the in-cluster equivalent (postgres-operator + MinIO +
Redis Helm + the PS Helm chart). Same outputs, same DNS target.

gcp / hetzner / r2 are stubs in v0.4.0 — they fail at plan time with
a "PRs welcome" message.

## Branches

### User has no DNS / domain yet

Suggest a quick path: register a domain (Cloudflare Registrar, Porkbun,
Namecheap), or use a free subdomain (free DNS providers, or
`duckdns.org`). For VPS path, DNS must be pointing BEFORE first boot
or Caddy fails Let's Encrypt issuance.

### User wants free / educational TLS

Caddy uses Let's Encrypt by default — free, automatic. No action.

For AWS, ACM is free. No action.

### Migrator fails mid-deploy

ECS RunTask exited non-zero. Common causes:
- DB connection error (security groups not allowing ECS → RDS).
- Migration script error (Alembic version mismatch — usually means
  the user is on a prior blueprint version; suggest
  `upgrade-blueprint`).

Surface the CloudWatch Logs for the migrator task:

```bash
aws logs tail /ecs/<name_prefix>/migrator --follow
```

### CI hasn't published images yet (first deploy)

If `image_prefix` references a tag that doesn't exist in GHCR yet,
ECS / docker-compose pull fails. Two options:

1. **Quick:** build and push locally:

   ```bash
   docker build -t ghcr.io/<owner>/<repo>-api:latest -f services/api/Dockerfile .
   docker push ghcr.io/<owner>/<repo>-api:latest
   # repeat for worker + migrator
   ```

2. **Right:** push a commit to `main` and let CI publish. Then re-apply.

### Compliance check on a deployed PS

After deploy, `publicstack-compliance run --strict` should still
report green — Phase 5 ships compliant-by-default. If a deploy
introduced new warnings, walk them via `compliance-fix`.

## Failure recovery

- **`docker compose up -d` fails.** Read `docker compose logs`; common
  causes: port 80/443 already bound, env file missing, image pull
  failure.

- **`terraform apply` fails.** Read the verbatim error. Common causes:
  permission missing on an AWS resource, ACM cert not validated,
  VPC/subnet mismatches.

- **`helm install` fails.** Common: missing dependency repo
  (`helm repo add bitnami https://charts.bitnami.com/bitnami` first),
  CRDs missing (cert-manager not installed).

- **Cert fails to issue.** Caddy / cert-manager / ACM each have
  different troubleshooting paths. The single biggest gotcha: DNS not
  pointing at the deploy yet. Wait for propagation; re-trigger
  issuance.

## Worked example

User says: "Deploy parking to AWS. I have an AWS account, my budget
is around $150/mo, I want HA / multi-AZ in prod."

1. Verify CWD is `Parking/`. `BLUEPRINT_VERSION` is 0.4.0+.

2. AskUserQuestion:
   - On-ramp: AWS Terraform.
   - Environment: prod.
   - Budget: ~$150/mo.

3. Recommend: AWS prod environment. Note the budget aligns with the
   AWS Terraform prod numbers from `blueprint/docs/cost-floor.md`
   ($130-250/mo).

4. Walk prereqs:
   - Confirm AWS credentials configured (`aws sts get-caller-identity`).
   - Confirm VPC + subnets exist.
   - Confirm ACM cert in us-east-1 for `parking.publicstack.org`.

5. `cd deploy/terraform/environments/prod && cp terraform.tfvars.example
   terraform.tfvars`. Walk the user through filling in each field,
   with suggested values for the AWS multi-AZ shape:

   ```hcl
   cloud                    = "aws"
   environment              = "prod"
   region                   = "us-east-1"
   vpc_id                   = "vpc-..."
   public_subnet_ids        = ["subnet-...", "subnet-..."]
   private_subnet_ids       = ["subnet-...", "subnet-..."]
   image_prefix             = "ghcr.io/publicstackorg/parking"
   image_tag                = "git-abc1234"
   aliases                  = ["parking.publicstack.org"]
   cloudfront_certificate_arn = "arn:aws:acm:us-east-1:..."
   postgres_instance_class  = "db.t4g.small"
   postgres_multi_az        = true
   queue_num_cache_clusters = 2
   api_desired_count        = 2
   postgres_master_password = "<from secret manager>"
   ```

6. Run `terraform init && terraform apply`. ~10 min.

7. After apply, run the migrator one-shot:

   ```bash
   aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) \
     --task-definition $(terraform output -raw migrator_task_definition_arn) \
     --launch-type FARGATE \
     --network-configuration "awsvpcConfiguration={...}"
   ```

8. Upload Flutter web builds to the static bucket:

   ```bash
   STATIC=$(terraform output -raw static_bucket_name)
   for app in resident staff kiosk; do
     (cd apps/$app && flutter build web --release)
     aws s3 sync apps/$app/build/web s3://$STATIC/$app/
   done
   ```

9. Route 53 alias `parking.publicstack.org` → CloudFront distribution
   domain. Wait for DNS propagation.

10. Verify:

    ```bash
    curl -fsSL https://parking.publicstack.org/health
    # → {"status":"ok","service":"parking"}
    ```

End state: Parking running on AWS Fargate prod, ~$150/mo, with
multi-AZ Postgres + ElastiCache, CloudFront distribution at
`parking.publicstack.org`.
