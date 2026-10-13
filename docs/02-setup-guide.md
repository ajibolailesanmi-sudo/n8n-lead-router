# Setup Guide

This gets the Lead Router running on your own computer with Docker. It was written for a Mac with Apple Silicon and works the same on Intel Macs, Windows (with WSL2) and Linux.

**Time:** about 2 to 3 hours the first time, most of it creating the free accounts in Part C.

**What you end up with:**

| Service | Address | What it is |
|---|---|---|
| n8n | http://localhost:5678 | The workflow editor |
| Adminer | http://localhost:8080 | A simple viewer for the Postgres database |
| Web form | http://localhost:5678/form/contact-sales | The "Contact Sales" form |
| Webhook | http://localhost:5678/webhook/lead-intake | Where other systems send leads |

Everything runs locally and is bound to `127.0.0.1`, so nothing is reachable from outside your computer.

---

## Part A: Install Docker Desktop (10 minutes)

1. Download **Docker Desktop for Mac** from docker.com. Pick the **Apple chip** version on an M1, M2, M3 or M4 Mac.
2. Open the downloaded file, drag Docker to Applications, then open Docker from Applications.
3. Wait until the Docker whale icon in the menu bar says **Docker Desktop is running**.
4. Open **Terminal** and check it works:

   ```bash
   docker --version
   docker compose version
   ```

   Both commands should print a version number.

---

## Part B: Start n8n, Postgres and Adminer (15 minutes)

1. Unzip the project and move the `n8n-lead-router` folder somewhere permanent, for example `~/Projects/n8n-lead-router`.

2. In Terminal, go into the folder:

   ```bash
   cd ~/Projects/n8n-lead-router
   ```

3. Create your private settings file and open it:

   ```bash
   cp .env.example .env
   open -e .env
   ```

4. Generate the three secret values. Run this command and paste the result into `.env` as `POSTGRES_PASSWORD`:

   ```bash
   openssl rand -hex 16
   ```

   Run the same command again and paste the new result as `LEAD_ROUTER_DB_PASSWORD`. Then run this one and paste the result as `N8N_ENCRYPTION_KEY`:

   ```bash
   openssl rand -hex 32
   ```

   Save the file. Keep `.env` private; it is already excluded from Git.

   > **Fill in `.env` completely before the first start.** The first `docker compose up` creates the database with these passwords and locks in the encryption key. Changing them afterwards has no effect unless you erase everything with `docker compose down -v` and start again.

5. Start everything:

   ```bash
   docker compose up -d
   ```

   The first start downloads the images and can take a few minutes.

6. Check that all three services are up:

   ```bash
   docker compose ps
   ```

   You should see `postgres` (healthy), `n8n` and `adminer` running.

7. Open **http://localhost:5678** and create your n8n owner account. This account only exists on your computer.

8. Optional check of the database: open **http://localhost:8080** and log in with
   - System: **PostgreSQL**
   - Server: **postgres**
   - Username: **lead_router_app**
   - Password: your `LEAD_ROUTER_DB_PASSWORD`
   - Database: **lead_router**

   You should see the tables `lead_log`, `processed_events`, `rep_rotation` and `test_results`.

---

## Part C: Create the accounts and keys (60 to 90 minutes)

Keep a note open while you do this. You will collect six things:

| # | What | Used for |
|---|---|---|
| 1 | Slack bot token (starts with `xoxb-`) | Lead and alert messages |
| 2 | HubSpot service key | Creating and updating contacts |
| 3 | Google service account email and private key | Reading and updating the config sheet |
| 4 | Google Sheet ID | Telling n8n which sheet to use |
| 5 | Gmail app password | Hot-lead and failure emails |
| 6 | A webhook API key you make up | Protecting the webhook |

### C1. Slack

