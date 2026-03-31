# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in Buffer, please **do not** open a public GitHub issue.

Instead, report it privately by emailing the maintainer or using GitHub's private vulnerability reporting:

1. Go to the **Security** tab of this repository
2. Click **"Report a vulnerability"**
3. Fill in the details

### What to include

- A clear description of the vulnerability
- Steps to reproduce it
- Potential impact
- Any suggested fix (optional)

### Response timeline

- **Acknowledgement**: Within 48 hours
- **Status update**: Within 7 days
- **Fix / patch**: As soon as reasonably possible, depending on severity

## Scope

Buffer is a local-only macOS clipboard manager. It does **not** transmit any data over the network. All clipboard data is stored in `~/Library/Application Support/Buffer/` on your device.

Security concerns most relevant to this project:

- Local privilege escalation
- Unauthorized access to clipboard data stored on disk
- Vulnerabilities in the accessibility/hotkey permission flow

## Disclosure Policy

We follow responsible disclosure. Once a fix is released, we will publicly acknowledge the report (with your permission).
