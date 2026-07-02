# STRIDE Threat Model for Security Architecture

> _AI-generated engineering reference material. No project-specific or confidential content._

## Overview

STRIDE is a threat modeling framework developed by Microsoft that categorizes security threats into six classes. This document provides a systematic approach to identifying, analyzing, and mitigating security threats in software systems.

**STRIDE Acronym:**
- **S**poofing Identity
- **T**ampering with Data
- **R**epudiation
- **I**nformation Disclosure
- **D**enial of Service
- **E**levation of Privilege

**Usage:** Apply STRIDE during architecture reviews, security design sessions, and threat modeling workshops. For each component, data flow, or trust boundary, systematically evaluate all six threat categories.

---

## 1. Spoofing Identity

### Threat Description
Attacker pretends to be someone or something else to gain unauthorized access. Targets authentication mechanisms, identity verification, and credential management.

### Attack Vectors
- **Credential theft:** Stolen passwords, API keys, tokens, certificates
- **Session hijacking:** Cookie theft, session fixation, CSRF
- **Man-in-the-middle:** Intercepting authentication flows
- **Token replay:** Reusing captured authentication tokens
- **Impersonation:** Using stolen identities or weak identity proofing

### Mitigations by Layer

#### Network Layer
- Enforce TLS 1.3+ for all communications
- Implement mutual TLS (mTLS) for service-to-service auth
- Use certificate pinning for mobile/desktop clients
- Deploy HSTS headers to prevent protocol downgrade

#### Application Layer
- Multi-factor authentication (MFA) for sensitive operations
- Short-lived access tokens with refresh token rotation
- JWT signature verification with algorithm whitelisting
- Rate limiting on authentication endpoints
- Account lockout after failed attempts

#### Infrastructure Layer
- Network segmentation and microsegmentation
- Service mesh with identity-aware proxy (e.g., Istio, Linkerd)
- Secrets management systems (Vault, AWS Secrets Manager)
- Hardware security modules (HSM) for key storage

### Implementation Examples

#### Go: JWT Validation with Algorithm Whitelisting
```go
package auth

import (
    "errors"
    "fmt"
    "github.com/golang-jwt/jwt/v5"
    "time"
)

var (
    ErrInvalidToken     = errors.New("invalid token")
    ErrExpiredToken     = errors.New("token expired")
    ErrInvalidAlgorithm = errors.New("invalid signing algorithm")
)

type TokenValidator struct {
    secret            []byte
    allowedAlgorithms []string
    issuer            string
}

func NewTokenValidator(secret []byte, issuer string) *TokenValidator {
    return &TokenValidator{
        secret:            secret,
        allowedAlgorithms: []string{"HS256", "RS256"},
        issuer:            issuer,
    }
}

func (v *TokenValidator) Validate(tokenString string) (*jwt.RegisteredClaims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
        // Validate algorithm
        alg := token.Method.Alg()
        if !v.isAlgorithmAllowed(alg) {
            return nil, fmt.Errorf("%w: %s", ErrInvalidAlgorithm, alg)
        }
        return v.secret, nil
    })

    if err != nil {
        return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
    }

    claims, ok := token.Claims.(*jwt.RegisteredClaims)
    if !ok || !token.Valid {
        return nil, ErrInvalidToken
    }

    // Validate issuer
    if claims.Issuer != v.issuer {
        return nil, fmt.Errorf("%w: invalid issuer", ErrInvalidToken)
    }

    // Validate expiration
    if claims.ExpiresAt.Before(time.Now()) {
        return nil, ErrExpiredToken
    }

    return claims, nil
}

func (v *TokenValidator) isAlgorithmAllowed(alg string) bool {
    for _, allowed := range v.allowedAlgorithms {
        if alg == allowed {
            return true
        }
    }
    return false
}
```

#### TypeScript: Secure Session Management
```typescript
import { randomBytes, createHash } from 'crypto';
import { Request, Response, NextFunction } from 'express';

interface Session {
  userId: string;
  createdAt: number;
  expiresAt: number;
  fingerprint: string;
}

class SessionManager {
  private sessions = new Map<string, Session>();
  private readonly maxAge = 15 * 60 * 1000; // 15 minutes
  private readonly renewThreshold = 5 * 60 * 1000; // Renew if < 5 min left

  generateToken(): string {
    return randomBytes(32).toString('base64url');
  }

  createFingerprint(req: Request): string {
    const components = [
      req.headers['user-agent'] || '',
      req.ip || '',
      req.headers['accept-language'] || '',
    ].join('|');
    return createHash('sha256').update(components).digest('hex');
  }

  create(userId: string, req: Request): string {
    const token = this.generateToken();
    const now = Date.now();

    this.sessions.set(token, {
      userId,
      createdAt: now,
      expiresAt: now + this.maxAge,
      fingerprint: this.createFingerprint(req),
    });

    return token;
  }

  validate(token: string, req: Request): string | null {
    const session = this.sessions.get(token);

    if (!session) return null;
    if (Date.now() > session.expiresAt) {
      this.sessions.delete(token);
      return null;
    }

    // Validate fingerprint to detect session hijacking
    if (session.fingerprint !== this.createFingerprint(req)) {
      this.sessions.delete(token);
      return null;
    }

    // Rotate token if close to expiration
    if (session.expiresAt - Date.now() < this.renewThreshold) {
      this.sessions.delete(token);
      const newToken = this.create(session.userId, req);
      return newToken;
    }

    return token;
  }

  revoke(token: string): void {
    this.sessions.delete(token);
  }
}
```

### Detection Scripts

#### Detect Weak Authentication Patterns
```bash
#!/bin/bash
# detect-weak-auth.sh - Finds weak authentication implementations

echo "=== Scanning for Weak Authentication Patterns ==="

# Hardcoded credentials
echo -e "\n[1] Hardcoded Credentials:"
rg -i 'password\s*=\s*["\x27]' --type go --type ts --type py --type rust

# Weak JWT validation (missing algorithm check)
echo -e "\n[2] JWT without Algorithm Validation:"
rg 'jwt\.Parse\(' --type go -A 5 | rg -v 'SigningMethod'

# Missing token expiration checks
echo -e "\n[3] Missing Expiration Validation:"
rg 'ParseWithClaims' --type go -A 10 | rg -v 'ExpiresAt'

# Insecure session management
echo -e "\n[4] Insecure Session IDs:"
rg -i 'Math\.random\(\).*sessionId' --type ts --type js

# Missing MFA checks on sensitive operations
echo -e "\n[5] Sensitive Operations without MFA:"
rg -i '(delete|transfer|payment|admin).*handler' --type go -A 20 | rg -v 'mfa|2fa|otp'

echo -e "\n=== Scan Complete ==="
```

---

## 2. Tampering with Data

### Threat Description
Unauthorized modification of data in transit or at rest. Targets data integrity, message authentication, and input validation mechanisms.

### Attack Vectors
- **Message tampering:** Modifying API requests/responses
- **SQL injection:** Manipulating database queries
- **Command injection:** Injecting shell commands
- **Path traversal:** Accessing unauthorized files
- **Configuration tampering:** Modifying config files, environment variables

### Mitigations by Layer

#### Network Layer
- Use TLS with strong cipher suites
- Implement message authentication codes (HMAC)
- Digital signatures for critical messages
- Content Security Policy (CSP) headers

#### Application Layer
- Input validation and sanitization (whitelist approach)
- Parameterized queries (prepared statements)
- Output encoding for XSS prevention
- Integrity checks (checksums, hashes)
- Immutable data structures where possible

#### Infrastructure Layer
- File integrity monitoring (AIDE, Tripwire)
- Database audit logging
- Write-once storage for audit logs
- Code signing for deployments

### Implementation Examples