1. Create a free workspace at slack.com, for example "Lead Router Demo".
2. Create two channels: **#leads** and **#lead-alerts**.
3. Go to **api.slack.com/apps**, click **Create New App**, choose **From scratch**, name it **Lead Router** and pick your demo workspace.
4. Open **OAuth & Permissions**. Under **Bot Token Scopes**, add:
   - `chat:write`
   - `chat:write.public` (lets the bot post in public channels without being invited)
5. Scroll up, click **Install to Workspace**, then **Allow**.
6. Copy the **Bot User OAuth Token**. It starts with `xoxb-`.
7. Optional: to get @mentions in the lead messages, copy your own Slack member ID (click your profile picture, **Profile**, the three dots, **Copy member ID**). You will paste it into the `reps` tab later.

### C2. HubSpot

1. Sign up for the free HubSpot CRM at hubspot.com.
2. Create a service key: go to **Development > Keys > Service keys** (or **Settings > Account Management > Integrations > Service Keys**) and click **Create service key**.
3. Name it **Lead Router**, click **Add new scope** and tick these four:
   - `crm.objects.contacts.read`
   - `crm.objects.contacts.write`
   - `crm.schemas.contacts.read`
   - `crm.schemas.contacts.write`
4. Click **Update**, then **Create**. Open the key, click **Show**, then **Copy**.

> If your account does not show **Service keys**, create a legacy private app instead: **Development > Legacy apps > Create legacy app > Private**, add the same four scopes on the **Scopes** tab, click **Create app**, then copy the token from the **Auth** tab. It works the same way in n8n.

You also need your **Hub ID** later. Workflow 00 prints it for you, or you can copy it from your HubSpot address bar: it is the number after `app.hubspot.com/contacts/`.

### C3. Google service account

A service account is a robot Google user. You share the config sheet with it, and n8n uses its key to read and update the sheet.

1. Go to **console.cloud.google.com** and create a project, for example **lead-router-demo**.
2. Open **APIs & Services > Library**, search for **Google Sheets API** and click **Enable**.
3. Open **IAM & Admin > Service Accounts** and click **Create service account**. Name it **lead-router**, click **Create and continue**, skip the optional steps and click **Done**. No roles are needed.
4. Click the new service account, open the **Keys** tab, click **Add key > Create new key**, choose **JSON** and click **Create**. A `.json` file downloads.
5. Open that file in TextEdit. You need two values from it:
   - `client_email` (looks like `lead-router@lead-router-demo.iam.gserviceaccount.com`)
   - `private_key` (the long text between the quotes, starting with `-----BEGIN PRIVATE KEY-----`)

Keep the JSON file out of the project folder and never commit it.

### C4. The config Google Sheet

1. Upload `config/lead-router-config.xlsx` to Google Drive. (If you have the personal copy from the portfolio kit, upload that instead; its rep emails already point to your inbox.)
2. Double-click it in Drive and choose **Open with Google Sheets**, then **File > Save as Google Sheets**. Work in the Google Sheets copy from now on.
3. Check it has these tabs: `intake`, `reps`, `scoring_rules`, `territories`, `sample_rows` and `about`. Do not rename the tabs or the header rows.
4. In the `reps` tab, set every rep's email to an address you can read. Gmail plus-addressing works well: `yourname+maya@gmail.com`, `yourname+daniel@gmail.com` and so on all arrive in your normal inbox, and the To line shows which rep each email was for.
5. Optional: paste your Slack member ID into `slack_member_id` for any reps you want @mentioned.
6. Click **Share** and share the sheet with the service account's `client_email` as an **Editor**. Untick "Notify people".
7. Copy the **Sheet ID** from the address bar. It is the long part between `/d/` and `/edit`:
   `https://docs.google.com/spreadsheets/d/`**`THIS_PART`**`/edit`

### C5. Gmail app password

The router emails reps about Hot leads and emails you when a workflow fails. Tests M-01, M-06 and M-07 check those emails, so set this up if you want the full test protocol to pass.

