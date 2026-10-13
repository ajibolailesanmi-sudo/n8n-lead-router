-- Lead Router database schema
-- Safe to run more than once: every statement uses IF NOT EXISTS or OR REPLACE.
-- Docker applies this automatically on first start. Workflow "00 - Setup & Connection Check"
-- runs the same statements, which is how you set it up on a hosted Postgres such as Supabase.

-- 1. Idempotency keys: one row per incoming event, claimed atomically.
CREATE TABLE IF NOT EXISTS processed_events (
  idem_key        text PRIMARY KEY,
  source          text NOT NULL,
  source_event_id text,
  lead_id         uuid,
  status          text NOT NULL DEFAULT 'processing'
                  CHECK (status IN ('processing', 'done', 'rejected')),
  attempts        integer NOT NULL DEFAULT 1,
  first_seen_at   timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- 2. Round-robin state: when each rep last received a lead.
CREATE TABLE IF NOT EXISTS rep_rotation (
  rep_id           text PRIMARY KEY,
  last_assigned_at timestamptz,
  assigned_count   integer NOT NULL DEFAULT 0
);

-- 3. Audit log: one row per event, written by every path through the router.
CREATE TABLE IF NOT EXISTS lead_log (
  id              bigserial PRIMARY KEY,
  logged_at       timestamptz NOT NULL DEFAULT now(),
  event           text NOT NULL
                  CHECK (event IN ('routed', 'unassigned', 'duplicate_dropped', 'rejected', 'error')),
  lead_id         uuid,
  idem_key        text,
  source          text,
  source_event_id text,
  email           text,
  company         text,
  score           integer,
  priority        text,
  pool            text,
  route_type      text,
  rep_id          text,
  rep_name        text,
  reason          text,
  crm_contact_id  text,
  crm_is_new      boolean,
  details         jsonb,
  workflow_name   text,
  execution_id    text
);
CREATE INDEX IF NOT EXISTS lead_log_logged_at_idx ON lead_log (logged_at DESC);
CREATE INDEX IF NOT EXISTS lead_log_email_idx ON lead_log (email);
CREATE INDEX IF NOT EXISTS lead_log_source_event_idx ON lead_log (source_event_id);

-- 4. Results written by the "99 - Test Runner" workflow.
CREATE TABLE IF NOT EXISTS test_results (
  id        bigserial PRIMARY KEY,
  run_id    text NOT NULL,
  test_id   text NOT NULL,
  title     text,
  expected  text,
  actual    text,
  passed    boolean NOT NULL,
  ran_at    timestamptz NOT NULL DEFAULT now()
);

-- 5. Reporting views (handy for screenshots and the Loom walkthrough).
CREATE OR REPLACE VIEW v_lead_activity AS
SELECT logged_at, event, source, email, company, score, priority, pool,
       route_type, rep_name, reason, crm_contact_id, execution_id
FROM lead_log
ORDER BY logged_at DESC;

CREATE OR REPLACE VIEW v_rep_load AS
SELECT rep_id, rep_name, pool,
       count(*) AS leads_assigned,
       max(logged_at) AS last_assigned_at
FROM lead_log
WHERE event = 'routed' AND rep_id IS NOT NULL
GROUP BY rep_id, rep_name, pool
ORDER BY pool, rep_id;

CREATE OR REPLACE VIEW v_daily_summary AS
SELECT (logged_at AT TIME ZONE 'America/New_York')::date AS day,
       count(*) FILTER (WHERE event = 'routed')            AS routed,
       count(*) FILTER (WHERE event = 'unassigned')        AS unassigned,
       count(*) FILTER (WHERE event = 'duplicate_dropped') AS duplicates_dropped,
       count(*) FILTER (WHERE event = 'rejected')          AS rejected,
       count(*) FILTER (WHERE event = 'error')             AS errors
FROM lead_log
GROUP BY 1
ORDER BY 1 DESC;

CREATE OR REPLACE VIEW v_latest_test_run AS
SELECT test_id, title, passed, expected, actual, ran_at
FROM test_results
WHERE run_id = (SELECT run_id FROM test_results ORDER BY ran_at DESC LIMIT 1)
ORDER BY test_id;