#### Python: SQL Injection Prevention
```python
from typing import List, Dict, Any
import sqlite3
from contextlib import contextmanager

class SecureDatabase:
    """Database wrapper with parameterized queries."""

    def __init__(self, db_path: str):
        self.db_path = db_path

    @contextmanager
    def get_connection(self):
        """Context manager for database connections."""
        conn = sqlite3.connect(self.db_path)
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def get_user_by_email(self, email: str) -> Dict[str, Any] | None:
        """
        Safe user lookup using parameterized query.

        VULNERABLE (DON'T DO THIS):
            cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")

        SECURE (DO THIS):
            cursor.execute("SELECT * FROM users WHERE email = ?", (email,))
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, email, name FROM users WHERE email = ?",
                (email,)
            )
            row = cursor.fetchone()
            if row:
                return {
                    'id': row[0],
                    'email': row[1],
                    'name': row[2]
                }
            return None

    def search_users(self, filters: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Safe dynamic query builder using parameterized queries.
        """
        allowed_fields = {'email', 'name', 'role'}
        query_parts = ["SELECT id, email, name FROM users WHERE 1=1"]
        params = []

        for field, value in filters.items():
            if field not in allowed_fields:
                raise ValueError(f"Invalid field: {field}")
            query_parts.append(f"AND {field} = ?")
            params.append(value)

        query = " ".join(query_parts)

        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, params)
            return [
                {'id': row[0], 'email': row[1], 'name': row[2]}
                for row in cursor.fetchall()
            ]
```

#### Rust: Command Injection Prevention
```rust
use std::process::Command;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum SecureCommandError {
    #[error("Invalid path: {0}")]
    InvalidPath(String),
    #[error("Command execution failed: {0}")]
    ExecutionFailed(String),
    #[error("Path traversal detected")]
    PathTraversal,
}

pub struct SecureFileProcessor {
    allowed_base_dir: PathBuf,
}

impl SecureFileProcessor {
    pub fn new(base_dir: PathBuf) -> Self {
        Self {
            allowed_base_dir: base_dir,
        }
    }

    /// Validate and canonicalize path to prevent path traversal
    fn validate_path(&self, user_path: &str) -> Result<PathBuf, SecureCommandError> {
        let requested = Path::new(user_path);

        // Check for path traversal attempts
        if user_path.contains("..") || user_path.contains("~") {
            return Err(SecureCommandError::PathTraversal);
        }

        let full_path = self.allowed_base_dir.join(requested);
        let canonical = full_path.canonicalize()
            .map_err(|e| SecureCommandError::InvalidPath(e.to_string()))?;

        // Ensure resolved path is still within base directory
        if !canonical.starts_with(&self.allowed_base_dir) {
            return Err(SecureCommandError::PathTraversal);
        }

        Ok(canonical)
    }

    /// Safe file processing using validated paths
    pub fn process_file(&self, filename: &str) -> Result<String, SecureCommandError> {
        let safe_path = self.validate_path(filename)?;

        // SECURE: Using array of arguments (no shell interpretation)
        let output = Command::new("/usr/bin/file")
            .arg("--brief")
            .arg(&safe_path)
            .output()
            .map_err(|e| SecureCommandError::ExecutionFailed(e.to_string()))?;

        // VULNERABLE (DON'T DO THIS):
        // Command::new("sh")
        //     .arg("-c")
        //     .arg(format!("file --brief {}", filename))  // Shell injection!

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }
}
```

### Detection Scripts

#### Detect Tampering Vulnerabilities
```bash
#!/bin/bash
# detect-tampering.sh - Finds data tampering vulnerabilities

echo "=== Scanning for Tampering Vulnerabilities ==="

# SQL injection (string concatenation)
echo -e "\n[1] Potential SQL Injection:"
rg 'execute\(.*\+.*\)' --type py --type go --type ts
rg 'Exec\(.*fmt\.Sprintf' --type go

# Command injection
echo -e "\n[2] Command Injection Risk:"
rg 'exec\.Command\("sh".*-c' --type go
rg 'subprocess\.(call|run|Popen).*shell=True' --type py

# Path traversal
echo -e "\n[3] Path Traversal Risk:"
rg 'os\.path\.join\([^)]*\)' --type py | rg -v 'abspath|realpath'
rg 'filepath\.Join' --type go -A 3 | rg -v 'Clean|Abs'

# Missing input validation
echo -e "\n[4] Missing Input Validation:"
rg 'req\.(body|query|params)\.' --type ts -A 3 | rg -v 'validate|schema|zod'

# XSS vulnerabilities (unsafe HTML rendering)
echo -e "\n[5] XSS Risk:"
rg 'dangerouslySetInnerHTML|innerHTML\s*=' --type ts --type js
rg 'template\.HTML\(' --type go | rg -v 'html\.Escape'

echo -e "\n=== Scan Complete ==="
```

---

## 3. Repudiation

### Threat Description
Ability to deny performing an action without proof otherwise. Targets audit logging, non-repudiation mechanisms, and forensic capabilities.

### Attack Vectors
- **Log tampering:** Deleting or modifying audit logs
- **Missing audit trails:** No record of critical operations
- **Clock manipulation:** Altering timestamps
- **Anonymous actions:** Operations without identity tracking

### Mitigations by Layer

#### Application Layer
- Comprehensive audit logging (who, what, when, where, why)
- Immutable audit logs (append-only)
- Digital signatures on log entries
- Correlation IDs across distributed systems
- Log integrity verification

#### Infrastructure Layer
- Centralized log aggregation (ELK, Splunk, Datadog)
- Write-once storage for logs (WORM, S3 Object Lock)
- Network time synchronization (NTP, PTP)
- Security Information and Event Management (SIEM)

### Implementation Example

#### Go: Audit Logging System
```go
package audit

import (
    "context"
    "crypto/hmac"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "time"
)

type EventType string

const (
    EventLogin          EventType = "auth.login"
    EventLogout         EventType = "auth.logout"
    EventDataAccess     EventType = "data.access"
    EventDataModify     EventType = "data.modify"
    EventAdminAction    EventType = "admin.action"
    EventSecurityAlert  EventType = "security.alert"
)

type AuditEvent struct {
    ID            string                 `json:"id"`
    Timestamp     time.Time              `json:"timestamp"`
    EventType     EventType              `json:"event_type"`
    UserID        string                 `json:"user_id"`
    IPAddress     string                 `json:"ip_address"`
    Resource      string                 `json:"resource"`
    Action        string                 `json:"action"`
    Result        string                 `json:"result"` // success, failure, denied
    Metadata      map[string]interface{} `json:"metadata"`
    CorrelationID string                 `json:"correlation_id"`
    Signature     string                 `json:"signature"`
}

type AuditLogger interface {
    Log(ctx context.Context, event AuditEvent) error
}

type SecureAuditLogger struct {
    writer   AuditWriter
    hmacKey  []byte
    sequence uint64
}

func NewSecureAuditLogger(writer AuditWriter, hmacKey []byte) *SecureAuditLogger {
    return &SecureAuditLogger{
        writer:  writer,
        hmacKey: hmacKey,
    }
}

func (l *SecureAuditLogger) Log(ctx context.Context, event AuditEvent) error {
    // Ensure timestamp is set
    if event.Timestamp.IsZero() {
        event.Timestamp = time.Now().UTC()
    }

    // Generate deterministic ID
    l.sequence++
    event.ID = generateEventID(event.Timestamp, l.sequence)

    // Extract correlation ID from context
    if corrID := ctx.Value("correlation_id"); corrID != nil {
        event.CorrelationID = corrID.(string)
    }

    // Sign the event for integrity
    event.Signature = l.signEvent(event)

    // Write to append-only storage
    return l.writer.Write(event)
}

func (l *SecureAuditLogger) signEvent(event AuditEvent) string {
    // Create canonical representation
    data, _ := json.Marshal(struct {
        ID            string    `json:"id"`
        Timestamp     time.Time `json:"timestamp"`
        EventType     EventType `json:"event_type"`
        UserID        string    `json:"user_id"`
        Resource      string    `json:"resource"`
        Action        string    `json:"action"`
        CorrelationID string    `json:"correlation_id"`
    }{
        ID:            event.ID,
        Timestamp:     event.Timestamp,
        EventType:     event.EventType,
        UserID:        event.UserID,
        Resource:      event.Resource,
        Action:        event.Action,
        CorrelationID: event.CorrelationID,
    })

    h := hmac.New(sha256.New, l.hmacKey)
    h.Write(data)
    return hex.EncodeToString(h.Sum(nil))
}

func generateEventID(ts time.Time, seq uint64) string {
    return fmt.Sprintf("%d-%016x", ts.Unix(), seq)
}

type AuditWriter interface {
    Write(event AuditEvent) error
}
```