1. Turn on **2-Step Verification** for your Google account if it is not on already.
2. Go to **myaccount.google.com/apppasswords**, create an app password named **n8n lead router** and copy the 16-character code.

If you decide to skip email anyway, open workflows 02 and 03 later and deactivate the nodes **Email Hot Lead to Rep** and **Alert by Email** (select the node and press `D`), and mark the email parts of M-01, M-06 and M-07 as not tested.

### C6. Webhook API key

Make one up in Terminal and save it in your note:

```bash
openssl rand -hex 24
```

---

## Part D: Create the six credentials in n8n (15 minutes)

In n8n, open **Overview > Credentials** and click **Create credential** for each row below.

**Use these names exactly.** The workflows find their credentials by name, so a different name means relinking nodes by hand.

| Name (exact) | Credential type | Fields |
|---|---|---|
| `Lead Router - Postgres` | Postgres | Host `postgres`, Database `lead_router`, User `lead_router_app`, Password = your `LEAD_ROUTER_DB_PASSWORD`, Port `5432`, SSL `disable` |
| `Lead Router - HubSpot` | HubSpot Service Key (called HubSpot App Token in older n8n versions) | Service Key = your HubSpot key |
| `Lead Router - Slack` | Slack API | Access Token = your `xoxb-` token |
| `Lead Router - Google Service Account` | Google Service Account API | Service Account Email = `client_email`, Private Key = `private_key` (paste the whole value). Turn on **Set up for use in HTTP Request node** and set Scope(s) to `https://www.googleapis.com/auth/spreadsheets.readonly`, because 02 reads the three config tabs in one HTTP request. |
| `Lead Router - SMTP` | SMTP | User = your Gmail address, Password = the app password, Host `smtp.gmail.com`, Port `465`, SSL/TLS on |
| `Lead Router - Webhook API Key` | Header Auth | Name `X-API-Key`, Value = your webhook API key |

If n8n's connection test fails for the HubSpot key, save it anyway. Workflow 00 tests the contacts API directly, which is what matters.

---

## Part E: Import the workflows (10 minutes)

1. In Terminal, from the project folder, run:

   ```bash
   docker compose exec n8n n8n import:workflow --separate --input=/workflows
   ```

   It should say `Successfully imported 5 workflows`. Importing this way keeps the links between the workflows (01 calls 02, and 01 and 02 send errors to 03).

2. Refresh n8n. You should see:
   - **00 - Setup & Connection Check**
   - **01 - Lead Intake**
   - **02 - Process Lead**
   - **03 - Error Handler**
   - **99 - Test Runner**

3. **Open each of the five workflows once and press Cmd+S.** When a workflow opens, n8n matches every node to your credentials by name; saving stores that link. A node that still shows a red warning triangle needs its credential picked from the dropdown by hand (this only happens if a credential name differs).

---

## Part F: Fill in the Config nodes (10 minutes)

Each workflow keeps its settings in a node called **Config** near the start. Double-click it, change the values, close it and press Cmd+S.

| Workflow | Value | Set it to |
|---|---|---|
| 00 - Setup & Connection Check | `config.sheet_id` | Your Sheet ID |
| | `config.slack_alerts_channel` | `#lead-alerts` (already set) |
| 01 - Lead Intake | `config.sheet_id` | Your Sheet ID (Config node in the Google Sheet branch) |
| 02 - Process Lead | `config.sheet_id` | Your Sheet ID |
| | `config.slack_leads_channel` | `#leads` (already set) |
| | `config.slack_alerts_channel` | `#lead-alerts` (already set) |
| | `config.hubspot_portal_id` | Your Hub ID (Part G prints it) |
| | `config.from_email` | Your Gmail address |
| | `config.hot_threshold`, `config.warm_threshold` | Leave at 70 and 40 unless you want different bands |
| 03 - Error Handler | `config.alert_email` | Where failure emails should go |
| | `config.from_email` | Your Gmail address |

