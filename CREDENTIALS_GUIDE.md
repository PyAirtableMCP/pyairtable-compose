# PyAirtable Secure Credentials Management Guide

## Overview

This guide provides secure credential management practices for the PyAirtable project, ensuring no sensitive information is exposed in version control while maintaining automated deployment capabilities through GitHub Actions.

## Security Principles

1. **Never commit actual credentials** to version control
2. **Use environment variables** with secure fallback patterns
3. **Leverage GitHub Secrets** for automated deployments
4. **Generate strong credentials** using cryptographically secure methods
5. **Follow principle of least privilege** for access control

## Required Credentials

### Core API Keys & Tokens

| Environment Variable | Description | How to Obtain | GitHub Secret Name |
|---------------------|-------------|---------------|-------------------|
| `PYAIRTABLE_API_KEY` | Internal service-to-service API key | Generate using: `python -c "import secrets; print(secrets.token_urlsafe(48))"` | `PYAIRTABLE_API_KEY` |
| `AIRTABLE_TOKEN` | Airtable Personal Access Token | [Airtable API Authentication](https://airtable.com/developers/web/api/authentication) | `AIRTABLE_TOKEN` |
| `AIRTABLE_BASE` | Airtable Base ID | From [Airtable API docs](https://airtable.com/api) (format: appXXXXXXXXXXXXXX) | `AIRTABLE_BASE` |
| `GEMINI_API_KEY` | Google Gemini API Key | [Google AI Platform](https://cloud.google.com/ai-platform/generative-ai/docs/api-key) | `GEMINI_API_KEY` |

### Security Secrets

| Environment Variable | Description | How to Generate | GitHub Secret Name |
|---------------------|-------------|-----------------|-------------------|
| `JWT_SECRET` | JWT token signing secret | `python -c "import secrets; print(secrets.token_urlsafe(64))"` | `JWT_SECRET` |
| `NEXTAUTH_SECRET` | NextAuth.js session secret | `python -c "import secrets; print(secrets.token_urlsafe(64))"` | `NEXTAUTH_SECRET` |

### Database Credentials

| Environment Variable | Description | Security Requirements | GitHub Secret Name |
|---------------------|-------------|----------------------|-------------------|
| `POSTGRES_PASSWORD` | PostgreSQL database password | Min 16 chars, alphanumeric + symbols | `POSTGRES_PASSWORD` |
| `REDIS_PASSWORD` | Redis cache password | Min 16 chars, alphanumeric + symbols | `REDIS_PASSWORD` |

## Setting Up GitHub Secrets

### Repository Secrets (Recommended)

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each credential with the exact name from the "GitHub Secret Name" column above

### Environment Secrets (For Production)

For production deployments, use environment-specific secrets:

1. Go to **Settings** → **Environments**
2. Create or select your environment (e.g., "production")
3. Add environment-specific secrets with the same names

## Automated Credential Generation Script

Create strong credentials automatically:

```bash
#!/bin/bash
# Generate secure credentials for PyAirtable

echo "=== PyAirtable Secure Credential Generator ==="
echo

echo "Internal API Key (48-character URL-safe):"
python -c "import secrets; print('PYAIRTABLE_API_KEY=' + secrets.token_urlsafe(48))"
echo

echo "JWT Secret (64-character URL-safe):"
python -c "import secrets; print('JWT_SECRET=' + secrets.token_urlsafe(64))"
echo

echo "NextAuth Secret (64-character URL-safe):"
python -c "import secrets; print('NEXTAUTH_SECRET=' + secrets.token_urlsafe(64))"
echo

echo "PostgreSQL Password (32-character alphanumeric):"
python -c "import secrets, string; chars = string.ascii_letters + string.digits; print('POSTGRES_PASSWORD=' + ''.join(secrets.choice(chars) for _ in range(32)))"
echo

echo "Redis Password (32-character alphanumeric):"
python -c "import secrets, string; chars = string.ascii_letters + string.digits; print('REDIS_PASSWORD=' + ''.join(secrets.choice(chars) for _ in range(32)))"
echo

echo "=== Manual Setup Required ==="
echo "1. Get Airtable Token from: https://airtable.com/developers/web/api/authentication"
echo "2. Get Airtable Base ID from: https://airtable.com/api"
echo "3. Get Gemini API Key from: https://cloud.google.com/ai-platform/generative-ai/docs/api-key"
```

## Local Development Setup

### Option 1: Using GitHub CLI (Recommended)

```bash
# Install GitHub CLI if not already installed
# macOS: brew install gh
# Other platforms: https://cli.github.com/

# Login to GitHub
gh auth login

# Set up credentials automatically from GitHub Secrets
./scripts/setup-local-credentials.sh
```

### Option 2: Manual Environment Setup

1. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Generate secure credentials:**
   ```bash
   # Run the credential generator
   python -c "
   import secrets
   print('# Generated secure credentials:')
   print(f'PYAIRTABLE_API_KEY={secrets.token_urlsafe(48)}')
   print(f'JWT_SECRET={secrets.token_urlsafe(64)}')
   print(f'NEXTAUTH_SECRET={secrets.token_urlsafe(64)}')
   print(f'POSTGRES_PASSWORD={secrets.token_urlsafe(32)}')
   print(f'REDIS_PASSWORD={secrets.token_urlsafe(32)}')
   "
   ```

3. **Obtain external API credentials:**
   - **Airtable Token**: Visit [Airtable API Authentication](https://airtable.com/developers/web/api/authentication)
   - **Airtable Base ID**: Get from [Airtable API docs](https://airtable.com/api)
   - **Gemini API Key**: Get from [Google AI Platform](https://cloud.google.com/ai-platform/generative-ai/docs/api-key)

4. **Update your .env file** with the actual values

## GitHub Actions Integration

The project is configured to automatically use GitHub Secrets in CI/CD pipelines. The `.env` file uses fallback patterns:

```bash
# Automatically uses GitHub Secret if available, otherwise shows secure placeholder
AIRTABLE_TOKEN=${AIRTABLE_TOKEN:-REPLACE_WITH_AIRTABLE_TOKEN_FROM_GITHUB_SECRETS}
```

### Workflow Integration

Add this to your GitHub Actions workflow:

```yaml
- name: Set up environment variables
  env:
    PYAIRTABLE_API_KEY: ${{ secrets.PYAIRTABLE_API_KEY }}
    AIRTABLE_TOKEN: ${{ secrets.AIRTABLE_TOKEN }}
    AIRTABLE_BASE: ${{ secrets.AIRTABLE_BASE }}
    GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
    JWT_SECRET: ${{ secrets.JWT_SECRET }}
    NEXTAUTH_SECRET: ${{ secrets.NEXTAUTH_SECRET }}
    POSTGRES_PASSWORD: ${{ secrets.POSTGRES_PASSWORD }}
    REDIS_PASSWORD: ${{ secrets.REDIS_PASSWORD }}
  run: |
    # Your deployment commands here
    docker-compose up -d
```

## Security Best Practices

### Credential Rotation

- **Rotate secrets quarterly** or immediately if compromised
- **Use different credentials** for each environment (dev/staging/prod)
- **Monitor credential usage** through API logs

### Access Control

- **Limit GitHub repository access** to authorized team members only
- **Use environment-specific secrets** for production deployments
- **Enable branch protection rules** to prevent unauthorized changes

### Monitoring & Auditing

- **Enable GitHub audit logs** for secret access tracking
- **Monitor failed authentication attempts** in application logs
- **Set up alerts** for credential-related security events

## Troubleshooting

### Common Issues

1. **"Missing credential" errors**
   - Verify GitHub Secret names match exactly
   - Check environment variable spelling in `.env`
   - Ensure secrets are set at the repository level

2. **Authentication failures**
   - Verify credential format and validity
   - Check API key permissions and quotas
   - Ensure credentials haven't expired

3. **Local development issues**
   - Confirm `.env` file exists and has correct values
   - Verify Python can generate secure tokens
   - Check file permissions on `.env` (should be 600)

### Getting Help

1. **Check the project's security documentation**
2. **Review GitHub Actions logs** for specific error messages
3. **Verify credential format** against API documentation
4. **Test credentials manually** using API calls

## Compliance & Audit

### Security Checklist

- [ ] No credentials committed to version control
- [ ] All production secrets use strong, generated values
- [ ] GitHub Secrets configured for all required credentials
- [ ] Environment-specific secrets for production
- [ ] Regular credential rotation schedule established
- [ ] Access logs monitored for suspicious activity
- [ ] Team trained on secure credential practices

### Audit Trail

- **GitHub audit logs** track secret access and modifications
- **Application logs** record authentication events
- **Infrastructure logs** monitor credential usage patterns

## Emergency Procedures

### Credential Compromise Response

1. **Immediately revoke** compromised credentials
2. **Generate new credentials** using secure methods
3. **Update GitHub Secrets** with new values
4. **Redeploy services** to use new credentials
5. **Monitor logs** for unauthorized access attempts
6. **Document incident** for future reference

### Contact Information

- **Security Team**: security@yourorganization.com
- **DevOps Team**: devops@yourorganization.com
- **Emergency Contact**: +1-XXX-XXX-XXXX

---

**Last Updated**: August 1, 2025
**Version**: 1.0.0
**Maintained By**: PyAirtable Security Team