# Test Protocol

How the Lead Router is verified against the acceptance criteria in the [project brief](01-project-brief.md). Results are recorded in [`tests/test-protocol.xlsx`](../tests/test-protocol.xlsx).

## Approach

Two kinds of test, because they prove different things:

- **Automated (22 checks):** workflow **99 - Test Runner** sends 23 requests to the live webhook, waits for processing, reads the audit log and compares what happened with the expected result for each case. It is repeatable: every run tags its leads with a new run ID, so earlier runs never interfere. Results are saved in the `test_results` table.
- **Manual (11 tests):** the things a script cannot judge or should not change on its own: the form in a real browser, the sheet source, rep availability, scoring edits, deliberate outages and recovery, and what the HubSpot record actually looks like.

## Before you start

- [ ] Setup guide completed and **00 - Setup & Connection Check** shows all PASS
- [ ] 03, 02 and 01 are published
- [ ] Every rep in the `reps` tab has `available = TRUE`
- [ ] `scoring_rules` matches the defaults (R07 is 15 points)
- [ ] Adminer open at http://localhost:8080 on the `lead_router` database

The test leads create real contacts in your HubSpot demo account, messages in your Slack workspace and a few emails to your rep addresses. All test emails use `example.com` domains or plus-addressing, so nothing reaches a real person. Delete the test contacts in HubSpot afterwards if you like.

## Running the automated suite

1. Open **99 - Test Runner** and click **Execute workflow**. It takes about 2 minutes.
2. Open **Test Summary**. It shows `ALL 22 TESTS PASSED`, or lists each failure with expected and actual values.
3. In Adminer, open the view `v_latest_test_run` for the full table. Copy the results into the **Automated** tab of the workbook.

If a test shows "No result logged yet", the lead was still processing or its run failed. Check **02 - Process Lead > Executions**, then rerun, or raise `wait_seconds` in the **Test Settings** node.

## Automated tests

| ID | Scenario | Input | Expected result | Criteria |
|---|---|---|---|---|
| TC-01 | Clean lead in an East state is routed by territory | Massachusetts dental group, 35 staff, $8,000, Managed IT, 1-3 months | routed; Cold; score 35; pool east; route territory; email lowercased; phone +16175550101; state MA; size 11-50; budget $5k-$15k | AC-01 |
| TC-02 | Lead in a West state goes to the West pool | Oregon brewery, 11-50 staff, $15k-$50k, Cybersecurity, 3-6 months | routed; Warm; score 50; pool west; route territory | AC-01 |
| TC-03 | Hot lead goes to Enterprise regardless of territory | Illinois health group, 450 staff, $75,000, Cloud Migration, ASAP, VP | routed; Hot; score 105; pool enterprise; route score; size 201-1000; budget $50k+ | AC-01 |
| TC-04 | Messy input is cleaned | Spaces, lowercase names, 'new york', 'u.s.', phone with extension, '8' staff, 'under 5k', 'managed it', 'asap' | routed; names Liam / O'Connor; email lowercased and trimmed; phone +12125550104; state NY; country US; size 1-10; budget Under $5k; service Managed IT Support; timeline ASAP | AC-01 |
| TC-05 | Free email domain gets no business-email points | Gmail address, owner of a 5-person firm, $5k-$15k, Microsoft 365 | routed; Cold; score 35; email_type free | AC-01 |
| TC-06 | Lead outside the US goes to the Sales Manager | French company, no state, 51-200 staff, Director | routed; Warm; score 60; pool manager; route no_territory; rep Rachel Kim; phone +33142685300 | AC-01 |
| TC-07 | Second Hot lead rotates to the other Enterprise rep | Georgia logistics, 1000+ staff, $50k+, CTO | routed; Hot; score 115; pool enterprise; route score (balance across Enterprise reps is checked in TC-21) | AC-04 |
| TC-08 | East lead for round-robin balance | New Jersey CPA firm, 11-50 staff | routed; Cold; score 35; pool east | AC-04 |
| TC-09 | Budget range uses its midpoint | Budget '10000-20000' | routed; Warm; score 55; pool east; budget $15k-$50k | AC-04 |
| TC-10 | West lead for round-robin balance | Arizona clinic, Cybersecurity, ASAP | routed; Warm; score 55; pool west | AC-04 |
| TC-11 | Missing email is rejected for review | No email | rejected; reason 'Missing email' | AC-03 |
| TC-12 | Invalid email format is rejected | Email without an @ | rejected; reason starts 'Invalid email format' | AC-03 |
| TC-13 | Several missing fields are all reported | No company, no service interest | rejected; reason 'Missing company; Missing service interest' | AC-03 |
| TC-14 | Same webhook delivered 3 times at once | Same event_id sent 3 times in parallel | exactly 1 routed and 2 duplicate_dropped | AC-02 |
| TC-15 | Repeat delivery without an event ID | Identical payload with the same submitted_at, sent twice | 1 routed and 1 duplicate_dropped | AC-02 |
| TC-16 | Returning contact keeps the same rep | Same email as TC-01, new event 20 seconds later | routed; route returning; same rep as TC-01; crm_is_new false (HubSpot updated the existing contact) | AC-01, AC-02 |
| TC-17 | Wrong API key is refused | X-API-Key: wrong value | HTTP 401 or 403; nothing logged | AC-09 |
| TC-18 | SQL and HTML in input are stored as plain text | Company "Robert'); DROP TABLE lead_log;--", message with a script tag | routed; Cold; score 15; company stored exactly as sent; warning that it was kept out of HubSpot | AC-01 |
| TC-19 | Full name field is split | name 'Chloe Anne Ramirez', budget '25k', Head of IT | routed; Hot; score 90; first name Chloe; last name Anne Ramirez; budget $15k-$50k | AC-01 |
| TC-20 | Unknown state is flagged and still reaches a person | state 'Narnia', country US | routed; Warm; score 45; pool manager; rep Rachel Kim; warning 'Unknown US state' | AC-03 |
| TC-21 | Round-robin keeps every pool balanced | All rotated leads in the run | east, west and enterprise each split across 2 reps, difference of 1 at most | AC-04 |
| TC-22 | Webhook acknowledges every valid delivery with 202 | All 22 valid requests in the run | 22 of 22 requests return 202 Accepted | AC-06 |

