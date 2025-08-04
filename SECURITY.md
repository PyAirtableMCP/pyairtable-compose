# Security Policy

## Supported Versions

We actively support and provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security vulnerability in PyAirtable Compose, please report it to us as described below.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: security@pyairtable.com

Include the following information in your report:
- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

### Response Timeline

- **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 24 hours.
- **Initial Assessment**: We will provide an initial assessment within 72 hours.
- **Regular Updates**: We will provide regular updates on our progress at least every 7 days.
- **Resolution**: We aim to resolve critical vulnerabilities within 30 days.

### Disclosure Policy

- We follow responsible disclosure practices
- We will coordinate with you on the timing of public disclosure
- We will credit you in our security advisory unless you prefer to remain anonymous

## Security Measures

### Current Security Controls

- **Authentication & Authorization**: JWT-based authentication with role-based access control
- **Database Security**: SSL/TLS encryption for all database connections
- **Container Security**: Automated vulnerability scanning with Trivy
- **Dependency Management**: Automated security updates via Dependabot
- **Code Analysis**: Static security analysis with CodeQL and Gosec
- **Secret Management**: Secrets scanning to prevent credential leaks
- **Network Security**: HTTPS/TLS encryption for all API communications

### Security Headers

All services implement the following security headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `Content-Security-Policy: default-src 'self'`

### Security Best Practices

- All passwords are hashed using bcrypt with a minimum cost of 12
- API keys use constant-time comparison to prevent timing attacks
- JWT tokens use only HS256 algorithm with explicit validation
- Database connections require SSL mode
- Container images run as non-root users
- Regular security scans are performed on all dependencies

## Security Contacts

- Security Team: security@pyairtable.com
- GPG Key: [Link to public key if available]

## Hall of Fame

We acknowledge security researchers who have responsibly disclosed vulnerabilities:

[List will be maintained here]

---

Last updated: August 2, 2025
EOF < /dev/null