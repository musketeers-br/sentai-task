# Quickstart: Area Report Steps

On the dev stack with `iris-target` up, after `LoadDir` of `src` and publishing the canvas.

## 1. Catalog

```bash
TOKEN=$(curl -s -u _SYSTEM:SYS -X POST localhost:52773/api/admin/login -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)
curl -s -H "Authorization: Bearer $TOKEN" localhost:52773/csp/sentai/api/v1/catalog/step-types \
  | jq '.[] | select(.executor=="platform-read") | {type,category,remoteCapable,available}'
```

Four entries, all `remoteCapable: true`, `available: true`.

## 2. On the canvas

1. New flow "qs013 area checks". From *Security* drag **Security posture report**, **Web
   application inventory** and **Secrets inventory**; from *Monitoring* drag **System alerts
   check**. Duplicate the four with *Run on* = `iris-target`.
2. *Validate flow* → 0 errors. *Run now* (with the target password).
3. Each node ends `completed` or `failed`. **System alerts check** fails on an instance that had
   alerts since it started (the dev instance usually has), with the reason naming the threshold.
   That is a real finding (research R-4).
4. Click **Result** on the security report: the summary counts by severity, then the findings
   (`ALL_ROLE_HOLDER _SYSTEM`, `SuperUser`, …), then accounts and services. On the web
   application inventory: `/csp/sentai` is a *medium* finding and `/csp/sentai/api/v1` is a REST
   endpoint that requires a password. Click **Result** on a **Database size report** of another
   flow: a readable tree (the existing step's result was never shown before).

## 3. Refused operator

Create an operator without security administration (the spec 011 demo role is one). Run the
security report as that operator: `failed` with `Administrative endpoint
/api/admin/v2/security/users returned HTTP 403: …` verbatim.

## 4. Gate

Flow: **System alerts check** → join → two integrity checks. On an instance with serious alerts
the integrity checks are not started, and the run log (spec 012) says which input failed. After
an instance restart (which clears the counter, if T001 confirms this), the flow runs to the end.

## 5. Secrets never stored

```bash
# after creating a collection and secret through the platform (T001 recipe)
curl -s -H "Authorization: Bearer $TOKEN" localhost:52773/csp/sentai/api/v1/runs/<guid> | grep -c '<the secret value>'   # 0
```
