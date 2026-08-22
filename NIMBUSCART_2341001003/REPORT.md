# NimbusCart — Three-Tier Application on AWS using Terraform and Docker

## 1. Project overview

NimbusCart is a small product-catalog application deployed as three tiers:

1. **Web tier** — NGINX on a public Web EC2 instance. It serves `index.html` and reverse-proxies `/api/*` to the private App EC2.
2. **App tier** — a Flask REST API running as one Docker container on a private App EC2 instance.
3. **Database tier** — Amazon RDS PostgreSQL in an isolated Data VPC.

The frontend has two real operations: it fetches products with `GET /api/items` and adds products with `POST /api/items`. After a successful POST, it performs another GET so the new database row appears in the table.

## 2. Technology choices

### API: Flask

Flask was selected because the assignment allows Flask, Express, or FastAPI and this application needs only three small routes. Flask keeps the API beginner-readable and makes the Docker image small and easy to explain during evaluation.

### Database: PostgreSQL

PostgreSQL was selected instead of MySQL because it is straightforward to run locally in Docker and is well supported by Python through `psycopg2-binary`. The table is created by the API at startup; Terraform never executes SQL against RDS.

## 3. Application routes

The container exposes:

- `GET /health` — returns HTTP 200 and does not require the database.
- `GET /items` — reads `products` from PostgreSQL and returns JSON.
- `POST /items` — validates the JSON body, inserts a product, and returns the inserted row.

NGINX exposes these through `/api/`:

- `GET /api/health`
- `GET /api/items`
- `POST /api/items`

The frontend itself uses `/api/items`, so the browser never needs to know the private App IP.

## 4. Database schema

The API creates this table automatically:

```sql
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL CHECK (stock >= 0)
);
```

No laptop-to-RDS database connection is required, and Terraform does not run `CREATE TABLE`.

## 5. AWS network architecture

The project uses three VPCs:

| Tier | VPC | Subnet | Purpose |
|---|---|---|---|
| Web | `10.10.0.0/16` | `10.10.1.0/24` public | NGINX/Web EC2 |
| App | `10.20.0.0/16` | `10.20.1.0/24` private | Docker/Flask EC2 |
| App NAT | `10.20.0.0/16` | `10.20.2.0/24` public | NAT Gateway |
| Data | `10.30.0.0/16` | `10.30.1.0/24` private | RDS subnet A |
| Data | `10.30.0.0/16` | `10.30.2.0/24` private | RDS subnet B |

The Web VPC has an Internet Gateway. The App VPC has a public NAT subnet and NAT Gateway plus a private App subnet. The Data VPC has no Internet Gateway and no NAT Gateway.

## 6. Traffic flow

### Browser to Web

`Internet -> Web EC2 public IP -> NGINX :80`

### Web to App

`NGINX -> Web route table -> Web/App VPC peering -> App route table -> App EC2 private IP :5000`

### App to Database

`Flask container -> App route table -> App/Data VPC peering -> Data route table -> RDS :5432`

### App to ECR

`App EC2 -> private subnet route table -> NAT Gateway -> App VPC Internet Gateway -> AWS/ECR`

The App instance has no public IP. A NAT Gateway allows private instances to initiate outbound Internet connections while preventing unsolicited inbound Internet connections.

## 7. VPC peering routes

There are two peering connections:

1. Web VPC <-> App VPC
2. App VPC <-> Data VPC

The route tables contain routes in both directions. Peering itself does not automatically create routes.

Web route table:

```text
10.20.0.0/16 -> Web/App peering
0.0.0.0/0    -> Web Internet Gateway
```

App route table:

```text
10.10.0.0/16 -> Web/App peering
10.30.0.0/16 -> App/Data peering
0.0.0.0/0    -> NAT Gateway
```

Data route table:

```text
10.20.0.0/16 -> App/Data peering
```

There is intentionally no default Internet route in the Data VPC.

## 8. Security groups

### Web SG

- TCP 80 from `0.0.0.0/0`
- TCP 22 only from the configured administrator CIDR
- Outbound allowed

### App SG

- TCP 5000 only from the Web SG
- TCP 22 only from the Web SG so Terraform can use the Web EC2 as an SSH bastion
- Outbound allowed

### DB SG

- TCP 5432 only from the App SG
- Outbound allowed

Therefore the Internet cannot directly access the App EC2 or RDS.

## 9. ECR and IAM

