===============================================================================
 Starflix — dev environment: terraform.tfvars reference
===============================================================================

HOW .tfvars WORKS
-------------------------------------------------------------------------------
terraform.tfvars supplies the ACTUAL values for the input variables declared in
variables.tf. Terraform auto-loads terraform.tfvars on every plan/apply.

  cp terraform.tfvars.example terraform.tfvars   # then edit real values

terraform.tfvars is gitignored because it holds secrets (GitHub token, TMDB
key). Variables marked `sensitive = true` are masked in Terraform output.

Flow of every value:
  terraform.tfvars (value)
    -> variables.tf (declaration / validation)
      -> main.tf    (passed into modules)
        -> AWS resources


1. IDENTITY & NAMING
-------------------------------------------------------------------------------
project     = "starflix"    Base name. Combined in locals.tf as
                            name_prefix = "${project}-${environment}" ->
                            "starflix-dev". Every resource name/tag uses this.
environment = "dev"         Which environment. VALIDATED: must be dev|stage|prod
                            (variables.tf:11). Feeds name_prefix and is injected
                            into containers as NODE_ENV.
aws_region  = "ap-south-1"  Region for all resources (Mumbai). Also used by
                            CodeBuild and the image-seed script.


2. NETWORKING (VPC module)
-------------------------------------------------------------------------------
vpc_cidr             = "10.0.0.0/16"   Private IP range of the whole VPC
                                       (~65k addresses). VALIDATED as real CIDR.
public_subnet_cidrs  = [2x /24]        Subnets hosting the ALBs and NAT Gateway
                                       (internet-facing). One entry per AZ;
                                       locals.tf slices AZs to match the count.
private_subnet_cidrs = [2x /24]        Subnets hosting the ECS EC2 instances
                                       (containers). No direct inbound internet;
                                       outbound via NAT.
single_nat_gateway   = true            COST vs HA tradeoff. true = one shared
                                       NAT Gateway (cheaper, no AZ-level HA).
                                       false = one NAT per AZ. Use true for dev.


3. PORTS (security groups + services)
-------------------------------------------------------------------------------
frontend_port = 80     Port the nginx/frontend container listens on. Opens the
                       SG rule and the ALB target group.
backend_port  = 4000   Port the Express API listens on. SG rule, target group,
                       and baked into BACKEND_URL / VITE_API_URL.


4. TAGGING / FINOPS
-------------------------------------------------------------------------------
owner       = "platform-team"   Applied as an Owner tag on every resource.
cost_center = "eng-infra"       CostCenter tag for AWS cost attribution.


5. DOMAIN & URLS
-------------------------------------------------------------------------------
s3_force_destroy    = true      Lets Terraform delete S3 buckets even if they
                                contain objects. Convenient for dev; dangerous
                                in prod (set false).
domain_name         = "starflix.com"   Root domain for Route 53 zone + ACM
                                certs. Only used when enable_dns = true.
public_frontend_url             Custom domain CNAMEd to the frontend ALB. Used
                                as the backend FRONTEND_URL (CORS origin) so
                                browser API calls aren't blocked (main.tf:341).
                                Empty = fall back to raw ALB DNS name.
public_backend_url              Custom domain CNAMEd to the backend ALB. Baked
                                into the frontend build as VITE_API_URL at
                                CodeBuild time (main.tf:410).
                                WARNING: changing it requires a frontend rebuild
                                because it is compiled into the static JS.
enable_dns          = false     Master switch for Route 53 + ACM. When false,
                                the dns module is skipped (count = 0) and the
                                ALB runs HTTP-only (no TLS).


6. SAFETY / LIFECYCLE
-------------------------------------------------------------------------------
enable_deletion_protection   = false   ALB deletion protection. false in dev so
                                       you can destroy freely; true in prod.
secrets_recovery_window_days = 0       Days Secrets Manager keeps a deleted
                                       secret before permanent deletion. 0 =
                                       instant delete (fast dev teardown + lets
                                       you re-create a same-named secret now).
                                       Prod should use 7-30.


