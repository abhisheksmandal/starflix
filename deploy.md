# Starflix — AWS ECR + ECS Deployment Guide

This guide covers the full lifecycle: one-time infrastructure setup, the initial deploy, and the day-to-day update workflow.

**Architecture**
```
Internet → ALB (port 80/443)
              └─► ECS Service: starflix-frontend (nginx, port 80)
                      └─► ECS Service Connect → starflix-backend (Express, port 4000)
```

Both services run on **ECS Fargate** (no EC2 to manage). The frontend nginx proxies `/api/*` to the backend using ECS Service Connect, so the existing `nginx.conf` works unchanged.

---

## Prerequisites

| Tool | Min version | Install |
|------|------------|---------|
| AWS CLI | v2 | `brew install awscli` / [docs](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Docker | 24+ | [docs.docker.com](https://docs.docker.com/get-docker/) |
| jq | any | `brew install jq` / `apt install jq` |

```bash
aws configure          # set Access Key, Secret, region, output=json
aws sts get-caller-identity   # verify credentials work
```

Set these shell variables once — all commands below reference them:

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export APP="starflix"
export ECR_BACKEND="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP-backend"
export ECR_FRONTEND="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP-frontend"
```

---

## Step 1 — Create ECR Repositories

Run once per environment.

```bash
aws ecr create-repository \
  --repository-name $APP-backend \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true

aws ecr create-repository \
  --repository-name $APP-frontend \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true
```

---

## Step 2 — Store the TMDB API Key in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name "$APP/tmdb-api-key" \
  --secret-string "your_tmdb_api_key_here" \
  --region $AWS_REGION
```

Save the ARN returned — you'll need it in the task definition:

```bash
export TMDB_SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$APP/tmdb-api-key" \
  --query ARN --output text)
```

---

## Step 3 — Create IAM Roles

### Task Execution Role (used by ECS to pull images and read secrets)

```bash
# Create the role
aws iam create-role \
  --role-name $APP-ecs-execution-role \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ecs-tasks.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }'

# Attach managed policies
aws iam attach-role-policy \
  --role-name $APP-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Allow reading the TMDB secret
aws iam put-role-policy \
  --role-name $APP-ecs-execution-role \
  --policy-name AllowTMDBSecret \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Action\":[\"secretsmanager:GetSecretValue\"],
      \"Resource\":\"$TMDB_SECRET_ARN\"
    }]
  }"

export EXECUTION_ROLE_ARN=$(aws iam get-role \
  --role-name $APP-ecs-execution-role \
  --query Role.Arn --output text)
```

---

## Step 4 — Create ECS Cluster with Service Connect

```bash
aws ecs create-cluster \
  --cluster-name $APP \
  --service-connect-defaults namespace=$APP \
  --region $AWS_REGION
```

This creates a Cloud Map namespace called `starflix`. ECS Service Connect uses it so the frontend can reach the backend at `backend:4000` — exactly what `nginx.conf` already expects.

---

## Step 5 — Create a CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/$APP \
  --region $AWS_REGION
```

---

## Step 6 — Build & Push Images to ECR

### Authenticate Docker with ECR

```bash
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin \
    "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

### Build, tag, and push

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

# Backend
docker build -t $APP-backend:$IMAGE_TAG ./backend
docker tag  $APP-backend:$IMAGE_TAG $ECR_BACKEND:$IMAGE_TAG
docker tag  $APP-backend:$IMAGE_TAG $ECR_BACKEND:latest
docker push $ECR_BACKEND:$IMAGE_TAG
docker push $ECR_BACKEND:latest

# Frontend
docker build -t $APP-frontend:$IMAGE_TAG ./frontend
docker tag  $APP-frontend:$IMAGE_TAG $ECR_FRONTEND:$IMAGE_TAG
docker tag  $APP-frontend:$IMAGE_TAG $ECR_FRONTEND:latest
docker push $ECR_FRONTEND:$IMAGE_TAG
docker push $ECR_FRONTEND:latest
```

---

## Step 7 — Register ECS Task Definitions

### Backend task definition

```bash
aws ecs register-task-definition --cli-input-json "$(cat <<EOF
{
  "family": "$APP-backend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "backend",
      "image": "$ECR_BACKEND:$IMAGE_TAG",
      "portMappings": [
        {
          "name": "backend",
          "containerPort": 4000,
          "protocol": "tcp",
          "appProtocol": "http"
        }
      ],
      "environment": [
        {"name": "NODE_ENV",      "value": "production"},
        {"name": "PORT",          "value": "4000"},
        {"name": "FRONTEND_URL",  "value": "http://starflix.your-domain.com"}
      ],
      "secrets": [
        {
          "name": "TMDB_API_KEY",
          "valueFrom": "$TMDB_SECRET_ARN"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group":         "/ecs/$APP",
          "awslogs-region":        "$AWS_REGION",
          "awslogs-stream-prefix": "backend"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -qO- http://localhost:4000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 15
      }
    }
  ]
}
EOF
)"
```

### Frontend task definition

```bash
aws ecs register-task-definition --cli-input-json "$(cat <<EOF
{
  "family": "$APP-frontend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "frontend",
      "image": "$ECR_FRONTEND:$IMAGE_TAG",
      "portMappings": [
        {
          "name": "frontend",
          "containerPort": 80,
          "protocol": "tcp",
          "appProtocol": "http"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group":         "/ecs/$APP",
          "awslogs-region":        "$AWS_REGION",
          "awslogs-stream-prefix": "frontend"
        }
      }
    }
  ]
}
EOF
)"
```

---

## Step 8 — Create ECS Services

You need a VPC with at least two public subnets and a security group before running these. Replace the placeholders:

```bash
export VPC_ID="vpc-xxxxxxxxxxxxxxxxx"
export SUBNET_IDS="subnet-xxxxxxxx,subnet-yyyyyyyy"   # comma-separated
export SG_BACKEND="sg-xxxxxxxxxxxxxxxxx"    # allow inbound 4000 from frontend SG
export SG_FRONTEND="sg-xxxxxxxxxxxxxxxxx"   # allow inbound 80 from ALB SG
export ALB_TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:..."
```

### Backend service (internal, no ALB)

```bash
aws ecs create-service \
  --cluster $APP \
  --service-name $APP-backend \
  --task-definition $APP-backend \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$SUBNET_IDS],
    securityGroups=[$SG_BACKEND],
    assignPublicIp=ENABLED
  }" \
  --service-connect-configuration "{
    \"enabled\": true,
    \"namespace\": \"$APP\",
    \"services\": [{
      \"portName\": \"backend\",
      \"discoveryName\": \"backend\",
      \"clientAliases\": [{\"port\": 4000, \"dnsName\": \"backend\"}]
    }]
  }" \
  --region $AWS_REGION