---

## 4. Information Disclosure

### Threat Description
Exposure of sensitive information to unauthorized parties. Targets data confidentiality, error handling, and logging practices.

### Attack Vectors
- **Verbose error messages:** Stack traces, database errors in production
- **Information leakage:** Sensitive data in logs, cache, temp files
- **Side-channel attacks:** Timing attacks, cache attacks
- **Insufficient encryption:** Weak algorithms, exposed keys

### Mitigations
- Sanitize error messages in production
- Encrypt sensitive data at rest and in transit
- Secure key management
- Redact sensitive data from logs
- Constant-time comparisons for secrets
- Security headers (X-Content-Type-Options, etc.)

---

## 5. Denial of Service

### Threat Description
Making systems unavailable through resource exhaustion. Targets availability, performance, and resource management.

### Attack Vectors
- **Resource exhaustion:** Memory, CPU, disk, network bandwidth
- **Algorithmic complexity:** ReDoS, hash collision attacks
- **Connection exhaustion:** TCP SYN floods, slowloris
- **Application-layer floods:** HTTP floods, API abuse

### Mitigations
- Rate limiting and throttling
- Request size limits
- Timeouts on operations
- Circuit breakers
- Resource quotas
- DDoS protection (CDN, WAF)

---

## 6. Elevation of Privilege

### Threat Description
Gaining unauthorized access to elevated permissions. Targets authorization, access control, and privilege management.

### Attack Vectors
- **Authorization bypass:** Missing or weak authorization checks
- **Privilege escalation:** Exploiting bugs to gain admin access
- **Confused deputy:** Abusing trusted components
- **IDOR:** Accessing resources by manipulating IDs

### Mitigations
- Role-Based Access Control (RBAC)
- Attribute-Based Access Control (ABAC)
- Principle of least privilege
- Authorization checks at every layer
- Resource-level permissions
- Defense in depth

### Implementation Example

#### TypeScript: Authorization Middleware
```typescript
import { Request, Response, NextFunction } from 'express';

enum Permission {
  READ = 'read',
  WRITE = 'write',
  DELETE = 'delete',
  ADMIN = 'admin',
}

interface User {
  id: string;
  role: string;
  permissions: Permission[];
}

const ROLE_PERMISSIONS: Record<string, Permission[]> = {
  admin: [Permission.READ, Permission.WRITE, Permission.DELETE, Permission.ADMIN],
  editor: [Permission.READ, Permission.WRITE],
  viewer: [Permission.READ],
};

function requirePermission(...required: Permission[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const user = req.user as User;

    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const userPerms = new Set([
      ...ROLE_PERMISSIONS[user.role] || [],
      ...user.permissions,
    ]);

    const hasPermission = required.every(perm => userPerms.has(perm));

    if (!hasPermission) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    next();
  };
}

// Usage
app.delete('/api/users/:id',
  requirePermission(Permission.DELETE),
  deleteUserHandler
);
```

---

## Threat Modeling Process

### 1. Identify Assets
List critical data, services, and components requiring protection.

### 2. Create Architecture Diagrams
Document data flows, trust boundaries, and entry/exit points.

### 3. Apply STRIDE to Each Component
For each component, systematically evaluate all six threat categories.

### 4. Prioritize Threats
Use risk matrix (likelihood × impact) to prioritize remediation.

### 5. Define Mitigations
Document specific countermeasures for each identified threat.

### 6. Verify and Test
Validate that mitigations are correctly implemented and effective.

---

## OWASP Top 10 Security Risks (2021)

### A01:2021 - Broken Access Control

#### Vulnerability Description
Failures in access control allow unauthorized users to access data or perform actions beyond their permissions. Common issues include IDOR (Insecure Direct Object References), missing authorization checks, and privilege escalation.

#### Prevention by Language

**Go: Resource-Level Access Control**
```go
package authz

import (
    "context"
    "errors"
)

var ErrForbidden = errors.New("access denied")

type ResourceType string

const (
    ResourceDocument ResourceType = "document"
    ResourceProject  ResourceType = "project"
)

type Action string

const (
    ActionRead   Action = "read"
    ActionWrite  Action = "write"
    ActionDelete Action = "delete"
)

type Principal struct {
    UserID  string
    OrgID   string
    IsAdmin bool
}

type Resource struct {
    ID      string
    Type    ResourceType
    OwnerID string
    OrgID   string
}

type Authorizer struct {
    policies map[ResourceType]PolicyFunc
}

type PolicyFunc func(ctx context.Context, principal Principal, resource Resource, action Action) bool

func NewAuthorizer() *Authorizer {
    return &Authorizer{
        policies: map[ResourceType]PolicyFunc{
            ResourceDocument: documentPolicy,
            ResourceProject:  projectPolicy,
        },
    }
}

func (a *Authorizer) Authorize(ctx context.Context, principal Principal, resource Resource, action Action) error {
    policy, ok := a.policies[resource.Type]
    if !ok {
        return ErrForbidden
    }

    if !policy(ctx, principal, resource, action) {
        return ErrForbidden
    }

    return nil
}

func documentPolicy(ctx context.Context, principal Principal, resource Resource, action Action) bool {
    // Admins can do anything
    if principal.IsAdmin {
        return true
    }

    // Must be in same organization
    if principal.OrgID != resource.OrgID {
        return false
    }

    // Owner can do anything
    if principal.UserID == resource.OwnerID {
        return true
    }

    // Others can only read
    return action == ActionRead
}

func projectPolicy(ctx context.Context, principal Principal, resource Resource, action Action) bool {
    if principal.IsAdmin {
        return true
    }

    if principal.OrgID != resource.OrgID {
        return false
    }

    // Project-specific logic here
    return principal.UserID == resource.OwnerID
}
```

**TypeScript: IDOR Prevention**
```typescript
import { Request, Response, NextFunction } from 'express';

interface User {
  id: string;
  organizationId: string;
}

interface Document {
  id: string;
  ownerId: string;
  organizationId: string;
}

class DocumentService {
  async getDocument(documentId: string, user: User): Promise<Document> {
    const doc = await db.documents.findById(documentId);

    if (!doc) {
      throw new Error('Document not found');
    }

    // CRITICAL: Verify ownership before returning
    if (doc.organizationId !== user.organizationId) {
      throw new Error('Access denied');
    }

    return doc;
  }

  async updateDocument(
    documentId: string,
    user: User,
    updates: Partial<Document>
  ): Promise<Document> {
    const doc = await this.getDocument(documentId, user);

    // Additional write permission check
    if (doc.ownerId !== user.id) {
      throw new Error('Access denied: must be owner');
    }

    return db.documents.update(documentId, updates);
  }
}
```

#### Detection
```bash
# Detect missing authorization checks
rg -i '(get|delete|update).*handler' --type go -A 20 | rg -v 'Authorize|CheckPermission|HasAccess'
```

**Reference:** [OWASP A01 - Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/)

---

### A02:2021 - Cryptographic Failures

#### Vulnerability Description
Insufficient protection of sensitive data through weak or missing encryption. Includes plaintext storage, weak algorithms (MD5, SHA1), and improper key management.

