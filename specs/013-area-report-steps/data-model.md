# Data Model: Area Report Steps

## 1. Registry entries (`sentai.registry.StepType` XData)

```json
{ "type": "security-posture-report", "label": "Security posture report", "class": "sentai.steps.reports.SecurityPosture",
  "category": "security", "executor": "platform-read", "destructive": false, "pausable": false, "available": true,
  "parameters": [ { "name": "failOnFindings", "property": "FailOnFindings", "type": "boolean", "required": false, "default": false,
                    "description": "Fail the step when any high finding exists" } ] },
{ "type": "web-app-inventory", "label": "Web application inventory", "class": "sentai.steps.reports.WebAppInventory",
  "category": "security", "executor": "platform-read", "destructive": false, "pausable": false, "available": true,
  "parameters": [ { "name": "failOnFindings", "property": "FailOnFindings", "type": "boolean", "required": false, "default": false,
                    "description": "Fail the step when any high finding exists" } ] },
{ "type": "system-alerts-check", "label": "System alerts check", "class": "sentai.steps.reports.SystemAlerts",
  "category": "monitoring", "executor": "platform-read", "destructive": false, "pausable": false, "available": true,
  "parameters": [
    { "name": "maxSeriousAlerts", "property": "MaxSeriousAlerts", "type": "integer", "required": false, "default": 0, "min": 0,
      "description": "Fail when the platform reports more serious alerts than this" },
    { "name": "maxApplicationErrors", "property": "MaxApplicationErrors", "type": "integer", "required": false, "default": 0, "min": 0,
      "description": "Fail when the platform reports more application errors than this" },
    { "name": "requireNormalStatus", "property": "RequireNormalStatus", "type": "boolean", "required": false, "default": true,
      "description": "Fail when any system resource status is not Normal" } ] },
{ "type": "secrets-inventory", "label": "Secrets inventory", "class": "sentai.steps.reports.SecretsInventory",
  "category": "security", "executor": "platform-read", "destructive": false, "pausable": false, "available": true,
  "parameters": [] }
```

`property` is kept for symmetry with the in-process entries. `ReadExecutor` passes the declared
parameters to `Build` as a `%DynamicObject` filled from the schema (defaults applied, keys not in
the schema ignored), the same rule as `InProcessExecutor.ApplyParameters`.

## 2. Report details per type

| Type | `details` | Findings (rule id → severity) |
|---|---|---|
| security-posture-report | `accounts: [{name, fullName, roles, accountNeverExpires, passwordNeverExpires}]` (enabled only), `services: [{name, authenticationMethods}]` (enabled only), `auditEnabled` | `ALL_ROLE_HOLDER` → high (item = account); `UNAUTHENTICATED_SERVICE` → medium (item = service); `AUDIT_DISABLED` → high; `ROLES_NOT_READABLE` → medium (item = account, detail = platform text); `ROLES_CAP_REACHED` → info |
| web-app-inventory | `applications: [{path, namespace, enabled, rest, dispatchClass, resource, authenticationMethods, system}]` | `ANONYMOUS_REST_ENDPOINT` → high; `ANONYMOUS_APPLICATION` → medium (both: enabled, not system, `Unauthenticated` allowed, no resource) |
| system-alerts-check | `alerts: {serious, applicationErrors}`, `systemUsage: {<name>: <status>}`, `license: {use, limit, high}`, `uptime`, `thresholds: {…}` | `SERIOUS_ALERTS_OVER` → high; `APPLICATION_ERRORS_OVER` → high; `STATUS_NOT_NORMAL` → high (item = resource) |
| secrets-inventory | `collections: [{name, useResource, editResource, secrets: [{name, type}]}]` | `UNPROTECTED_COLLECTION` → medium |

## 3. Frontend

- `StepTypeInfo.executor`: `'platform-api' | 'in-process' | 'platform-read'`.
- `StepCategory`: adds `'security' | 'monitoring'`; `GROUP_ORDER`: verification, security,
  monitoring, storage, journal, purge, backup, custom.
- `StepRunView.result: unknown | null` (from the wire `result`, `{}` → null).
- `result.ts`: `isReport(r): r is Report`; `orderedFindings(report)`; `severityLabel`.
