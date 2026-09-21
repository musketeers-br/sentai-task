# Contract: Evidence Envelope JSON Shape

**Feature**: 001-validate-async-job-contract
**Consumed by**: every downstream feature that consumes captured evidence.

Each evidence file at
`specs/001-validate-async-job-contract/evidence/NN-<slug>.json` MUST
conform to the following shape. Downstream features consume these
files by path and by shape; changes to the shape are contract changes
and require an amendment to this document.

## JSON Schema (Draft 2020-12)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://sentai-task.local/schemas/evidence-envelope.json",
  "title": "Evidence Envelope",
  "type": "object",
  "required": ["call_id", "captured_at", "platform", "request", "response", "notes"],
  "additionalProperties": false,
  "properties": {
    "call_id": {
      "type": "string",
      "pattern": "^[0-9]{2}[a-z]?-[a-z0-9-]+$",
      "description": "Matches the file's basename without .json."
    },
    "captured_at": {
      "type": "string",
      "format": "date-time",
      "description": "ISO-8601 UTC, seconds precision, 'Z' suffix."
    },
    "platform": {
      "type": "object",
      "required": ["version"],
      "additionalProperties": false,
      "properties": {
        "version": {
          "type": "string",
          "description": "As reported by the platform itself, not by the operator."
        },
        "image_digest": {
          "type": "string",
          "pattern": "^sha256:[0-9a-f]{64}$"
        }
      }
    },
    "request": {
      "type": "object",
      "required": ["method", "url_path", "query", "headers"],
      "additionalProperties": false,
      "properties": {
        "method": {
          "type": "string",
          "enum": ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"]
        },
        "url_path": {
          "type": "string",
          "pattern": "^/"
        },
        "query": {
          "type": "object",
          "description": "Flat map. Values with credential-shaped keys are '<REDACTED>'."
        },
        "headers": {
          "type": "object",
          "description": "Authorization is always '<REDACTED>'."
        },
        "body": {
          "description": "Any JSON value, or absent for GET/HEAD."
        }
      }
    },
    "response": {
      "type": "object",
      "required": ["status", "headers", "body"],
      "additionalProperties": false,
      "properties": {
        "status": { "type": "integer", "minimum": 100, "maximum": 599 },
        "headers": {
          "type": "object",
          "description": "Set-Cookie and token-shaped headers are '<REDACTED>'."
        },
        "body": {
          "description": "Any JSON value, or null when empty. Credential-shaped fields are '<REDACTED>'."
        }
      }
    },
    "notes": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Free-text strings the script emits for observed deviations. MUST NOT contain secrets."
    }
  }
}
```

## Sentinel string

The redaction sentinel is exactly `<REDACTED>` (angle brackets included,
uppercase). Downstream features and any future validator MAY rely on this
literal string as a signal that a field was intentionally scrubbed. Any
other spelling is a bug.

## What redaction targets

| Location             | Rule                                                                                       |
|----------------------|--------------------------------------------------------------------------------------------|
| `request.headers`    | `Authorization` (any casing) → `<REDACTED>`.                                               |
| `request.query`      | Keys ending in `password`, `token`, `secret`, `credential` (case-insensitive) → `<REDACTED>`. |
| `request.body`       | Fields whose leaf key ends in `password`, `token`, `secret`, `credential` (case-insensitive) → `<REDACTED>`. |
| `response.headers`   | `Set-Cookie`, and any `X-*-Token` / `Authorization` → `<REDACTED>`.                        |
| `response.body`      | Fields whose leaf key ends in `token`, `refreshToken`, `accessToken`, `sessionId`, `csrf` (case-insensitive) → `<REDACTED>`. |

Redaction applies before the envelope is written to disk. There is no
"cleanup pass". If a new credential-shaped field is observed at run time
that no existing rule matches, the script emits a WARNING on stderr and
adds a note to the envelope; the field is still written verbatim so the
operator can decide whether to extend the rules — but only when the run
is against a private test instance, never on a public run.

## Example (call 3, illustrative shape only)

```json
{
  "call_id": "03-tasks-list",
  "captured_at": "2026-09-20T14:03:14Z",
  "platform": {
    "version": "IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2025.1 (…)",
    "image_digest": "sha256:0123456789abcdef…"
  },
  "request": {
    "method": "GET",
    "url_path": "/api/admin/v2/tasks",
    "query": {},
    "headers": {
      "Accept": "application/json",
      "Authorization": "<REDACTED>"
    }
  },
  "response": {
    "status": 200,
    "headers": {
      "Content-Type": "application/json; charset=utf-8"
    },
    "body": {
      "…platform-returned list shape…": "…"
    }
  },
  "notes": []
}
```