## Manual tests

Run these in order. M-03 to M-07 change settings on purpose; put each one back before moving on.

| ID | Scenario | Steps | Expected result | Criteria |
|---|---|---|---|---|
| M-01 | Web form submission end to end | Open http://localhost:5678/form/contact-sales in a browser. Submit a Hot lead with an email you have not used before (for example m01.yourname@formtest.example.com): 201-1000 employees, $50k+, Cybersecurity, ASAP, job title CTO. | Thank-you message shows. Within 60 seconds: #leads message assigning an Enterprise rep, HubSpot contact with the Lead Router properties filled in, hot-lead email in that rep's inbox, lead_log row with event routed and source form. | AC-01, AC-06 |
| M-02 | Google Sheet intake | Copy the 3 rows from the sample_rows tab into the intake tab, leaving status blank. If you have pasted these rows before, change added_at on each one first. Wait up to 3 minutes. | Grace Holloway: routed to an East rep (Warm, score 65). Tom Brennan: routed to a West rep (Warm, score 45). Lena Fischer: rejected, 'Missing email', plus a review alert in #lead-alerts. status, routed_to and processed_at are filled in on every row. | AC-03, AC-06 |
| M-03 | A rep marked unavailable is skipped | In the reps tab set Maya Chen's available to FALSE. Run the 'Send one test lead' command twice with TEST=m03. Afterwards set Maya back to TRUE. | Both leads go to Daniel Okafor. | AC-05, AC-08 |
| M-04 | A pool with nobody available falls back to the manager | Set Maya Chen and Daniel Okafor to FALSE. Run the 'Send one test lead' command with TEST=m04. Afterwards set both back to TRUE. | Routed to Rachel Kim; routing reason mentions 'no available reps in the east pool'. | AC-05 |
| M-05 | Scoring change takes effect without editing n8n | In scoring_rules set R07 (ASAP) points to 40. Run the 'M-05 scoring lead' command (Oregon, 11-50 staff, $25,000, Cybersecurity, ASAP, business email, no job title). Afterwards set R07 back to 15. | Score 90 instead of 65; priority Hot; routed to the Enterprise pool; Slack shows 'Buying now +40'. | AC-08 |
| M-06 | CRM failure raises an alert and recovers cleanly | Edit the 'Lead Router - HubSpot' credential and change one character of the key. Run the 'Send one test lead' command with TEST=m06. After the alert arrives, restore the key, open the failed execution from the alert link and click Retry. | Within 1 minute: alert in #lead-alerts and by email naming the failed HubSpot step, with a link to the execution. After Retry: execution succeeds, exactly 1 HubSpot contact, 1 #leads message, 1 routed row in lead_log. | AC-07, AC-01, AC-02 |
| M-07 | Alerts still arrive when Slack is down | Edit the 'Lead Router - Slack' credential and break the token. Run the 'Send one test lead' command with TEST=m07. Then restore the token and retry the failed execution. | Notify in Slack fails after 3 attempts; the failure email still arrives; after Retry the #leads message posts once. | AC-07 |
| M-08 | HubSpot record is complete and a partial resubmission loses nothing | Open the M-01 contact in HubSpot. Then run the 'M-08 partial resubmission' command with the email, first name and company you used in M-01. | Lead Router group shows score, priority, assigned rep, routing reason and source. After the resubmission the phone and job title are unchanged and the contact keeps the same rep (returning contact). | AC-01 |
| M-09 | Audit trail links every lead to its execution | In Adminer open the view v_lead_activity. Copy the execution_id of any row. In n8n open 02 - Process Lead > Executions and find that ID. | Every test event has one row; the execution opens and shows the lead's path through the workflow. | AC-03, AC-07 |
| M-10 | Webhook without an API key is refused | Run the 'M-10 no API key' command. | HTTP 403; no lead_log row for that event. | AC-09 |
| M-11 | A burst of simultaneous leads stays balanced | Run the command in the setup guide's 'Load check' section, which sends 12 New York leads at the same instant and prints a run number. Then run the SQL query shown there in Adminer with that run number. | All 12 routed; split 6 and 6 between Maya Chen and Daniel Okafor; no failed executions. | AC-04 |

