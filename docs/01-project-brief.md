# Project Brief: Lead Routing Automation for a B2B IT Services Firm

> **Demo build by Solvant Labs.** The firm in this brief is a sample scenario, not a client. The workflows, database, tests and documentation are real. They were tested end to end on n8n Cloud with a Neon Postgres database, and the repo's Docker Compose stack runs the same build self-hosted.

## 1. Background

The firm sells managed IT support, cybersecurity and cloud services to US businesses with 10 to 1,000 employees. New leads arrive from three places:

- The "Contact Sales" form on the website
- Partner and landing-page integrations that post leads by webhook
- A shared Google Sheet where the team logs leads from events and phone calls

Today a coordinator copies each lead into HubSpot by hand and messages a rep. That causes duplicate contacts, slow follow-up, uneven distribution across reps, missed leads whenever the coordinator is out, and no record of who received which lead.

## 2. Goal

Every lead is captured, cleaned, scored, assigned to the right rep, created or updated in HubSpot and announced to that rep within one minute, with no manual steps and a complete audit trail.

## 3. Scope

| In scope | Out of scope (can be added later) |
|---|---|
| Three lead sources: web form, webhook, Google Sheet | Paid data enrichment (Clearbit, Apollo and similar) |
| Validation, cleaning and duplicate prevention | Nurture sequences and follow-up emails to the lead |
| Configurable lead scoring | WhatsApp alerts (need Meta Business verification first) |
| Round-robin, territory and score-based routing | Reporting dashboards |
| HubSpot create or update, Slack and email alerts | |
| Logging, retries, error alerts, documentation and tests | |

## 4. Lead sources

| Source | How it arrives | Basis for the duplicate check |
|---|---|---|
| Website form | n8n-hosted form | Email plus the form's submission timestamp |
| Webhook | `POST /webhook/lead-intake` with an `X-API-Key` header | `event_id` in the body or `X-Event-Id` header, otherwise a hash of the payload |
| Google Sheet | `intake` tab, checked every 2 minutes | Email plus the row's `added_at` value |

## 5. Standard lead record

Every source is mapped into one shape before any logic runs, so adding a fourth source later is a mapping step, not a rebuild.

| Field | Notes |
|---|---|
| `source`, `source_event_id`, `submitted_at` | Where and when the lead came from |
| `first_name`, `last_name`, `email`, `phone` | Contact details |
| `company`, `job_title` | Company details |
| `state`, `country` | Used for territory routing |
| `company_size`, `budget`, `service_interest`, `timeline` | Used for scoring |
| `message` | Free text from the lead |

## 6. Validation and cleaning

**Required:** first name, a valid email, company and service interest.

**Cleaning applied to every lead:**

- Trim spaces, lowercase the email, capitalize names properly
- Phone numbers converted to international format (US by default), for example `(415) 555-0134` becomes `+14155550134`
- State names or abbreviations converted to the 2-letter code (`california`, `Calif.` and `CA` all become `CA`)
- Company size and budget converted to standard bands (`35` becomes `11-50`, `25k` becomes `$15k-$50k`)
- Free email domains (Gmail, Yahoo, Outlook and similar) are flagged, since this is a B2B business

**Invalid leads are never dropped silently.** Each one is logged with the reasons it failed and posted to `#lead-alerts` for a person to review.

## 7. Duplicate prevention

Two layers:

1. **Event level.** Each incoming lead gets an idempotency key, a SHA-256 hash of its source plus event ID (or the fallback in section 4). The key is claimed in Postgres with a unique index, so if the same webhook arrives twice, even in the same second, exactly one copy is processed and the other is logged as a dropped duplicate. A key stuck in "processing" for more than 15 minutes can be claimed again, so a crashed run never blocks a lead for good.
2. **Contact level.** HubSpot contacts are created or updated by email in one call, so one person never becomes two contacts, even if they submit through two different sources.

## 8. Lead scoring

Scoring rules live in the `scoring_rules` tab of the config sheet. The sales team can change points or switch rules on and off without touching n8n.

| Rule | Points |
|---|---|
| Company size 51-1,000 employees | +20 |
| Company size 1,000+ employees | +30 |
| Budget $5k-$15k / $15k-$50k / $50k+ | +10 / +20 / +30 |
| Interested in Cybersecurity or Cloud Migration | +15 |
| Timeline ASAP / 1-3 months | +15 / +10 |
| Business email address | +10 |
| Decision-maker job title (Owner, CEO, CTO, VP, Director and similar) | +10 |
| Based in the US | +5 |

**Priority:** Hot is 70 or more, Warm is 40 to 69, Cold is below 40.

## 9. Routing rules

Applied in this order:

1. **Returning contact:** goes back to the rep who had it before, if that rep is available.
2. **Hot lead:** goes to the Enterprise pool.
3. **Territory:** US state decides the East or West pool (the `territories` tab).
4. **No territory** (outside the US or no state given): goes to the Sales Manager.
5. **Nobody available in the pool:** goes to the Sales Manager. If the manager is unavailable too, the lead is still created in HubSpot, marked unassigned, and an alert is posted.

Inside a pool, leads go round-robin to the available rep who was assigned least recently. Rotation state is stored in Postgres, not inside the workflow, so it survives restarts and stays fair when two leads arrive at once. A rep marked `available = FALSE` in the `reps` tab is skipped.

## 10. CRM: HubSpot

- Contacts are created or updated by email (upsert)
- Standard fields: name, email, phone, company, job title, state, country
- A "Lead Router" property group holds score, priority, assigned rep, routing reason, source, service interest, company size, budget and timeline
- Blank values are never sent, so a sparse resubmission cannot wipe existing data

## 11. Notifications

| Channel | When |
|---|---|
| Slack `#leads` | Every routed lead, mentioning the assigned rep |
| Email to the rep | Hot leads only |
| Slack `#lead-alerts` | Rejected leads, unassigned leads and workflow failures |
| Email to operations | Workflow failures |

## 12. Logging and error handling

- **Audit log:** every event (routed, duplicate dropped, rejected, error) is written to a `lead_log` table with the n8n execution ID, so any lead can be traced end to end.
- **Retries:** every call to HubSpot, Slack, Google Sheets and Postgres is tried up to 3 times, with a pause between attempts.
- **Error workflow:** if a run still fails, an alert with the workflow name, failed step, error message and a link to the execution goes to Slack and email.
- **Recovery:** fix the cause, then retry the execution from n8n. Because every write is idempotent, a retry cannot create duplicates.

## 13. Acceptance criteria

| ID | Criterion |
|---|---|
| AC-01 | Each valid lead creates or updates exactly one HubSpot contact |
| AC-02 | A repeated delivery of the same lead creates no extra contacts, Slack messages or emails |
| AC-03 | Each invalid lead produces one log row and one review alert, and is never silently dropped |
| AC-04 | Within a pool, available reps receive leads evenly (a difference of 1 at most across a test batch) |
| AC-05 | A rep marked unavailable receives no new leads |
| AC-06 | The assigned rep is notified within 60 seconds for form and webhook leads, and within 3 minutes for sheet leads |
| AC-07 | A failed run raises an alert within 1 minute, with a link to the failed execution |
| AC-08 | Scoring points and rep availability can be changed in the sheet without editing n8n |
| AC-09 | Webhook calls without the correct API key are rejected |

## 14. Deliverables

- Four n8n workflows: Setup, Intake, Process Lead and Error Handler, plus an automated Test Runner
- Docker setup for n8n, Postgres and a database viewer
- Config sheet template (reps, scoring rules, territories, intake)
- Setup guide, design walkthrough, test protocol with recorded results, and a Loom walkthrough