Terraform creates one private ECR repository for the API image. A Terraform `local-exec` provisioner builds and pushes the image after the repository exists.

The App EC2 has an IAM instance profile. It receives only the ECR permissions needed to authenticate and pull the image:

- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:BatchGetImage`
- `ecr:GetDownloadUrlForLayer`

No long-lived AWS access key is stored in the EC2 instance, Dockerfile, source code, or Bash script.

## 10. Terraform provisioners

The assignment explicitly requires `file` and `remote-exec` provisioners.

The App tier uses `remote-exec` to:

1. Install Docker and AWS CLI.
2. Wait until RDS is reachable.
3. Authenticate to ECR using the EC2 IAM role.
4. Pull the image.
5. Run the API container.

The Web tier uses a `file` provisioner to upload the frontend and NGINX configuration and `remote-exec` to install/configure NGINX.

The Web EC2 is used as an SSH bastion for the private App EC2. This is necessary because the App instance has no public IP.

## 11. Why provisioners are normally discouraged

Terraform is strongest when it describes infrastructure resources declaratively. A provisioner runs an external command or script and Terraform generally cannot model every side effect of that command as a first-class resource. If the command changes files, installs software, or pushes an artifact, Terraform does not automatically understand the full internal state of those changes.

Provisioners can also make retries, replacement behavior, credentials, and debugging harder. In production, immutable images, cloud-init/user data, configuration management, or dedicated deployment systems are normally preferable.

For this college assignment, provisioners are explicitly required, so they are appropriate as a demonstration mechanism. The image-build `local-exec` is also justified here because the assignment specifically asks for the image-build step to be discussed in relation to `local-exec`.

## 12. Question 1 — What happens if the return route in data-vpc is forgotten?

Suppose App VPC has:

```text
10.30.0.0/16 -> App/Data peering
```

but Data VPC does not have:

```text
10.20.0.0/16 -> App/Data peering
```

The App EC2 can send a packet toward the RDS address because its route table knows that the Data CIDR is reachable through the peering connection. However, the response from RDS has no matching route back to the App CIDR in the Data VPC route table.

The result is a failed TCP connection or a connection that times out. The forward direction exists but the return direction is broken.

A useful demonstration is to temporarily remove the Data route and test from App EC2:

```bash
nc -vz <rds-private-hostname> 5432
```

Then restore the route and repeat the test. The exact failure can depend on the client timeout, but the important concept is that VPC peering does not automatically create both-side routing.

## 13. Question 2 — Why does the DB subnet need no NAT Gateway?

A NAT Gateway is used when a private resource needs to initiate connections toward the public Internet.

RDS does not need to initiate an Internet connection for this application. The required connection is:

```text
App EC2 -> RDS
```

That is private VPC-to-VPC traffic through VPC peering. The Data VPC route table knows how to return traffic to the App CIDR.

Therefore:

```text
reachable from another VPC != needs Internet egress
```

Adding NAT to the database tier would provide unnecessary Internet egress and increase cost and complexity.

## 14. Question 3 — Why does the DB subnet group span multiple AZs?

The RDS DB subnet group must contain subnets covering at least two Availability Zones. This is a subnet-group requirement and also prepares the database networking for Multi-AZ configurations.

NimbusCart uses two private DB subnets:

```text
AZ-a -> 10.30.1.0/24
AZ-b -> 10.30.2.0/24
```

The current database instance is configured as a single-AZ instance to keep the student deployment simple and cost-conscious. The subnet group still spans two AZs.

## 15. Question 4 — VPC Peering vs Transit Gateway

VPC Peering is direct one-to-one connectivity between VPCs. It is simple and works well for this assignment because there are only three VPCs and the traffic relationships are predictable.

Transit Gateway is a hub-and-spoke networking service. It becomes more attractive when an organization has many VPCs, multiple accounts, on-premises connectivity, centralized routing, or a need to avoid maintaining many individual peering relationships.

For NimbusCart, peering is simpler and directly demonstrates the assignment requirement. I would consider Transit Gateway when the number of VPCs and routing relationships becomes large enough that a mesh of individual peerings becomes difficult to operate.

## 16. Question 5 — How does private App EC2 pull from ECR?

The App EC2 has no public IP. Its private subnet has:

```text
0.0.0.0/0 -> NAT Gateway
```

The NAT Gateway is in a public subnet with a public Elastic IP and Internet Gateway path.

The sequence is:

```text
App EC2
  -> private route table
  -> NAT Gateway
  -> Internet Gateway
  -> ECR endpoint