## Commands for the manual tests

Run these in Terminal. They use the `KEY` variable from Part I of the setup guide, so run `export KEY=your-webhook-key` first in any new Terminal window. Each command creates a new lead with its own event ID and email, so you can run it as often as you like.

### Send one test lead (M-03, M-04, M-06, M-07)

Set `TEST` to the test you are running (`m03`, `m04`, `m06` or `m07`), then run:

```bash
TEST=m03
ID=$TEST-$(date +%s)-$RANDOM
curl -s -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
  -w '\nHTTP %{http_code}\n' \
  -d "{\"event_id\":\"$ID\",\"first_name\":\"Test\",\"last_name\":\"$TEST\",\"email\":\"$ID@testlead.example.com\",\"company\":\"Test Co $TEST\",\"state\":\"NY\",\"country\":\"US\",\"service_interest\":\"Managed IT Support\"}"
```

### M-05 scoring lead

```bash
ID=m05-$(date +%s)-$RANDOM
curl -s -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
  -w '\nHTTP %{http_code}\n' \
  -d "{\"event_id\":\"$ID\",\"first_name\":\"Score\",\"last_name\":\"Check\",\"email\":\"$ID@scorecheck.example.com\",\"company\":\"Score Check Co\",\"state\":\"OR\",\"country\":\"US\",\"company_size\":\"11-50\",\"budget\":\"25000\",\"service_interest\":\"Cybersecurity\",\"timeline\":\"ASAP\"}"
```

### M-08 partial resubmission

Fill in the three values you used in M-01, then run:

```bash
EMAIL=the-email-you-used-in-m01@formtest.example.com
FIRST=TheFirstNameYouUsed
COMPANY="The Company You Used"
ID=m08-$(date +%s)-$RANDOM
curl -s -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
  -w '\nHTTP %{http_code}\n' \
  -d "{\"event_id\":\"$ID\",\"first_name\":\"$FIRST\",\"email\":\"$EMAIL\",\"company\":\"$COMPANY\",\"service_interest\":\"Cybersecurity\"}"
```

### M-10 no API key

```bash
ID=m10-$(date +%s)-$RANDOM
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d "{\"event_id\":\"$ID\",\"first_name\":\"No\",\"last_name\":\"Key\",\"email\":\"$ID@nokey.example.com\",\"company\":\"No Key Co\",\"service_interest\":\"Other\"}"
echo "In Adminer, this should return no rows: SELECT * FROM lead_log WHERE source_event_id = '$ID';"
```

## Traceability

| Criterion | Description | Proved by |
|---|---|---|
| AC-01 | Each valid lead creates or updates exactly one HubSpot contact | TC-01, TC-16, M-01, M-06, M-08 |
| AC-02 | A repeated delivery creates no extra contacts, Slack messages or emails | TC-14, TC-15, TC-16, M-06 |
| AC-03 | Each invalid lead produces one log row and one review alert, never a silent drop | TC-11, TC-12, TC-13, TC-20, M-02 |
| AC-04 | Available reps in a pool receive leads evenly (difference of 1 at most) | TC-07, TC-21, M-11 |
| AC-05 | A rep marked unavailable receives no new leads | M-03, M-04 |
| AC-06 | The rep is notified within 60 s (form, webhook) or 3 min (sheet) | TC-22, M-01, M-02 |
| AC-07 | A failed run raises an alert within 1 minute with a link to the execution | M-06, M-07, M-09 |
| AC-08 | Scoring points and rep availability change in the sheet without editing n8n | M-03, M-05 |
| AC-09 | Webhook calls without the correct API key are rejected | TC-17, M-10 |

The **Traceability** tab of the workbook pulls each test's result automatically and marks every criterion Met, Not met or Pending.

## Recording results

- Fill in the yellow cells on the **Automated** and **Manual** tabs: actual result, PASS or FAIL, evidence file, tester and date.
- Save one screenshot per manual test under the evidence file name given in the workbook.
- The **Summary** tab totals everything and shows the overall status. When it reads **ALL PASSED**, fill in the run details at the top and export a PDF copy for the repo.

## Results

| Run | Date | Automated | Manual | Criteria met | Notes |
|---|---|---|---|---|---|
| tvn5j2y (n8n Cloud) | 2026-10-05 | 18 / 22 | | | Google Sheets read quota (60 per minute) throttled Read Reps for 4 leads in the burst. Fixed: one batchGet call per lead |
| tvnqf1j (n8n Cloud) | 2026-10-05 | 21 / 22 | | | TC-18: HubSpot's firewall answered 403 to the injection test lead. Fixed: code-like text is kept out of HubSpot with a warning |
| tvo47hy (n8n Cloud) | 2026-10-05 | 22 / 22 | 10 / 11 (M-07 not run) | 8 / 9 (AC-07 waits on M-07) | After both fixes. Results in `tests/test-protocol.xlsx` |
