# PyAirtable Security Guidelines

## 🔒 CRITICAL: Credential Management

### ❌ NEVER COMMIT:
- Hardcoded passwords, API keys, or tokens
- Database credentials
- Service account keys
- TLS certificates and private keys
- SSH keys or other authentication materials

### ✅ ALWAYS USE:
- Environment variables via `.env` files
- HashiCorp Vault for production secrets
- AWS Secrets Manager or Parameter Store
- Kubernetes Secrets for K8s deployments

## 🛡️ Pre-Commit Security Checks

Our repository uses automated credential scanning:
- All commits are scanned for potential secrets
- Commits are blocked if credentials are detected
- Use `git commit --no-verify` ONLY in emergencies

## 📋 Security Checklist

Before committing code:
- [ ] No hardcoded credentials in any files
- [ ] Environment variables used for all secrets
- [ ] `.env` files are in `.gitignore`
- [ ] Production secrets stored in secure vaults
- [ ] Test credentials use `TEST_*` environment variables

## 🔧 Remediation Steps

If credentials are detected:
1. Remove hardcoded values from files
2. Add environment variables to `.env.template`
3. Update code to use `os.getenv()`
4. Verify `.gitignore` excludes sensitive files
5. Rotate any exposed credentials immediately

## 📊 Environment Variable Patterns

```bash
# Development
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=your_test_password

# Database
POSTGRES_PASSWORD=your_secure_postgres_password
REDIS_PASSWORD=your_secure_redis_password

# Monitoring
GF_SECURITY_ADMIN_PASSWORD=your_grafana_password
```

## 🚨 Emergency Response

If credentials are accidentally committed:
1. Rotate compromised credentials immediately
2. Review commit history for exposure
3. Consider repository history cleanup if needed
4. Update security training materials

## 📞 Security Contacts

- DevOps Team: Immediate credential rotation
- Security Team: Incident response
- Infrastructure Team: Vault and secrets management

**Remember: Security is everyone's responsibility!**