#### Prevention by Language

**Python: Secure Password Hashing**
```python
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
import secrets

class SecurePasswordManager:
    """Password manager using Argon2id."""

    def __init__(self):
        # Argon2id is currently recommended by OWASP
        self.hasher = PasswordHasher(
            time_cost=2,        # Number of iterations
            memory_cost=65536,  # 64 MB
            parallelism=4,      # Number of threads
            hash_len=32,        # 32-byte hash
            salt_len=16         # 16-byte salt
        )

    def hash_password(self, password: str) -> str:
        """
        Hash password using Argon2id.

        DO NOT USE:
        - hashlib.md5()
        - hashlib.sha1()
        - hashlib.sha256() without salt
        """
        return self.hasher.hash(password)

    def verify_password(self, password: str, hash: str) -> bool:
        """Verify password against hash."""
        try:
            self.hasher.verify(hash, password)

            # Check if rehashing is needed (params changed)
            if self.hasher.check_needs_rehash(hash):
                # Signal that password should be rehashed on next login
                return True

            return True
        except VerifyMismatchError:
            return False

    def generate_token(self, num_bytes: int = 32) -> str:
        """Generate cryptographically secure random token."""
        return secrets.token_urlsafe(num_bytes)
```

**Rust: Encryption at Rest**
```rust
use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose, Engine};
use rand::RngCore;

pub struct DataEncryptor {
    cipher: Aes256Gcm,
}

impl DataEncryptor {
    pub fn new(key: &[u8; 32]) -> Self {
        let cipher = Aes256Gcm::new(key.into());
        Self { cipher }
    }

    pub fn encrypt(&self, plaintext: &[u8]) -> Result<String, String> {
        // Generate random nonce (96-bit for AES-GCM)
        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        // Encrypt
        let ciphertext = self.cipher.encrypt(nonce, plaintext)
            .map_err(|e| format!("Encryption failed: {}", e))?;

        // Prepend nonce to ciphertext (nonce doesn't need to be secret)
        let mut result = nonce_bytes.to_vec();
        result.extend_from_slice(&ciphertext);

        // Base64 encode for storage
        Ok(general_purpose::STANDARD.encode(&result))
    }

    pub fn decrypt(&self, encrypted_b64: &str) -> Result<Vec<u8>, String> {
        // Decode base64
        let encrypted = general_purpose::STANDARD.decode(encrypted_b64)
            .map_err(|e| format!("Base64 decode failed: {}", e))?;

        if encrypted.len() < 12 {
            return Err("Invalid encrypted data".to_string());
        }

        // Extract nonce (first 12 bytes)
        let (nonce_bytes, ciphertext) = encrypted.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        // Decrypt
        self.cipher.decrypt(nonce, ciphertext)
            .map_err(|e| format!("Decryption failed: {}", e))
    }
}
```

#### Detection
```bash
# Detect weak crypto
rg 'md5|sha1|des|rc4' --type go --type py --type rust -i
rg 'createHash\(["\x27](md5|sha1)' --type ts
```