---

## Part G: Run the setup check (5 minutes)

1. Open **00 - Setup & Connection Check** and click **Execute workflow**.
2. When it finishes, double-click **Setup Summary** and read the output. Every line should say **PASS**:
   - Postgres tables
   - HubSpot key works and can read contacts
   - HubSpot Hub ID (copy this number into `hubspot_portal_id` in 02's Config node, then save)
   - HubSpot Lead Router properties (11 created the first time, "already existed" after that)
   - Google Sheets config sheet readable
   - Google Sheets one-call read of the three config tabs (fails if the credential is not set up for the HTTP Request node)
   - Slack can post to the alerts channel (you will see a test message in #lead-alerts)
3. It is safe to run this again any time. See **Troubleshooting** below for anything that fails.

Running it also creates a **Lead Router** property group on HubSpot contacts, which is where the score, priority and assigned rep appear on each contact record.

---

## Part H: Publish the workflows (5 minutes)

In n8n 2.x a workflow only runs on its own after it is **published**. That applies to the sub-workflow and the error workflow too, so publish all three, in this order:

1. **03 - Error Handler**
2. **02 - Process Lead**
3. **01 - Lead Intake**

For each one: open it, click **Publish** (top right), keep the suggested version name and click **Publish** in the dialog.

> **Important:** after you edit a published workflow, click **Publish** again. Until you do, the previous version keeps running. If 03 is not published, failures happen silently, with no alerts.

Workflows 00 and 99 are run by hand and never need publishing.

---

## Part I: Send your first lead (5 minutes)

**By webhook.** First store your webhook API key in the Terminal window, so it never has to appear in a command (paste your own key in place of `paste-your-key-here`):

```bash
export KEY=paste-your-key-here
```

Then send a lead:

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $KEY" \
  -w '\nHTTP %{http_code} in %{time_total}s\n' \
  -d '{
    "event_id": "first-test-001",
    "first_name": "Ava",
    "last_name": "Martin",
    "email": "ava.martin@harborviewdental.example.com",
    "phone": "(617) 555-0101",
    "company": "Harborview Dental Group",
    "job_title": "Office Manager",
    "state": "Massachusetts",
    "country": "USA",
    "company_size": "35",
    "budget": "$8,000",
    "service_interest": "Managed IT Support",
    "timeline": "1-3 months"
  }'
```

You should get back `{"status":"accepted",...}` and `HTTP 202` straight away, then within a few seconds:

- a message in **#leads** assigning the lead to an East rep
- a new contact in HubSpot with the **Lead Router** properties filled in
- a `routed` row in Adminer (table `lead_log`, or the view `v_lead_activity`)

Run the same command again: nothing new appears in Slack or HubSpot, and `lead_log` shows a `duplicate_dropped` row. That is the duplicate protection working.

`export KEY=...` only lasts until you close that Terminal window. Run it again in any new window before the commands in this guide or the test protocol.

**By form.** Open http://localhost:5678/form/contact-sales in your browser and submit it with a made-up example.com email.

**By sheet.** Type this row into the `intake` tab (leave `status`, `routed_to` and `processed_at` blank):

| added_at | first_name | last_name | email | company | state | country | service_interest |
|---|---|---|---|---|---|---|---|
| today's date and time | Iris | Cole | iris.cole@maplecrestvet.example.com | Maplecrest Vet Clinic | NJ | US | Managed IT Support |

Within 2 minutes its `status` changes to `queued`, then `routed`, with the rep in `routed_to`. Keep the rows in `sample_rows` for test M-02.

Then run the full automated test suite: see [04 - Test Protocol](04-test-protocol.md).

### Load check (optional, test M-11)

Sends 12 leads at the same instant to the East pool, using the `KEY` you exported in Part I:

```bash
RUN=$(date +%H%M%S)
for i in $(seq 1 12); do
  curl -s -o /dev/null -X POST http://localhost:5678/webhook/lead-intake \
    -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
    -d "{\"event_id\":\"burst-$RUN-$i\",\"first_name\":\"Burst$i\",\"last_name\":\"Test\",\"email\":\"burst$i.$RUN@burstco.example.com\",\"company\":\"Burst Co $i\",\"state\":\"NY\",\"country\":\"US\",\"service_interest\":\"Managed IT Support\"}" &
done; wait; echo "Sent 12 leads. Run number: $RUN"
```

After about 30 seconds, run this in Adminer (**SQL command**), with your run number in place of `RUN`:

```sql
SELECT rep_name, count(*) FROM lead_log
WHERE source_event_id LIKE 'burst-RUN-%' AND event = 'routed'
GROUP BY rep_name;
```

Expected: 6 for Maya Chen and 6 for Daniel Okafor.

---

## Everyday commands

Run these from the project folder.

| Task | Command |
|---|---|
| Start everything | `docker compose up -d` |
| Stop everything (data is kept) | `docker compose down` |
| See n8n's log | `docker compose logs -f n8n` |
| Re-import the workflows after pulling changes | `docker compose exec n8n n8n import:workflow --separate --input=/workflows`, then open, save and publish them |
| Delete everything and start over | `docker compose down -v` (this erases the database and n8n data) |

---

## Troubleshooting

| What you see | Cause and fix |
|---|---|
| 01's executions fail with "Workflow is not active and cannot be executed" | 02 is not published. Publish **02 - Process Lead**. |
| A run failed but no alert arrived | 03 is not published, or its Slack and SMTP credentials are wrong. Publish **03 - Error Handler** and check its last execution. |
| Webhook returns 403 | The `X-API-Key` header does not match the Header Auth credential. |
| Webhook returns 404 | **01 - Lead Intake** is not published, or the URL is wrong. |
| Slack: `not_in_channel` | The app lacks `chat:write.public`. Add the scope, reinstall the app, and update the token in n8n if it changed. Or invite the bot: `/invite @Lead Router`. |
| Slack: `channel_not_found` | The channel name in a Config node does not match Slack. |
| Google: "The caller does not have permission" | The sheet is not shared with the service account's `client_email`. |
| Google: "Unable to parse range" or "Sheet with name ... not found" | A tab was renamed. Tab names must be `intake`, `reps`, `scoring_rules`, `territories`. |
| Google: 403 or "missing a valid API key" in Read Config Tabs | The Google credential is not set up for the HTTP Request node. Turn on **Set up for use in HTTP Request node** and add the read-only Sheets scope. Workflow 00 checks this. |
| Google: "The service is receiving too many requests from you" | Google's limit of 60 reads per minute per service account. Read Config Tabs retries for about 20 seconds; if a large burst still fails, open the failed run from the alert and click Retry. |
| HubSpot 403 when creating properties | The key is missing `crm.schemas.contacts.write`. |
| HubSpot: "Property ... does not exist" | Run **00 - Setup & Connection Check** to create the Lead Router properties. |
| Email: "Invalid login" | Use the 16-character app password, not your normal Google password. |
| The form shows a blank 401 page in a script or link preview | The form ignores bots by design. Open it in a normal browser. |
| A sheet row says `duplicate` | That row (same email and `added_at`) was already processed. Change `added_at` to send it again. |
| A sheet row is stuck on `queued` | Its run failed; check the alert and the execution. Clear `status` to send it again after 15 minutes, or retry the execution in n8n. |
| `docker compose up` fails with "port is already allocated" | Something else uses 5678 or 8080. Stop it, or change the left-hand port in `docker-compose.yml` (for n8n, also change `WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` to the new port). |
| n8n log: "password authentication failed" or "Mismatching encryption keys" | `.env` was changed after the first start. Put the original values back, or erase everything with `docker compose down -v` and start again. |