```

The EC2 instance role provides ECR authorization. The provisioning command uses:

```bash
aws ecr get-login-password --region <region>
```

and pipes the temporary authorization token to Docker login. The instance then pulls the image.

No AWS access key is stored on the instance.

## 17. Question 6 — Security Groups vs NACLs

Security Groups are stateful. If an inbound connection is permitted by a Security Group, the response traffic is automatically permitted as part of the same connection.

NACLs are stateless. Return traffic must be explicitly permitted.

Concrete example: suppose the Data VPC NACL allows inbound TCP 5432 from the App subnet but the outbound NACL does not allow the ephemeral response ports. The initial PostgreSQL packet can reach RDS, but the response packet can be dropped by the stateless NACL. The connection then appears to hang or time out even though the Security Group rules are correct.

This is why a working SG configuration does not compensate for an incorrectly restrictive NACL.

## 18. Question 7 — Why is local-exec discouraged?

Terraform tracks the `null_resource` and its trigger values, but it does not understand the internal state of every external action performed by `local-exec`.

For example, after:

```bash
docker build ...
docker push ...
```

Terraform does not become a full registry/image-state manager. It mainly knows that the provisioner ran for that resource instance.

For this assignment the image build is an acceptable use because the assignment explicitly asks for provisioners and requires the Docker image to be built/pushed as part of the deployment workflow. In a production system, a CI/CD pipeline would usually build, scan, tag, and publish the image separately.

## 19. Question 8 — Why doesn't backend.tf live in the state it configures?

Terraform must initialize its backend before it can read or write the state associated with the configuration.

Therefore the backend's S3 bucket and DynamoDB lock table cannot be resources that depend on the same remote state being initialized. Otherwise Terraform would have a circular bootstrap problem:

```text
Need backend to initialize state
        |
        v
Need Terraform state to create backend
        |
        v
Circular dependency
```

For NimbusCart, the S3 bucket and DynamoDB table are one-time bootstrap resources created outside this project's state. After they exist, `terraform init` can use them for the NimbusCart state.

This is the smallest change necessary to satisfy both the remote-backend requirement and the assignment's strict three-command `script.sh` requirement. Terraform's S3 backend documentation likewise assumes the referenced bucket already exists. DynamoDB locking is retained here because the assignment explicitly requires it, although modern Terraform also supports S3 lockfiles and documents DynamoDB locking as deprecated.

## 20. Remote backend bootstrap

This is a one-time prerequisite, not a fourth command in `script.sh`.

Create a unique S3 bucket in `ap-south-1`, enable versioning, and create a DynamoDB table named `nimbuscart-terraform-lock` with a String partition key named `LockID`.

Example AWS CLI commands, run once before the first deployment:

```bash
aws s3api create-bucket \
  --bucket YOUR-UNIQUE-NIMBUSCART-STATE-BUCKET \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning \
  --bucket YOUR-UNIQUE-NIMBUSCART-STATE-BUCKET \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name nimbuscart-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

Then replace the placeholder bucket name in `terraform/backend.tf`.

Do not put these commands into `script.sh`, because the PDF explicitly requires that `script.sh` run only `terraform init`, `terraform plan`, and `terraform apply -auto-approve`.

## 21. Local testing

### Start PostgreSQL

```bash
docker run --name nimbuscart-postgres \
  -e POSTGRES_DB=nimbuscart \
  -e POSTGRES_USER=nimbusadmin \
  -e POSTGRES_PASSWORD=LocalDevPassword123! \
  -p 5432:5432 \
  -d postgres:16
```

### Test the API without a database

The `/health` route does not require DB connectivity. Run the Flask application with the DB unavailable and verify:

```bash
curl http://localhost:5000/health
```

Expected:

```json
{"status":"ok"}
```

### Run the API locally

```bash
cd app/api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=nimbuscart
export DB_USER=nimbusadmin
export DB_PASSWORD='LocalDevPassword123!'
python app.py
```

### Test GET

```bash
curl http://localhost:5000/items
```

A fresh database should return:

```json
[]
```

### Test POST

```bash
curl -X POST http://localhost:5000/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"Laptop","price":55000,"stock":10}'
```

Then:

```bash
curl http://localhost:5000/items
```

### Build the Docker image locally