```

### Frontend service (public, behind ALB)

```bash
aws ecs create-service \
  --cluster $APP \
  --service-name $APP-frontend \
  --task-definition $APP-frontend \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$SUBNET_IDS],
    securityGroups=[$SG_FRONTEND],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=$ALB_TARGET_GROUP_ARN,containerName=frontend,containerPort=80" \
  --service-connect-configuration "{
    \"enabled\": true,
    \"namespace\": \"$APP\"
  }" \
  --region $AWS_REGION
```

> **Note:** Before creating the frontend service, create an **Application Load Balancer** in the AWS Console (or via CLI): listener on port 80, forwarding to a target group of type `ip`, pointing at port 80. Paste that target group ARN into `ALB_TARGET_GROUP_ARN`.

---

## Subsequent Deployments

After the one-time setup above, every deploy is just four commands:

```bash
# 1. Authenticate
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin \
    "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# 2. Build & push both images
export IMAGE_TAG=$(git rev-parse --short HEAD)

docker build -t $ECR_BACKEND:$IMAGE_TAG  ./backend  && docker push $ECR_BACKEND:$IMAGE_TAG
docker build -t $ECR_FRONTEND:$IMAGE_TAG ./frontend && docker push $ECR_FRONTEND:$IMAGE_TAG

# 3. Update ECS services (triggers rolling deployment)
aws ecs update-service \
  --cluster $APP \
  --service $APP-backend \
  --force-new-deployment \
  --region $AWS_REGION

aws ecs update-service \
  --cluster $APP \
  --service $APP-frontend \
  --force-new-deployment \
  --region $AWS_REGION

# 4. Wait for rollout to complete
aws ecs wait services-stable \
  --cluster $APP \
  --services $APP-backend $APP-frontend \
  --region $AWS_REGION

echo "Deploy complete."
```

---

## Useful Commands

```bash
# Watch running tasks
aws ecs list-tasks --cluster $APP --region $AWS_REGION

# Describe a service (shows deployment status)
aws ecs describe-services \
  --cluster $APP \
  --services $APP-backend $APP-frontend \
  --region $AWS_REGION \
  | jq '.services[] | {service:.serviceName, status:.deployments[0].rolloutState}'

# Tail logs (last 50 lines)
aws logs tail /ecs/$APP --follow --since 10m

# Force a service restart without a new image
aws ecs update-service --cluster $APP --service $APP-backend --force-new-deployment --region $AWS_REGION

# Scale up/down
aws ecs update-service --cluster $APP --service $APP-frontend --desired-count 3 --region $AWS_REGION

# List ECR images with tags
aws ecr list-images --repository-name $APP-backend --region $AWS_REGION | jq '.imageIds'
```

---

## Security Checklist

- [ ] Backend security group only allows port 4000 from the frontend security group (not `0.0.0.0/0`)
- [ ] ALB security group only allows port 80/443 from the internet
- [ ] Frontend security group only allows port 80 from the ALB security group
- [ ] `TMDB_API_KEY` is stored in Secrets Manager, not hardcoded in the task definition
- [ ] ECR image scanning is enabled (`scanOnPush=true`)
- [ ] CloudWatch logs retention is set (e.g. 30 days) to control costs
