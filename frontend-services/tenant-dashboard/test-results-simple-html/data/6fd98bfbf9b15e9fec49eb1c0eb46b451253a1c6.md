# Page snapshot

```yaml
- heading "Welcome back" [level=3]
- paragraph: Sign in to your PyAirtable account
- button "Google":
  - img
  - text: Google
- button "GitHub":
  - img
  - text: GitHub
- text: Or continue with email
- img
- textbox "Enter your email"
- paragraph: Please enter a valid email address
- img
- textbox "Enter your password"
- paragraph: Password must be at least 8 characters
- button "Sign In"
- link "Forgot your password?":
  - /url: /auth/forgot-password
- text: Don't have an account?
- link "Sign up":
  - /url: /auth/register
- alert
```