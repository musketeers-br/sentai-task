# Data Model: Scheduled Runs That Execute

## 1. Persistent

**`sentai.model.Schedule`** (new; one per scheduled flow)

| Property | Type | Rule |
|---|---|---|
| `flow` | `sentai.model.Flow` | required, unique |
| `kind` | `daily \| weekly \| monthly \| hourly` | required |
| `days` | `%List` of 1–7 (Mon=1) | weekly: ≥ 1 |
| `dayOfMonth` | integer 1–31 | monthly: required |
| `everyHours` | integer 1–12 | hourly: required |
| `startTime` | `HH:MM` | required, 00:00–23:59 |
| `runAs` | string (user name) | required |
| `targets` | `%List` of target names | the flow's remote targets at scheduling time |
| `taskId` | integer | the platform task id |
| `generation` | integer | increases with every schedule/renew; names its secrets |
| `nextRun` | `%TimeStamp` | last value read from the platform (plan D-8) |
| `createdBy`, `createdAt`, `updatedAt` | | |

No password, token or secret value is ever a property.

**`sentai.model.Run.trigger`** (new): `manual` (initial value) or `scheduled`.

**`sentai.model.Flow.scheduleSpec`** (exists): now the schedule in words, or "" when not scheduled.

## 2. Timing (pure, `sentai.schedule.Timing`)

`Validate(schedule) → errors[]` (field, message) · `ToTaskFields(schedule) → %DynamicObject` (the
table of research R-2, confirmed in T001) · `Describe(schedule) → string` (words as in plan D-7).

## 3. Wallet

- Collection `SentaiTask`: `UseResource = SentaiSchedule`, `EditResource = SentaiSchedule`.
  Created by the installer; the resource `SentaiSchedule` too (no role receives it by default:
  the administrator grants `SentaiSchedule:U` to run-as accounts and `SentaiSchedule:W`/`U` to
  operators who schedule; the README documents this).
- Secret per (flow, generation, instance): `flow-<flowId>-g<generation>-<primary|target>`,
  holding the run-as user name and password (form per T001), with allowed hosts restricted to that
  instance when the wallet supports it.

## 4. Start-failure run

`Run { state: failed, trigger: scheduled, dispatchedBy: <runAs>, startedAt = finishedAt, steps: 0 }`
plus one `LogEntry { severity: error, message: "Scheduled run could not start: <reason>" }`,
where `<reason>` is one of:
- `could not read the stored credential for <instance>: <platform text>`
- `could not sign in to <instance>: HTTP <status> <platform text>`
- `the flow does not validate: <code> <message>; …` (every error of the report)

## 5. Frontend

```ts
type ScheduleKind = 'daily' | 'weekly' | 'monthly' | 'hourly';
interface ScheduleForm { kind: ScheduleKind; days: number[]; dayOfMonth: number | null; everyHours: number | null;
  startTime: string; runAs: string; password: string; targetPasswords: Record<string, string>; }
interface ScheduleView { scheduled: boolean; describe: string; runAs: string; nextRun: string | null;
  targets: string[]; lastRun: { guid: string; state: RunState; startedAt: string } | null; }
```