```bash
cd app/api
docker build -t nimbuscart-api:local .
```

### Run the API container locally

```bash
docker run --rm -p 5000:5000 \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e DB_NAME=nimbuscart \
  -e DB_USER=nimbusadmin \
  -e DB_PASSWORD='LocalDevPassword123!' \
  nimbuscart-api:local
```

On Linux, if `host.docker.internal` is unavailable, add:

```bash
--add-host=host.docker.internal:host-gateway
```

### Frontend local testing

The frontend automatically uses `http://localhost:5000/items` when it is opened from `localhost` and uses `/api/items` when deployed. This keeps the deployed version same-origin while allowing a simple local test.

In another terminal, from `app/frontend`, run:

```bash
python3 -m http.server 8000
```

Open:

```text
http://localhost:8000
```

The local page will call the local Flask API. The Flask application permits the localhost development origin for this test. In AWS, NGINX provides the `/api/` reverse proxy and the browser uses the same-origin `/api/items` path.

## 22. Deployment

1. Install and configure AWS CLI.
2. Install Terraform and Docker on the machine running Terraform.
3. Create the EC2 key pair in AWS.
4. Ensure the private key is available locally.
5. Determine the machine's public IPv4 address and set `admin_cidr` to `<your-ip>/32`.
6. Create the remote backend resources once as described above.
7. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in values.
8. Replace the backend bucket placeholder in `terraform/backend.tf`.
9. From the project root run:

```bash
chmod +x script.sh
./script.sh
```

The script contains only the three required Terraform operations.

## 23. Important deployment prerequisites

The local machine running Terraform must have:

- AWS CLI authenticated with permission to create the required AWS resources.
- Docker running because Terraform's `local-exec` builds and pushes the API image.
- Terraform installed.
- The private SSH key corresponding to the EC2 key pair.
- Network access to the Web EC2 SSH port from the configured administrator CIDR.

## 24. Required Terraform outputs

After deployment:

```bash
cd terraform
terraform output
```

Expected outputs include:

```text
web_public_ip
app_private_ip
 db_endpoint
peering_connection_id
nat_gateway_public_ip
frontend_url
```

Open the value of `frontend_url` in a browser.

## 25. End-to-end validation

### Web

```bash
curl http://<web_public_ip>/
```

### Health through NGINX

```bash
curl http://<web_public_ip>/api/health
```

### GET products

```bash
curl http://<web_public_ip>/api/items
```

### POST product

```bash
curl -X POST http://<web_public_ip>/api/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"Keyboard","price":1200,"stock":25}'
```

### Verify the new product

```bash
curl http://<web_public_ip>/api/items
```

The product added by POST must appear in the GET response and in the browser table.

## 26. Browser acceptance test

1. Open `frontend_url`.
2. Confirm products load from RDS through the API.
3. Enter a product name, price, and stock.
4. Click **Add Product**.
5. Confirm a success message appears.
6. Confirm the table refreshes automatically.
7. Confirm the newly inserted product is visible.
8. Refresh the browser and confirm the product remains, proving it was stored in RDS rather than localStorage.

## 27. Cleanup

After the demonstration:

```bash
cd terraform
terraform destroy
```

The assignment's `script.sh` is intentionally limited to the required deployment commands, so cleanup is a separate Terraform lifecycle operation.

Because the RDS configuration uses `skip_final_snapshot = true`, destroying the infrastructure will not retain a final database snapshot. Change that setting if the data must be retained.

## 28. Assumptions

- The deployment uses `ap-south-1` by default.
- Two Availability Zones are available in the selected region.
- The user supplies an existing EC2 key pair and its private key locally.
- The user's SSH source CIDR is supplied as `admin_cidr`.
- The Terraform runner has Docker and AWS CLI installed.
- The remote S3 bucket and DynamoDB lock table are bootstrapped once outside this Terraform state because backend initialization necessarily occurs before the state can be used.
- The RDS instance is Single-AZ for cost and assignment simplicity, while its subnet group spans two AZs.

## 29. Important production caveats

This implementation intentionally follows the college assignment's EC2 + provisioner design. A production implementation would normally use immutable machine images or cloud-init/configuration management instead of SSH provisioners, a CI/CD pipeline for container builds, stronger secret management such as AWS Secrets Manager, private ECR connectivity through VPC endpoints where appropriate, HTTPS with a proper certificate, and a more resilient database deployment.
