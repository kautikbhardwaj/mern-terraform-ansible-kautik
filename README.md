# Deploying the TravelMemory MERN Application on AWS with Terraform and Ansible

Infrastructure as Code (Terraform) + configuration management (Ansible) for the
[TravelMemory](https://github.com/UnpredictablePrashant/TravelMemory) MERN stack.

---

## 1. Architecture

```
                          Internet
                              |
                     [ Internet Gateway ]
                              |
        VPC 10.0.0.0/16 ------+------------------------------------
        |                                                          |
        |  PUBLIC SUBNET 10.0.1.0/24        PRIVATE SUBNET 10.0.2.0/24
        |  +-----------------------+        +-----------------------+
        |  |  EC2: travelmemory-web|        |  EC2: travelmemory-db |
        |  |  Elastic IP           |        |  no public IP         |
        |  |  Nginx :80            |        |  MongoDB :27017       |
        |  |   |-> React build/    |        |  auth enabled         |
        |  |   |-> /api -> :3000   |        |  bindIp 127.0.0.1,    |
        |  |  Express (PM2) :3000  |------->|            10.0.2.x   |
        |  |  SG: 22 from MY_IP,   |  27017 |  SG: 22 + 27017 from  |
        |  |      80/443 from web  |        |      web SG only      |
        |  +-----------------------+        +-----------------------+
        |             |                                 |
        |     public route table                  private route table
        |     0.0.0.0/0 -> IGW                    0.0.0.0/0 -> NAT GW
        |                                                 ^
        +--------------- [ NAT Gateway + EIP ] -----------+
                          (in public subnet)
```

**Request path:** Browser → Elastic IP :80 → Nginx → `/` serves the compiled React
bundle, `/api/*` is reverse-proxied to Express on `127.0.0.1:3000` → Express opens an
authenticated connection to MongoDB on the private instance at `10.0.2.x:27017` →
response travels back the same way.

**Why this shape**
- The database has no public IP and no route to the Internet Gateway; its only inbound
  rules reference the web server's security group, so nothing outside the VPC can reach it.
- The database still needs outbound access (apt, MongoDB repo, pip) — that is what the
  NAT Gateway in the public subnet provides.
- The web server doubles as the SSH bastion. Ansible reaches the private host through it
  with an SSH `ProxyCommand`, so no jump box or public IP on the database is required.
- The frontend calls `/api` on its own origin rather than a hard-coded IP, which removes
  CORS problems and makes the build independent of the Elastic IP.

---

## 2. Repository layout

```
.
├── terraform/
│   ├── versions.tf              provider + required versions
│   ├── variables.tf             all input variables
│   ├── vpc.tf                   VPC, subnets, IGW, NAT GW, route tables
│   ├── security_groups.tf       web SG and db SG (SG-to-SG references)
│   ├── iam.tf                   EC2 role, SSM/CloudWatch policies, instance profile
│   ├── ec2.tf                   AMI lookup, key pair, both instances, Elastic IP
│   ├── outputs.tf               public IP, private IPs, ready-made inventory
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml         collections: community.general, community.mongodb, ansible.posix
│   ├── site.yml                 full provisioning run
│   ├── deploy.yml               application-only redeploy
│   ├── group_vars/all.yml       app, Node, MongoDB and credential variables
│   ├── inventory/hosts.ini.example
│   └── roles/
│       ├── common/              patching, base packages, timezone, hostname
│       ├── mongodb/             repo, install, mongod.conf, users, auth, UFW rule
│       ├── webserver/           Node.js 20 (NodeSource), NPM, PM2, Nginx
│       ├── app/                 clone, .env, npm install, React build, PM2, Nginx vhost
│       └── hardening/           UFW, sshd hardening, fail2ban, unattended-upgrades
├── generate-inventory.sh        builds hosts.ini from terraform outputs
├── Makefile                     init / apply / inventory / configure / destroy
└── docs/screenshots/            evidence of the working application
```

---

## 3. Prerequisites

| Tool | Version used |
|---|---|
| Terraform | >= 1.5 |
| AWS CLI | v2 |
| Ansible | >= 2.15 |
| Python | 3.10+ |

```bash
aws configure                      # access key, secret, region, output format
aws sts get-caller-identity        # confirms authentication

ssh-keygen -t ed25519 -f ~/.ssh/travelmemory -N ""
```

---

## 4. Part 1 — Infrastructure with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# restrict SSH to your own address
echo "my_ip_cidr = \"$(curl -s https://checkip.amazonaws.com)/32\"" >> terraform.tfvars

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

What gets created:

| # | Requirement | Resources |
|---|---|---|
| 1 | AWS CLI + Terraform init | `versions.tf`, provider `aws ~> 5.0` |
| 2 | VPC, two subnets, IGW, NAT, route tables | `aws_vpc`, `aws_subnet.public`, `aws_subnet.private`, `aws_internet_gateway`, `aws_eip.nat` + `aws_nat_gateway`, `aws_route_table.public/private` + associations |
| 3 | Two EC2 instances, SSH reachable | `aws_instance.web` (public subnet, Elastic IP), `aws_instance.db` (private subnet, reached over SSH via the bastion) |
| 4 | Security groups + IAM roles | `aws_security_group.web` (22 from `my_ip_cidr`, 80/443 public), `aws_security_group.db` (22 and 27017 **from the web SG only**), `aws_iam_role` + `aws_iam_instance_profile` with `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy` and a read-only EC2 describe policy |
| 5 | Output the web server public IP | `output "web_public_ip"`, plus `application_url` and a generated `ansible_inventory` |

Terraform output:

```
Outputs:
application_url  = "http://<WEB_PUBLIC_IP>"
db_private_ip    = "10.0.2.x"
web_private_ip   = "10.0.1.x"
web_public_ip    = "<WEB_PUBLIC_IP>"
```

Hardening details worth noting: root volumes are encrypted, IMDSv2 is enforced
(`http_tokens = required`), and the AMI is resolved dynamically from Canonical's
owner ID rather than pinned to a stale ID.

---

## 5. Part 2 — Configuration and deployment with Ansible

```bash
cd ..
./generate-inventory.sh                                 # writes ansible/inventory/hosts.ini
ansible-galaxy collection install -r ansible/requirements.yml

cd ansible
ansible all -m ping                                     # connectivity check
ansible-playbook site.yml
```

Set real credentials instead of the placeholders in `group_vars/all.yml`:

```bash
ansible-vault encrypt_string 'StrongAdminPass' --name 'mongodb_admin_password'
ansible-vault encrypt_string 'StrongAppPass'   --name 'mongodb_app_password'
# or, for a quick run:
ansible-playbook site.yml -e mongodb_admin_password='...' -e mongodb_app_password='...'
```

### 5.1 Ansible configuration
`ansible.cfg` disables host key checking for ephemeral instances, enables pipelining,
and points at `inventory/hosts.ini`. The `[db]` group carries an
`ansible_ssh_common_args` `ProxyCommand` that tunnels through the web server, which is
how a host with no public IP is managed.

### 5.2 Web server setup — `webserver` role
Adds the NodeSource keyring and repository, installs **Node.js 20 + NPM**, installs
**PM2** globally, installs and enables **Nginx**, and prints the resolved `node`/`npm`
versions.

### 5.3 Database server setup — `mongodb` role
Adds MongoDB's signed repository and installs `mongodb-org` 7.0. `mongod.conf` is
templated so that `bindIp` is `127.0.0.1` plus the private IP only — never `0.0.0.0`.
User provisioning is a deterministic two-phase operation guarded by a marker file:

1. First run: config rendered with `authorization: disabled`, mongod restarted,
   `mongoadmin` (admin roles) and `tmapp` (`readWrite` on `travelmemory`) created,
   marker written.
2. Every run: config re-rendered with `authorization: enabled`, mongod restarted,
   then an authenticated `mongodb_info` call verifies access.

A UFW rule permits port 27017 only from the web server's private IP, layered on top of
the security group.

### 5.4 Application deployment — `app` role
Clones the repository to `/opt/travelmemory`, then:

- **Backend** — renders `backend/.env` (mode `0600`) containing `MONGO_URI` and `PORT`,
  runs `npm install`, and starts `index.js` under PM2 via a templated
  `ecosystem.config.js`. `pm2 startup systemd` + `pm2 save` make it survive reboots.
- **Frontend** — overwrites `frontend/src/url.js` so `baseUrl` is `/api`, runs
  `npm install` and `npm run build` to produce a static bundle.
- **Nginx** — a templated vhost serves `frontend/build` with SPA fallback
  (`try_files ... /index.html`) and proxies `location /api/` to
  `http://127.0.0.1:3000/`, forwarding `Host`, `X-Real-IP` and `X-Forwarded-For`.
- **Verification** — `nginx -t`, then `uri` checks against `/` and `/api/hello` before
  printing a deployment summary.

### 5.5 Security hardening — `hardening` role
- UFW default deny inbound / allow outbound; `limit` on 22; 80 and 443 on the web host;
  27017 restricted to the web private IP on the database host.
- `sshd_config`: `PermitRootLogin no`, `PasswordAuthentication no` (including the
  cloud-init drop-in that normally overrides it), `PermitEmptyPasswords no`,
  `MaxAuthTries 3`, `X11Forwarding no`, idle timeouts. Every change is applied with
  `validate: sshd -t -f %s` so a bad edit can never lock you out.
- fail2ban `sshd` jail, and unattended security upgrades.
- Key-based authentication only, via the Terraform-managed `aws_key_pair`.

---

## 6. How the components interact

| Hop | From | To | Protocol / port | Controlled by |
|---|---|---|---|---|
| 1 | Browser | Nginx on web EC2 | HTTP 80 | web SG (`allow_http_from`), UFW |
| 2 | Nginx `/` | React build on disk | filesystem | Nginx `root` + `try_files` |
| 3 | Nginx `/api/` | Express (PM2) | HTTP 127.0.0.1:3000 | loopback only — never exposed |
| 4 | Express | MongoDB | TCP 10.0.2.x:27017 | db SG references web SG; UFW src rule; SCRAM auth |
| 5 | Admin laptop | web EC2 | SSH 22 | web SG limited to `my_ip_cidr` |
| 6 | Ansible | db EC2 | SSH 22 via ProxyCommand | db SG allows 22 only from web SG |
| 7 | db EC2 | Internet (apt/pip) | outbound 443 | NAT Gateway, private route table |

Express is deliberately bound behind Nginx rather than published on port 3000, so the
only externally reachable ports on the whole stack are 22 (your IP) and 80/443.

---

## 7. Verification

```bash
# Terraform
terraform -chdir=terraform output

# Application
curl -I http://$(terraform -chdir=terraform output -raw web_public_ip)/
curl    http://$(terraform -chdir=terraform output -raw web_public_ip)/api/hello

# Services
ssh -i ~/.ssh/travelmemory ubuntu@<WEB_PUBLIC_IP> 'pm2 status && sudo systemctl status nginx --no-pager'
ssh -i ~/.ssh/travelmemory -J ubuntu@<WEB_PUBLIC_IP> ubuntu@<DB_PRIVATE_IP> \
    'sudo systemctl status mongod --no-pager && sudo ufw status verbose'

# Database contents after adding a trip in the UI
mongosh "mongodb://tmapp:<pass>@<DB_PRIVATE_IP>:27017/travelmemory?authSource=travelmemory" \
  --eval 'db.trips.countDocuments()'

# Negative test — must time out
nc -vz <DB_PRIVATE_IP> 27017
```

Screenshots to capture in `docs/screenshots/`:
`terraform-apply.png`, `aws-vpc-resource-map.png`, `ec2-instances.png`,
`security-groups.png`, `ansible-playbook-recap.png`, `pm2-status.png`,
`mongod-status.png`, `app-homepage.png`, `app-add-trip.png`, `mongosh-documents.png`.

---

## 8. Troubleshooting notes

| Symptom | Cause | Fix |
|---|---|---|
| `ERR_OSSL_EVP_UNSUPPORTED` during `npm run build` | CRA 4 with OpenSSL 3 on Node 18+ | already handled — `NODE_OPTIONS=--openssl-legacy-provider` is set in the role |
| Frontend loads, API returns 502 | Express not running | `pm2 logs travelmemory-backend` |
| `MongoServerError: Authentication failed` | credentials changed after the marker file was written | delete `/etc/mongodb-users-provisioned` on the db host and rerun |
| Ansible cannot reach `[db]` | ProxyCommand key path wrong | rerun `SSH_KEY_PATH=~/.ssh/travelmemory ./generate-inventory.sh` |
| `npm run build` OOM on t3.micro | 1 GB RAM | add swap or use `t3.small` |

---

## 9. Teardown

```bash
terraform -chdir=terraform destroy
```

The NAT Gateway and both Elastic IPs are the only chargeable idle resources — destroy
when finished.
