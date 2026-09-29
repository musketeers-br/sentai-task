<!-- lang: en | target: community.intersystems.com | status: draft | published: -->
# SentaiTask: orchestrating InterSystems IRIS maintenance as flows, not lists

Every IRIS administrator has a runbook in their head: switch the journal, check the integrity of
the big databases, look at free disk, purge old task history, and do not start the heavy part if
the instance is already in trouble. The Task Manager schedules each of those jobs one at a time.
The order, the dependencies and "what happens if one fails" stay in someone's memory.

**SentaiTask turns that runbook into a flow.** You compose maintenance steps on a canvas, connect
them, and run them: steps run in parallel waves, converge at join points, and can run on other
IRIS servers. Every step is followed live, keeps its result, and the platform decides every
permission. We built it for the InterSystems "Build Your Own Management Portal" contest, and it is
the only entry whose core is orchestration rather than a list of screens.

![SentaiTask running a flow: checks on two servers converge on a join](https://raw.githubusercontent.com/musketeers-br/sentai-task/master/assets/media/sentai-run.gif)

## How a flow runs

A flow is a small graph. The picture above is the showcase flow that ships with the public demo:
integrity checks of two databases on the primary and one on a second server start together, and
an "all must succeed" join releases the database size report only when all three completed.

1. **Validate.** Before anything runs, SentaiTask checks the flow against the live instance:
   cycles, unknown or unavailable step types, missing parameters, namespaces that do not exist,
   Work Queue Manager categories the platform does not have, read-only databases. Findings land on
   the node they concern.
2. **Run now.** The canvas asks for your password once, signs in to the platform's management API
   for the run, and dispatches. Each step becomes a platform job with its own identifier, queued in
   the Work Queue Manager category you chose, so the platform's own worker limits apply.
3. **Watch.** Each node shows its state (queued, running, completed, failed, cancelled), its
   elapsed time, where it runs, and the platform's failure reason word for word. A failed step
   can be re-run on its own; a join keeps its successor from starting when an input failed, and
   says which one.
4. **Keep the evidence.** Every run writes its own log: who dispatched it, each step starting and
   finishing, a target that stopped answering, who asked to cancel, and the outcome. A *Runs*
   screen finds any past run by flow and outcome, and *Export* saves it as a file.
   <!-- after 012 merge -->

The step types are a closed, declared catalog. An operator never types code: each type names a
class in the source tree and the schema of the parameters it takes, and the inspector builds its
form from that schema ([declared step types](https://github.com/musketeers-br/sentai-task#declared-step-types)).

## The six areas

The contest asks for a management portal. We cover each area as something a flow can do, so the
areas work together instead of sitting on separate pages.

| Area | In SentaiTask |
|---|---|
| Task management | Flows of tasks with dependencies and joins, live tracking, cancel and re-run per step; the native Task Manager as a catalog with filters, suspend and resume |
| Operating system | Free disk per database and journal directory (Embedded Python) and the size of every database, as steps |
| Work Queue Manager | Every step runs in a WQM category you pick; categories can be read and edited |
| Logs and monitoring | A log per run; a *System alerts check* step that gates a flow on the platform's serious alerts and resource statuses <!-- after 013 merge --> |
| Security and permissions | A *Security posture report* step: accounts holding %All, services open to unauthenticated connections, auditing off <!-- after 013 merge --> |
| Web applications and secrets | A web application inventory (anonymous REST endpoints are findings) and an IRIS Wallet inventory that lists names, never values <!-- after 013 merge --> |

Because they are steps, you can build a nightly flow that refuses to start heavy maintenance on an
instance with serious alerts, and runs the same security review on every server you manage.

## Distributed work (DPI-I-588)

The InterSystems Ideas portal has an idea for a distributed work manager,
[DPI-I-588](https://ideas.intersystems.com/ideas/DPI-I-588): dispatch work to other instances and
follow it from one place. SentaiTask implements it with nothing installed on the other side.

You register a **target server** (an address), and any step whose type runs through the
management API can be set to *Run on* that target. At *Run now*, the canvas asks for your password
on each target; the primary signs in to the target's own management API with the same user name
and keeps only that run's tokens, in a temporary global that is erased when the run ends. The
run view says where each step ran and as whom, and a target that stops answering is retried
without holding the rest of the run
([how it works](https://github.com/musketeers-br/sentai-task#-implements-dpi-i-588-distributed-work-manager)).

## Security by delegation

A tool that runs privileged maintenance must not become a way around the platform's security.
Our rule is simple: **the platform decides every permission, at the moment of use.**

- Every call to the platform uses the operator's own credential. SentaiTask keeps no copy of the
  permission model and never guesses from a previous success.
- When the platform refuses, the operator sees the platform's own words, unchanged.
- Destructive steps ask you to type the database or namespace they act on before the run starts.
- Before a cancel that makes IRIS record an alert, the dialog says so, and why.
- The public demo runs behind a proxy that exposes only the canvas and the management API calls
  it makes; the privileged accounts use a host secret, and visitors sign in with a least-privilege
  demo account whose limits we measured one platform refusal at a time
  ([the demo role](https://github.com/musketeers-br/sentai-task/blob/master/specs/011-demo-readiness/evidence/t001-demo-role.md)).

## How it was built

SentaiTask is an ObjectScript backend over the IRIS management API (`/api/admin`), with a canvas
(SvelteKit and Svelte Flow) that IRIS serves itself. We are a team of three and we built it
spec first: every feature has a specification, a plan, tasks and evidence recorded against a real
IRIS 2026.2 instance, all in the repository
([specs](https://github.com/musketeers-br/sentai-task/tree/master/specs)).

Our constitution fixes six principles: layered architecture, a closed capability set, delegated
authorization, errors as values, verifiable increments and technology agnosticism. Tests come
first. Today the backend has more than 300 unit tests, the canvas more than 180, and more than
80 end-to-end scenarios run in a real browser against the container. We also keep a list of
known limitations, because a maintenance tool should say what it does not do yet
([limitations](https://github.com/musketeers-br/sentai-task/blob/master/docs/limitations.md)).

Writing the tests against a real instance found real problems. One example: `at` and `Join` are
SQL reserved words in IRIS, and two queries that used them unquoted failed silently. The tests
caught both before any user did.

## Try it

- **Public demo**: the address is in the README's *Try it* section. Sign in as `sentai-demo`,
  open *Showcase: nightly checks across servers* and choose *Run now*. The demo is reset every day.
- **On your machine**: clone the repository and run `docker compose up -d --build`. The README
  shows the whole quickstart
  ([Try it](https://github.com/musketeers-br/sentai-task#-try-it)).
- **The package**: [SentaiTask on Open Exchange](https://openexchange.intersystems.com/package/sentai-task).

If a flow that validates, runs in waves, spans servers and explains itself is how you want to run
IRIS maintenance, please try it, tell us what is missing, and **vote for SentaiTask** in the contest
this week. Thank you!

*The Musketeers: José Roberto Pereira, Henry Pereira and Henrique Dias.*
