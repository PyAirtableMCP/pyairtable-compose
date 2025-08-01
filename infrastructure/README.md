# PyAirtable Infrastructure - Practical Production Setup

This infrastructure is designed for a **2-person team** to deploy and maintain PyAirtable microservices with production-ready practices without over-engineering.

## What We Built

### ✅ **Modular but Simple**
- **Modules**: VPC, Security, RDS, etc. - reusable and maintainable
- **Single main file**: `simplified-main.tf` - uses modules but keeps configuration straightforward
- **Environment-specific**: `dev.tfvars` and `prod.tfvars` - clear separation without complexity

### ✅ **Production-Ready Basics**
- **Security**: WAF, security groups, encryption at rest, KMS
- **High Availability**: Multi-AZ RDS in prod, multiple subnets
- **Monitoring**: CloudWatch alarms, basic dashboards
- **Secrets Management**: SSM Parameter Store for API keys
- **Cost Optimization**: Spot instances in dev, right-sized resources

### ✅ **Maintainable Operations**
- **Simple Makefile**: `make apply ENV=dev` - that's it
- **Integrated CI/CD**: In your main repo, not separate
- **Clear Documentation**: Step-by-step deployment guide
- **Easy Troubleshooting**: Clear logs and health checks

## Quick Start (5 minutes to production)

```bash
# 1. One-time setup
make setup

# 2. Deploy dev environment
make apply ENV=dev

# 3. Deploy your services
make deploy-service SERVICE=api-gateway ENV=dev

# 4. Check health
make health ENV=dev
```

## File Structure

```
infrastructure/
├── terraform/
│   ├── simplified-main.tf          # Main infrastructure (uses modules)
│   ├── variables.tf                # Simple variable definitions
│   ├── outputs.tf                  # What you need to know
│   ├── environments/
│   │   ├── dev.tfvars             # Dev configuration
│   │   └── prod.tfvars            # Prod configuration
│   └── modules/                   # Reusable components
│       ├── vpc/                   # Network setup
│       ├── security/              # Security groups, WAF, KMS
│       ├── rds/                   # Database with backups
│       └── [other modules...]
├── Makefile.simple                # Simple operations
├── DEPLOYMENT_GUIDE.md           # Step-by-step guide
└── README.md                     # This file
```

## Key Decisions Made for Your Team

### 🎯 **Focused on Getting Things Done**
- **2 environments only**: dev and prod (no staging complexity)
- **Essential monitoring**: CloudWatch basics, email alerts
- **Practical security**: Industry standards without over-engineering
- **Cost conscious**: Spot instances in dev, right-sizing

### 🛠 **Operational Simplicity**
- **One command deployment**: `make apply ENV=prod`
- **Integrated CI/CD**: Lives in your main repo
- **Clear troubleshooting**: `make logs SERVICE=api-gateway`
- **Easy scaling**: `make scale-service SERVICE=api-gateway REPLICAS=3`

### 🔒 **Production Security**
- **Network isolation**: Private subnets, security groups
- **Encryption everywhere**: RDS, Redis, logs, secrets
- **WAF protection**: Rate limiting, common attack patterns
- **Secrets management**: SSM Parameter Store

## What This Gives You

### ✅ **For Development**
- Cheap to run (~$50-100/month)
- Fast deployments
- Easy to reset/recreate
- Full feature parity with prod

### ✅ **For Production**
- High availability (Multi-AZ)
- Automated backups
- Security hardening
- Monitoring and alerting
- Scalable architecture

### ✅ **For Your Team**
- Simple to operate
- Clear documentation
- Easy troubleshooting
- Maintainable codebase
- Room to grow

## Common Operations

```bash
# Deploy infrastructure
make apply ENV=dev
make apply ENV=prod

# Deploy a service
make deploy-service SERVICE=api-gateway ENV=dev

# Check status
make status ENV=dev
make health ENV=dev

# View logs
make logs SERVICE=api-gateway ENV=dev

# Scale services
make scale-service SERVICE=api-gateway REPLICAS=2 ENV=prod

# Database operations
make db-backup ENV=prod
make db-connect ENV=dev
```

## Migration from Current Setup

If you have existing infrastructure, here's how to migrate:

1. **Deploy new infrastructure** alongside existing
2. **Test thoroughly** in dev environment
3. **Migrate data** using standard database tools
4. **Switch DNS** to new load balancer
5. **Decomission old** infrastructure

## Cost Expectations

### Development (~$50-80/month)
- ECS Fargate Spot: ~$20
- RDS t3.micro: ~$15
- Redis t3.micro: ~$10
- ALB: ~$15
- NAT Gateway: ~$15
- Misc (CloudWatch, etc): ~$10

### Production (~$200-400/month)
- ECS Fargate: ~$100-200
- RDS t3.small Multi-AZ: ~$40
- Redis t3.small: ~$20
- ALB: ~$20
- NAT Gateways (2): ~$30
- Backups, monitoring: ~$20

## Next Steps

1. **Review** the configuration files
2. **Customize** the `prod.tfvars` with your domains/certificates
3. **Deploy** development environment
4. **Test** with your applications
5. **Deploy** production when ready

## Support

- **Documentation**: See `DEPLOYMENT_GUIDE.md` for detailed steps
- **Troubleshooting**: Check CloudWatch logs first
- **Operations**: Use the Makefile for common tasks
- **Monitoring**: CloudWatch dashboards and email alerts

This setup gives you **enterprise-grade infrastructure** with **startup-level operational simplicity**. Perfect for a focused 2-person team building great products.