**Reference:** [OWASP A02 - Cryptographic Failures](https://owasp.org/Top10/A02_2021-Cryptographic_Failures/)

---

### A03:2021 - Injection

#### Vulnerability Description
Untrusted data sent to an interpreter as part of a command or query. Includes SQL injection, NoSQL injection, OS command injection, LDAP injection, and expression language injection.

#### Prevention by Language

**Go: NoSQL Injection Prevention (MongoDB)**
```go
package db

import (
    "context"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/mongo"
)

type UserQuery struct {
    Email string `json:"email"`
    Role  string `json:"role"`
}

// VULNERABLE: Don't build queries from raw user input
func FindUsersVulnerable(ctx context.Context, coll *mongo.Collection, userInput map[string]interface{}) ([]User, error) {
    // DANGER: userInput could contain operators like {"$gt": "", "$ne": null}
    cursor, err := coll.Find(ctx, userInput)
    // ...
}

// SECURE: Use strongly-typed filters
func FindUsersSecure(ctx context.Context, coll *mongo.Collection, query UserQuery) ([]User, error) {
    filter := bson.M{
        "email": query.Email,
        "role":  query.Role,
    }

    cursor, err := coll.Find(ctx, filter)
    if err != nil {
        return nil, err
    }

    var users []User
    if err := cursor.All(ctx, &users); err != nil {
        return nil, err
    }

    return users, nil
}

// For dynamic queries, use explicit whitelisting
func BuildDynamicFilter(fields map[string]string) (bson.M, error) {
    allowedFields := map[string]bool{
        "email": true,
        "role":  true,
        "name":  true,
    }

    filter := bson.M{}
    for key, value := range fields {
        if !allowedFields[key] {
            return nil, fmt.Errorf("invalid field: %s", key)
        }
        // Use exact match only (no operators)
        filter[key] = value
    }

    return filter, nil
}
```

**Python: LDAP Injection Prevention**
```python
import ldap
import ldap.filter
from typing import List

class SecureLDAPClient:
    """LDAP client with injection protection."""

    def __init__(self, server: str):
        self.conn = ldap.initialize(server)

    def search_users(self, username: str) -> List[dict]:
        """
        Safe LDAP search with input sanitization.

        VULNERABLE:
            filter = f"(uid={username})"  # username='*)(uid=*' bypasses auth!

        SECURE:
            Use ldap.filter.escape_filter_chars()
        """
        # Escape special LDAP characters
        safe_username = ldap.filter.escape_filter_chars(username)

        # Build filter with escaped input
        search_filter = f"(uid={safe_username})"

        # LDAP special chars that get escaped:
        # * ( ) \ NUL

        results = self.conn.search_s(
            "ou=users,dc=example,dc=com",
            ldap.SCOPE_SUBTREE,
            search_filter,
            ["cn", "mail", "uid"]
        )

        return [
            {attr: val[0].decode() for attr, val in attrs.items()}
            for dn, attrs in results
        ]

    def authenticate(self, username: str, password: str) -> bool:
        """Safe LDAP bind with escaped credentials."""
        safe_username = ldap.filter.escape_filter_chars(username)
        dn = f"uid={safe_username},ou=users,dc=example,dc=com"

        try:
            self.conn.simple_bind_s(dn, password)
            return True
        except ldap.INVALID_CREDENTIALS:
            return False
```

#### Detection
```bash
# Detect injection vulnerabilities
rg 'Exec\(.*fmt\.Sprintf|Query\(.*\+' --type go
rg 'eval\(|exec\(' --type py --type js
rg '\.Find\(.*req\.(body|query)' --type ts
```

**Reference:** [OWASP A03 - Injection](https://owasp.org/Top10/A03_2021-Injection/)

---

### A04:2021 - Insecure Design

#### Vulnerability Description
Missing or ineffective security control design. Includes lack of threat modeling, insecure default configurations, and failure to implement security by design principles.

#### Prevention by Language

**TypeScript: Rate Limiting with Token Bucket**
```typescript
class RateLimiter {
  private buckets = new Map<string, TokenBucket>();
  private readonly maxTokens: number;
  private readonly refillRate: number; // tokens per second

  constructor(maxTokens: number, refillRate: number) {
    this.maxTokens = maxTokens;
    this.refillRate = refillRate;
  }

  async checkLimit(key: string, cost: number = 1): Promise<boolean> {
    let bucket = this.buckets.get(key);

    if (!bucket) {
      bucket = new TokenBucket(this.maxTokens, this.refillRate);
      this.buckets.set(key, bucket);
    }

    return bucket.consume(cost);
  }

  cleanup(): void {
    const now = Date.now();
    for (const [key, bucket] of this.buckets.entries()) {
      if (now - bucket.lastRefill > 3600000) { // 1 hour
        this.buckets.delete(key);
      }
    }
  }
}

class TokenBucket {
  private tokens: number;
  public lastRefill: number;

  constructor(
    private readonly capacity: number,
    private readonly refillRate: number
  ) {
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }

  consume(cost: number): boolean {
    this.refill();

    if (this.tokens >= cost) {
      this.tokens -= cost;
      return true;
    }

    return false;
  }

  private refill(): void {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000; // seconds
    const tokensToAdd = elapsed * this.refillRate;

    this.tokens = Math.min(this.capacity, this.tokens + tokensToAdd);
    this.lastRefill = now;
  }
}

// Usage in API middleware
const limiter = new RateLimiter(100, 10); // 100 tokens, refill 10/sec

export const rateLimitMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const clientId = req.ip || 'unknown';

  if (!await limiter.checkLimit(clientId)) {
    return res.status(429).json({
      error: 'Too many requests',
      retryAfter: 60
    });
  }

  next();
};
```

**Go: Circuit Breaker Pattern**
```go
package resilience

import (
    "context"
    "errors"
    "sync"
    "time"
)

var ErrCircuitOpen = errors.New("circuit breaker is open")

type State int

const (
    StateClosed State = iota
    StateOpen
    StateHalfOpen
)

type CircuitBreaker struct {
    mu              sync.Mutex
    state           State
    failureCount    int
    successCount    int
    lastFailureTime time.Time

    maxFailures     int
    timeout         time.Duration
    halfOpenSuccess int
}

func NewCircuitBreaker(maxFailures int, timeout time.Duration) *CircuitBreaker {
    return &CircuitBreaker{
        state:           StateClosed,
        maxFailures:     maxFailures,
        timeout:         timeout,
        halfOpenSuccess: 2,
    }
}

func (cb *CircuitBreaker) Execute(ctx context.Context, fn func() error) error {
    cb.mu.Lock()

    switch cb.state {
    case StateOpen:
        if time.Since(cb.lastFailureTime) > cb.timeout {
            // Try transitioning to half-open
            cb.state = StateHalfOpen
            cb.successCount = 0
        } else {
            cb.mu.Unlock()
            return ErrCircuitOpen
        }
    case StateHalfOpen:
        // Allow limited requests through
    case StateClosed:
        // Normal operation
    }

    cb.mu.Unlock()

    // Execute the function
    err := fn()

    cb.mu.Lock()
    defer cb.mu.Unlock()

    if err != nil {
        cb.onFailure()
        return err
    }

    cb.onSuccess()
    return nil
}

func (cb *CircuitBreaker) onFailure() {
    cb.failureCount++
    cb.lastFailureTime = time.Now()

    if cb.failureCount >= cb.maxFailures {
        cb.state = StateOpen
    }
}

func (cb *CircuitBreaker) onSuccess() {
    if cb.state == StateHalfOpen {
        cb.successCount++
        if cb.successCount >= cb.halfOpenSuccess {
            cb.state = StateClosed
            cb.failureCount = 0
        }
    } else {
        cb.failureCount = 0
    }
}
```

**Reference:** [OWASP A04 - Insecure Design](https://owasp.org/Top10/A04_2021-Insecure_Design/)

---

### A05:2021 - Security Misconfiguration

#### Vulnerability Description
Insecure default configurations, incomplete setups, open cloud storage, verbose error messages, and missing security headers.

#### Prevention by Language

**Go: Security Headers Middleware**
```go
package middleware

import (
    "net/http"
)

func SecurityHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Prevent clickjacking
        w.Header().Set("X-Frame-Options", "DENY")

        // Enable XSS protection
        w.Header().Set("X-Content-Type-Options", "nosniff")

        // Prevent MIME type sniffing
        w.Header().Set("X-XSS-Protection", "1; mode=block")

        // Content Security Policy
        w.Header().Set("Content-Security-Policy",
            "default-src 'self'; "+
            "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "+
            "style-src 'self' 'unsafe-inline'; "+
            "img-src 'self' data: https:; "+
            "font-src 'self'; "+
            "connect-src 'self'; "+
            "frame-ancestors 'none'")

        // Strict Transport Security (HSTS)
        w.Header().Set("Strict-Transport-Security",
            "max-age=63072000; includeSubDomains; preload")

        // Referrer Policy
        w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")

        // Permissions Policy (formerly Feature-Policy)
        w.Header().Set("Permissions-Policy",
            "geolocation=(), microphone=(), camera=()")

        next.ServeHTTP(w, r)
    })
}

func SecureErrorHandler(w http.ResponseWriter, r *http.Request, err error) {
    // Log detailed error for debugging
    log.Printf("Error: %v, Path: %s, Method: %s", err, r.URL.Path, r.Method)

    // Return generic error to client (don't leak internals)
    w.WriteHeader(http.StatusInternalServerError)
    json.NewEncoder(w).Encode(map[string]string{
        "error": "An internal error occurred",
        "code":  "INTERNAL_ERROR",
    })
}
```

#### Detection
```bash
# Check for missing security configurations
rg 'X-Frame-Options|Content-Security-Policy|Strict-Transport' --type go -c
rg 'helmet\(' --type ts -c
```

**Reference:** [OWASP A05 - Security Misconfiguration](https://owasp.org/Top10/A05_2021-Security_Misconfiguration/)

---

### A06:2021 - Vulnerable and Outdated Components

#### Vulnerability Description
Using components with known vulnerabilities, outdated libraries, and lack of dependency management.

#### Prevention

**Automated Scanning**
```bash
#!/bin/bash
# scan-dependencies.sh - Check for vulnerable dependencies

echo "=== Dependency Security Scan ==="

# Go vulnerabilities
if command -v govulncheck &> /dev/null; then
    echo -e "\n[Go] Running govulncheck..."
    govulncheck ./...
fi

# Node.js vulnerabilities
if [ -f "package.json" ]; then
    echo -e "\n[Node] Running npm audit..."
    npm audit --audit-level=moderate
fi

# Python vulnerabilities
if [ -f "requirements.txt" ]; then
    echo -e "\n[Python] Running safety check..."
    safety check -r requirements.txt
fi

# Rust vulnerabilities
if [ -f "Cargo.toml" ]; then
    echo -e "\n[Rust] Running cargo audit..."
    cargo audit
fi

# Container image scanning
echo -e "\n[Container] Running trivy..."
trivy image --severity HIGH,CRITICAL myapp:latest

echo -e "\n=== Scan Complete ==="
```

**Dependency Update Policy**
```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "security-team"

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    versioning-strategy: increase-if-necessary
```

**Reference:** [OWASP A06 - Vulnerable and Outdated Components](https://owasp.org/Top10/A06_2021-Vulnerable_and_Outdated_Components/)

---

### A07:2021 - Identification and Authentication Failures

#### Vulnerability Description
Weak password policies, credential stuffing, session fixation, and missing authentication controls.

#### Prevention by Language

**Rust: Secure Authentication System**
```rust
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use std::time::{Duration, SystemTime};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AuthError {
    #[error("Invalid credentials")]
    InvalidCredentials,
    #[error("Account locked")]
    AccountLocked,
    #[error("Password hash error: {0}")]
    HashError(String),
}

pub struct AuthService {
    max_attempts: u32,
    lockout_duration: Duration,
}

pub struct Account {
    pub username: String,
    pub password_hash: String,
    pub failed_attempts: u32,
    pub locked_until: Option<SystemTime>,
    pub mfa_enabled: bool,
    pub mfa_secret: Option<String>,
}

impl AuthService {
    pub fn new() -> Self {
        Self {
            max_attempts: 5,
            lockout_duration: Duration::from_secs(900), // 15 minutes
        }
    }

    pub fn hash_password(&self, password: &str) -> Result<String, AuthError> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        let hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| AuthError::HashError(e.to_string()))?
            .to_string();

        Ok(hash)
    }

    pub fn verify_password(&self, password: &str, hash: &str) -> Result<bool, AuthError> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| AuthError::HashError(e.to_string()))?;

        Ok(Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .is_ok())
    }

    pub fn authenticate(&self, account: &mut Account, password: &str) -> Result<(), AuthError> {
        // Check if account is locked
        if let Some(locked_until) = account.locked_until {
            if SystemTime::now() < locked_until {
                return Err(AuthError::AccountLocked);
            }
            // Unlock account
            account.locked_until = None;
            account.failed_attempts = 0;
        }

        // Verify password
        if !self.verify_password(password, &account.password_hash)? {
            account.failed_attempts += 1;

            // Lock account if max attempts reached
            if account.failed_attempts >= self.max_attempts {
                account.locked_until = Some(SystemTime::now() + self.lockout_duration);
            }

            return Err(AuthError::InvalidCredentials);
        }

        // Reset failed attempts on success
        account.failed_attempts = 0;
        Ok(())
    }

    pub fn validate_password_strength(&self, password: &str) -> Result<(), String> {
        if password.len() < 12 {
            return Err("Password must be at least 12 characters".to_string());
        }

        let has_uppercase = password.chars().any(|c| c.is_uppercase());
        let has_lowercase = password.chars().any(|c| c.is_lowercase());
        let has_digit = password.chars().any(|c| c.is_numeric());
        let has_special = password.chars().any(|c| !c.is_alphanumeric());

        if !has_uppercase || !has_lowercase || !has_digit || !has_special {
            return Err("Password must contain uppercase, lowercase, digit, and special character".to_string());
        }

        Ok(())
    }
}
```

**Reference:** [OWASP A07 - Identification and Authentication Failures](https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/)

---

### A08:2021 - Software and Data Integrity Failures

#### Vulnerability Description
Code and infrastructure that doesn't protect against integrity violations, such as insecure CI/CD pipelines, unverified updates, and insecure deserialization.

#### Prevention by Language

**Python: Secure Deserialization**
```python
import json
import hmac
import hashlib
from typing import Any, Dict
from base64 import b64encode, b64decode

class SecureSerializer:
    """Safe serialization with integrity protection."""

    def __init__(self, secret_key: bytes):
        self.secret_key = secret_key

    def serialize(self, data: Dict[str, Any]) -> str:
        """
        Serialize with HMAC signature.

        NEVER USE:
        - pickle.loads() on untrusted data
        - eval() on serialized data
        - yaml.load() without SafeLoader
        """
        # Convert to JSON (safe format)
        json_data = json.dumps(data, separators=(',', ':'))
        json_bytes = json_data.encode('utf-8')

        # Create HMAC signature
        signature = hmac.new(
            self.secret_key,
            json_bytes,
            hashlib.sha256
        ).digest()

        # Combine signature + data
        signed = signature + json_bytes

        # Base64 encode for transport
        return b64encode(signed).decode('ascii')

    def deserialize(self, signed_data: str) -> Dict[str, Any]:
        """Deserialize and verify integrity."""
        # Decode base64
        try:
            signed = b64decode(signed_data.encode('ascii'))
        except Exception:
            raise ValueError("Invalid base64 data")

        if len(signed) < 32:
            raise ValueError("Data too short")

        # Split signature and data
        signature = signed[:32]
        json_bytes = signed[32:]

        # Verify signature
        expected_sig = hmac.new(
            self.secret_key,
            json_bytes,
            hashlib.sha256
        ).digest()

        if not hmac.compare_digest(signature, expected_sig):
            raise ValueError("Signature verification failed")

        # Deserialize JSON
        try:
            return json.loads(json_bytes.decode('utf-8'))
        except json.JSONDecodeError:
            raise ValueError("Invalid JSON data")

# Example: Safe YAML loading
import yaml

def load_config_safely(config_path: str) -> Dict[str, Any]:
    """Load YAML config safely."""
    with open(config_path, 'r') as f:
        # Use SafeLoader to prevent code execution
        return yaml.load(f, Loader=yaml.SafeLoader)
```

**Go: Code Signing Verification**
```go
package signing

import (
    "crypto"
    "crypto/rsa"
    "crypto/sha256"
    "crypto/x509"
    "encoding/pem"
    "errors"
    "os"
)

var ErrInvalidSignature = errors.New("invalid signature")

type CodeVerifier struct {
    publicKey *rsa.PublicKey
}

func NewCodeVerifier(publicKeyPath string) (*CodeVerifier, error) {
    pemData, err := os.ReadFile(publicKeyPath)
    if err != nil {
        return nil, err
    }

    block, _ := pem.Decode(pemData)
    if block == nil {
        return nil, errors.New("failed to parse PEM block")
    }

    pub, err := x509.ParsePKIXPublicKey(block.Bytes)
    if err != nil {
        return nil, err
    }

    rsaPub, ok := pub.(*rsa.PublicKey)
    if !ok {
        return nil, errors.New("not an RSA public key")
    }

    return &CodeVerifier{publicKey: rsaPub}, nil
}

func (v *CodeVerifier) VerifyFile(filePath string, signaturePath string) error {
    // Read file content
    content, err := os.ReadFile(filePath)
    if err != nil {
        return err
    }

    // Read signature
    signature, err := os.ReadFile(signaturePath)
    if err != nil {
        return err
    }

    // Hash the content
    hashed := sha256.Sum256(content)

    // Verify signature
    err = rsa.VerifyPKCS1v15(v.publicKey, crypto.SHA256, hashed[:], signature)
    if err != nil {
        return ErrInvalidSignature
    }

    return nil
}
```

**Reference:** [OWASP A08 - Software and Data Integrity Failures](https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/)

---

### A09:2021 - Security Logging and Monitoring Failures

#### Vulnerability Description
Insufficient logging, detection, monitoring, and alerting allowing attacks to persist undetected.

#### Prevention by Language

**TypeScript: Structured Security Logging**
```typescript
import winston from 'winston';

enum SecurityEventType {
  AUTH_SUCCESS = 'auth.success',
  AUTH_FAILURE = 'auth.failure',
  AUTH_LOCKOUT = 'auth.lockout',
  ACCESS_DENIED = 'access.denied',
  DATA_EXPORT = 'data.export',
  CONFIG_CHANGE = 'config.change',
  SUSPICIOUS_ACTIVITY = 'security.suspicious',
}

interface SecurityEvent {
  type: SecurityEventType;
  userId?: string;
  ipAddress: string;
  userAgent: string;
  resource?: string;
  action?: string;
  result: 'success' | 'failure';
  details?: Record<string, any>;
  timestamp: Date;
}

class SecurityLogger {
  private logger: winston.Logger;

  constructor() {
    this.logger = winston.createLogger({
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      transports: [
        // Write security events to dedicated log
        new winston.transports.File({
          filename: 'security-events.log',
          level: 'info',
        }),
        // Critical events to separate file
        new winston.transports.File({
          filename: 'security-critical.log',
          level: 'warn',
        }),
      ],
    });
  }

  logEvent(event: SecurityEvent): void {
    const logEntry = {
      ...event,
      timestamp: event.timestamp.toISOString(),
    };

    // Determine severity
    const severity = this.getSeverity(event);

    this.logger.log(severity, 'Security Event', logEntry);

    // Trigger alerts for critical events
    if (severity === 'warn' || severity === 'error') {
      this.triggerAlert(event);
    }
  }

  private getSeverity(event: SecurityEvent): string {
    switch (event.type) {
      case SecurityEventType.AUTH_LOCKOUT:
      case SecurityEventType.SUSPICIOUS_ACTIVITY:
        return 'warn';
      case SecurityEventType.AUTH_FAILURE:
        return 'info';
      default:
        return 'info';
    }
  }

  private triggerAlert(event: SecurityEvent): void {
    // Send to SIEM, alerting system, etc.
    // Implementation depends on your infrastructure
  }
}

// Middleware to log security events
export const securityLoggerMiddleware = (logger: SecurityLogger) => {
  return (req: Request, res: Response, next: NextFunction) => {
    // Log on response finish
    res.on('finish', () => {
      if (res.statusCode === 401 || res.statusCode === 403) {
        logger.logEvent({
          type: res.statusCode === 401
            ? SecurityEventType.AUTH_FAILURE
            : SecurityEventType.ACCESS_DENIED,
          userId: req.user?.id,
          ipAddress: req.ip,
          userAgent: req.headers['user-agent'] || '',
          resource: req.path,
          action: req.method,
          result: 'failure',
          timestamp: new Date(),
        });
      }
    });

    next();
  };
};
```

**Reference:** [OWASP A09 - Security Logging and Monitoring Failures](https://owasp.org/Top10/A09_2021-Security_Logging_and_Monitoring_Failures/)

---

### A10:2021 - Server-Side Request Forgery (SSRF)

#### Vulnerability Description
Application fetches remote resources without validating user-supplied URLs, allowing attackers to coerce the application to send requests to unintended destinations.

#### Prevention by Language

**Go: SSRF Prevention**
```go
package ssrf

import (
    "errors"
    "net"
    "net/http"
    "net/url"
    "strings"
    "time"
)

var (
    ErrInvalidURL      = errors.New("invalid URL")
    ErrBlockedIP       = errors.New("IP address is blocked")
    ErrBlockedProtocol = errors.New("protocol is blocked")
)

type SSRFProtection struct {
    allowedProtocols []string
    blockedNetworks  []*net.IPNet
    client           *http.Client
}

func NewSSRFProtection() *SSRFProtection {
    // Parse blocked IP ranges
    blockedNetworks := []*net.IPNet{}
    blockedCIDRs := []string{
        "127.0.0.0/8",      // Loopback
        "10.0.0.0/8",       // Private
        "172.16.0.0/12",    // Private
        "192.168.0.0/16",   // Private
        "169.254.0.0/16",   // Link-local
        "::1/128",          // IPv6 loopback
        "fc00::/7",         // IPv6 private
        "fe80::/10",        // IPv6 link-local
    }

    for _, cidr := range blockedCIDRs {
        _, ipNet, _ := net.ParseCIDR(cidr)
        blockedNetworks = append(blockedNetworks, ipNet)
    }

    return &SSRFProtection{
        allowedProtocols: []string{"http", "https"},
        blockedNetworks:  blockedNetworks,
        client: &http.Client{
            Timeout: 10 * time.Second,
            Transport: &http.Transport{
                DisableKeepAlives: true,
            },
        },
    }
}

func (p *SSRFProtection) ValidateURL(rawURL string) error {
    parsed, err := url.Parse(rawURL)
    if err != nil {
        return ErrInvalidURL
    }

    // Check protocol
    if !p.isProtocolAllowed(parsed.Scheme) {
        return ErrBlockedProtocol
    }

    // Resolve hostname
    host := parsed.Hostname()
    ips, err := net.LookupIP(host)
    if err != nil {
        return ErrInvalidURL
    }

    // Check if any resolved IP is blocked
    for _, ip := range ips {
        if p.isIPBlocked(ip) {
            return ErrBlockedIP
        }
    }

    return nil
}

func (p *SSRFProtection) isProtocolAllowed(protocol string) bool {
    protocol = strings.ToLower(protocol)
    for _, allowed := range p.allowedProtocols {
        if protocol == allowed {
            return true
        }
    }
    return false
}

func (p *SSRFProtection) isIPBlocked(ip net.IP) bool {
    for _, network := range p.blockedNetworks {
        if network.Contains(ip) {
            return true
        }
    }
    return false
}

func (p *SSRFProtection) FetchURL(rawURL string) (*http.Response, error) {
    // Validate URL before fetching
    if err := p.ValidateURL(rawURL); err != nil {
        return nil, err
    }

    // Fetch with validated URL
    return p.client.Get(rawURL)
}
```

**Python: SSRF Protection for APIs**
```python
import ipaddress
import requests
from urllib.parse import urlparse
from typing import Set

class SSRFProtector:
    """Protect against SSRF attacks."""

    def __init__(self):
        self.allowed_protocols = {'http', 'https'}
        self.blocked_networks = [
            ipaddress.ip_network('127.0.0.0/8'),      # Loopback
            ipaddress.ip_network('10.0.0.0/8'),       # Private
            ipaddress.ip_network('172.16.0.0/12'),    # Private
            ipaddress.ip_network('192.168.0.0/16'),   # Private
            ipaddress.ip_network('169.254.0.0/16'),   # Link-local
            ipaddress.ip_network('::1/128'),          # IPv6 loopback
            ipaddress.ip_network('fc00::/7'),         # IPv6 private
        ]

    def validate_url(self, url: str) -> None:
        """Validate URL is safe from SSRF."""
        parsed = urlparse(url)

        # Check protocol
        if parsed.scheme not in self.allowed_protocols:
            raise ValueError(f"Protocol {parsed.scheme} not allowed")

        # Check hostname isn't an IP address
        hostname = parsed.hostname
        if not hostname:
            raise ValueError("Invalid URL: missing hostname")

        # Prevent direct IP access
        try:
            ip = ipaddress.ip_address(hostname)
            raise ValueError("Direct IP address access not allowed")
        except ValueError:
            pass  # Hostname is not an IP, which is good

        # Resolve and check IPs
        import socket
        try:
            addrs = socket.getaddrinfo(hostname, None)
        except socket.gaierror:
            raise ValueError(f"Cannot resolve hostname: {hostname}")

        for addr_info in addrs:
            ip = ipaddress.ip_address(addr_info[4][0])
            for network in self.blocked_networks:
                if ip in network:
                    raise ValueError(f"IP {ip} is in blocked network {network}")

    def fetch(self, url: str, **kwargs) -> requests.Response:
        """Safely fetch URL with SSRF protection."""
        self.validate_url(url)

        # Add safety defaults
        kwargs.setdefault('timeout', 10)
        kwargs.setdefault('allow_redirects', False)  # Prevent redirect bypass

        return requests.get(url, **kwargs)
```

**Reference:** [OWASP A10 - Server-Side Request Forgery](https://owasp.org/Top10/A10_2021-Server-Side_Request_Forgery_%28SSRF%29/)

---

## Secrets Management

### Overview

Secure secrets management is critical for protecting sensitive data like API keys, database credentials, encryption keys, and certificates. Never hardcode secrets in source code or configuration files.

### Secret Storage Solutions

#### HashiCorp Vault Integration

**Go: Vault Client**
```go
package secrets

import (
    "context"
    "fmt"
    "time"

    vault "github.com/hashicorp/vault/api"
)

type VaultClient struct {
    client *vault.Client
}

func NewVaultClient(address, token string) (*VaultClient, error) {
    config := vault.DefaultConfig()
    config.Address = address

    client, err := vault.NewClient(config)
    if err != nil {
        return nil, err
    }

    client.SetToken(token)

    return &VaultClient{client: client}, nil
}

func (v *VaultClient) GetSecret(ctx context.Context, path string) (map[string]interface{}, error) {
    secret, err := v.client.Logical().ReadWithContext(ctx, path)
    if err != nil {
        return nil, err
    }

    if secret == nil {
        return nil, fmt.Errorf("secret not found at path: %s", path)
    }

    return secret.Data, nil
}

func (v *VaultClient) GetDatabaseCredentials(ctx context.Context, role string) (*DatabaseCreds, error) {
    path := fmt.Sprintf("database/creds/%s", role)
    data, err := v.GetSecret(ctx, path)
    if err != nil {
        return nil, err
    }

    return &DatabaseCreds{
        Username: data["username"].(string),
        Password: data["password"].(string),
        LeaseID:  data["lease_id"].(string),
    }, nil
}

type DatabaseCreds struct {
    Username string
    Password string
    LeaseID  string
}
```

#### Environment Variables (Secure Loading)

**Python: Environment Variable Management**
```python
import os
from pathlib import Path
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class SecretManager:
    """Secure secret loading from environment."""

    @staticmethod
    def get_secret(name: str, required: bool = True) -> Optional[str]:
        """
        Get secret from environment.

        Security best practices:
        1. Use environment variables, not config files
        2. Validate secrets exist at startup
        3. Never log secret values
        4. Use separate secrets per environment
        """
        value = os.environ.get(name)

        if value is None and required:
            raise ValueError(f"Required secret {name} not found in environment")

        if value:
            # Log that secret was loaded, but not the value
            logger.info(f"Loaded secret: {name}")

        return value

    @staticmethod
    def load_from_file(file_path: str) -> None:
        """
        Load secrets from file (for local development only).

        WARNING: Never use in production!
        File should be in .gitignore
        """
        path = Path(file_path)
        if not path.exists():
            logger.warning(f"Secret file not found: {file_path}")
            return

        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue

                try:
                    key, value = line.split('=', 1)
                    os.environ[key.strip()] = value.strip()
                except ValueError:
                    logger.warning(f"Invalid line in secret file: {line}")

class DatabaseConfig:
    """Example: Type-safe secret access."""

    def __init__(self):
        self.host = SecretManager.get_secret('DB_HOST')
        self.port = int(SecretManager.get_secret('DB_PORT', required=False) or '5432')
        self.username = SecretManager.get_secret('DB_USERNAME')
        self.password = SecretManager.get_secret('DB_PASSWORD')
        self.database = SecretManager.get_secret('DB_NAME')

    @property
    def connection_string(self) -> str:
        """Build connection string without exposing password."""
        # Don't include password in string that might be logged
        return f"postgresql://{self.username}@{self.host}:{self.port}/{self.database}"

    def get_full_connection_string(self) -> str:
        """Get connection string with password (use carefully)."""
        return f"postgresql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"
```

### Key Rotation

**TypeScript: Rotating Encryption Keys**
```typescript
interface EncryptionKey {
  id: string;
  key: Buffer;
  createdAt: Date;
  expiresAt: Date;
  active: boolean;
}

class KeyRotationManager {
  private keys: Map<string, EncryptionKey> = new Map();
  private currentKeyId: string | null = null;

  constructor(private readonly keyRotationDays: number = 90) {}

  addKey(key: EncryptionKey): void {
    this.keys.set(key.id, key);
    if (key.active) {
      this.currentKeyId = key.id;
    }
  }

  getCurrentKey(): EncryptionKey {
    if (!this.currentKeyId) {
      throw new Error('No active encryption key');
    }

    const key = this.keys.get(this.currentKeyId);
    if (!key) {
      throw new Error('Current key not found');
    }

    // Check if key needs rotation
    if (new Date() > key.expiresAt) {
      throw new Error('Current key expired - rotation required');
    }

    return key;
  }

  getKeyById(id: string): EncryptionKey | undefined {
    return this.keys.get(id);
  }

  rotateKeys(): void {
    // Mark old keys as inactive
    for (const key of this.keys.values()) {
      if (key.active) {
        key.active = false;
      }
    }

    // Generate new key
    const newKey: EncryptionKey = {
      id: crypto.randomUUID(),
      key: crypto.randomBytes(32),
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + this.keyRotationDays * 24 * 60 * 60 * 1000),
      active: true,
    };

    this.addKey(newKey);

    // In production, store new key in secure backend (Vault, KMS, etc.)
  }

  // Encrypt with current key, include key ID in output
  encrypt(data: Buffer): { keyId: string; ciphertext: Buffer } {
    const key = this.getCurrentKey();
    // Encryption logic here...
    return {
      keyId: key.id,
      ciphertext: Buffer.from('encrypted-data'), // Placeholder
    };
  }

  // Decrypt with specified key (supports old keys)
  decrypt(keyId: string, ciphertext: Buffer): Buffer {
    const key = this.getKeyById(keyId);
    if (!key) {
      throw new Error(`Key ${keyId} not found`);
    }
    // Decryption logic here...
    return Buffer.from('decrypted-data'); // Placeholder
  }
}
```

### Cloud Provider Secret Management

**AWS Secrets Manager**
```python
import boto3
import json
from botocore.exceptions import ClientError

class AWSSecretsManager:
    """AWS Secrets Manager integration."""

    def __init__(self, region_name: str):
        self.client = boto3.client('secretsmanager', region_name=region_name)

    def get_secret(self, secret_name: str) -> dict:
        """Retrieve secret from AWS Secrets Manager."""
        try:
            response = self.client.get_secret_value(SecretId=secret_name)
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                raise ValueError(f"Secret {secret_name} not found")
            elif e.response['Error']['Code'] == 'InvalidRequestException':
                raise ValueError(f"Invalid request for secret {secret_name}")
            else:
                raise

        # Parse secret string
        if 'SecretString' in response:
            return json.loads(response['SecretString'])
        else:
            # Binary secret
            return {'binary': response['SecretBinary']}

    def create_secret(self, secret_name: str, secret_value: dict) -> str:
        """Create new secret in AWS Secrets Manager."""
        response = self.client.create_secret(
            Name=secret_name,
            SecretString=json.dumps(secret_value)
        )
        return response['ARN']

    def rotate_secret(self, secret_name: str, lambda_arn: str) -> None:
        """Configure automatic rotation for secret."""
        self.client.rotate_secret(
            SecretId=secret_name,
            RotationLambdaARN=lambda_arn,
            RotationRules={
                'AutomaticallyAfterDays': 30
            }
        )
```

### Detection Scripts

**Detect Hardcoded Secrets**
```bash
#!/bin/bash
# detect-secrets.sh - Find hardcoded secrets in code

echo "=== Scanning for Hardcoded Secrets ==="

# API keys and tokens
echo -e "\n[1] API Keys and Tokens:"
rg -i '(api[_-]?key|api[_-]?token|access[_-]?token)\s*[:=]\s*["\x27][a-zA-Z0-9]{20,}' \
    --type go --type py --type ts --type js

# AWS credentials
echo -e "\n[2] AWS Credentials:"
rg 'AKIA[0-9A-Z]{16}' --type-all

# Private keys
echo -e "\n[3] Private Keys:"
rg 'BEGIN (RSA |EC |DSA )?PRIVATE KEY' --type-all

# Database connection strings
echo -e "\n[4] Database Passwords:"
rg -i '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27]{3,}["\x27]' \
    --type go --type py --type ts --type js | rg -v '(env|ENV|config)'

# Hardcoded JWTs
echo -e "\n[5] JWT Tokens:"
rg 'eyJ[A-Za-z0-9-_]+\.eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+' --type-all

echo -e "\n=== Scan Complete ==="
echo "Review all findings - some may be false positives"
```

### Security Best Practices

1. **Never commit secrets to version control**
   - Use .gitignore for secret files
   - Run pre-commit hooks to detect secrets
   - Use git-secrets or gitleaks

2. **Use secret management systems**
   - HashiCorp Vault for on-premise
   - AWS Secrets Manager / Azure Key Vault for cloud
   - Kubernetes Secrets for container workloads

3. **Rotate secrets regularly**
   - Database credentials: 30-90 days
   - API keys: 90 days
   - Encryption keys: 90-365 days
   - Certificates: per PKI policy

4. **Principle of least privilege**
   - Grant minimum necessary access
   - Use separate secrets per service
   - Separate dev/staging/production secrets

5. **Audit and monitor**
   - Log secret access (not values)
   - Alert on unusual access patterns
   - Regular secret access reviews

---

## References

- [Microsoft STRIDE Documentation](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [NIST SP 800-154: Guide to Data-Centric System Threat Modeling](https://csrc.nist.gov/publications/detail/sp/800-154/draft)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [CWE Top 25 Most Dangerous Software Weaknesses](https://cwe.mitre.org/top25/)