7. ECS HOST FLEET (EC2 instances running containers)
-------------------------------------------------------------------------------
ecs_instance_type         = "t3.small"   EC2 size for the ECS cluster hosts.
ecs_ami_id                = ""           Custom AMI. Empty = latest ECS-optimised
                                         Amazon Linux 2 AMI.
ecs_desired_capacity      = 3            Number of EC2 hosts normally. Also used
                                         as initial desired_count for each ECS
                                         service (main.tf:266,320).
ecs_min_size              = 1            Lower bound for the host ASG.
ecs_max_size              = 5            Upper bound for the host ASG.
enable_container_insights = false        CloudWatch Container Insights (extra
                                         metrics + cost). Off for dev.


8. SERVICE AUTO-SCALING (task count, not hosts)
-------------------------------------------------------------------------------
Controls Application Auto Scaling on the ECS services (how many container copies
run), separate from EC2 host scaling above.

enable_service_autoscaling        = true   Turns on target-tracking scaling.
service_autoscaling_min           = 2      Never fewer than 2 tasks per service
                                           -> removes single-task SPOF.
service_autoscaling_max           = 4      Cap on tasks per service (bounded by
                                           host capacity).
service_autoscaling_cpu_target    = 60     Add tasks when avg CPU > 60%.
service_autoscaling_memory_target = 70     Add tasks when avg memory > 70%.


9. CDN / FIREWALL (off for dev)
-------------------------------------------------------------------------------
enable_cloudfront = false   CloudFront CDN module. Off in dev to save cost;
                            when off, traffic hits the ALB directly.
enable_waf        = false   Web Application Firewall on CloudFront. Prod only.


10. CONTAINER IMAGES & TASK SIZING
-------------------------------------------------------------------------------
frontend_image_tag = "latest"   Which ECR image tag the frontend deploys.
backend_image_tag  = "latest"   Which ECR image tag the backend deploys.
frontend_cpu       = 256        CPU units per frontend task (256 = 0.25 vCPU).
frontend_memory    = 512        Memory (MiB) per frontend task.
backend_cpu        = 256        CPU units per backend task.
backend_memory     = 768        Memory (MiB) per backend task (more for TMDB
                                enrichment).


11. LOGGING & CLOUDWATCH ALARMS
-------------------------------------------------------------------------------
log_retention_days                 = 7    How long ECS logs are kept.
cloudwatch_cpu_threshold           = 80   Alarm when ECS CPU > 80%.
cloudwatch_memory_threshold        = 80   Alarm when memory > 80%.
cloudwatch_5xx_threshold           = 10   Alarm when ALB returns >10 5xx/min.
cloudwatch_response_time_threshold = 5    Alarm when target response time > 5s.


12. CI/CD (CodeBuild)
-------------------------------------------------------------------------------
github_repo_url            The repo CodeBuild pulls source from. REQUIRED (no
                           default).
github_branch  = "main"    Branch CodeBuild builds.
github_token   = "ghp_..." GitHub PAT for source auth + webhook registration.
                           Scopes: repo, admin:repo_hook. SENSITIVE. Prefer the
                           env var TF_VAR_github_token over writing to a file.
                           Empty = manage the secret value manually via AWS CLI.


13. APPLICATION SECRET
-------------------------------------------------------------------------------
tmdb_api_key = "..."   TMDB API key for real movie artwork. SENSITIVE. Stored
                       in Secrets Manager and injected into the backend task
                       ONLY when non-empty (main.tf:347). Empty = backend runs
                       with placeholder images and the task still starts.


KEY DESIGN PATTERNS
-------------------------------------------------------------------------------
1. Feature flags (enable_dns, enable_cloudfront, single_nat_gateway) collect in
   locals.features and drive count/conditionals -- one flag turns whole modules
   on or off.
2. Empty-string fallbacks -- public_frontend_url, public_backend_url,
   ecs_ami_id, github_token, tmdb_api_key all treat "" as "not set" and fall
   back to a sensible default (raw ALB DNS, latest AMI, skip the secret).
3. Secrets never belong in Git -- put real github_token / tmdb_api_key in
   terraform.tfvars (gitignored) or TF_VAR_* env vars.
