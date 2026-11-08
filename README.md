# Herbie: job notes → Jira tickets, on a local AI model

Herbie turns a freelance IT technician's rough job notes into clean, categorized support tickets
(Incident / Request / Problem / Change, with priority, root cause, steps taken and resolution),
then files them in Jira with one click.

The AI runs entirely on your own PC through [Lemonade](https://lemonade-server.ai), AMD's local AI server.
Job notes (client passwords, network details, names) are never sent to a cloud AI, and there are no per-ticket API fees.
The only thing that leaves your PC is the finished ticket, sent to your own Jira, if you set that up.

## Why local matters for freelance techs
- **Privacy:** job notes often contain client credentials and internal details. No cloud AI ever sees them.
- **Cost:** a cloud model bills every ticket. Herbie on Lemonade costs $0 per ticket.
- **Works on site:** ticket writing works with no internet; Jira filing catches up with "Send to Jira" later.

## Setup (Windows)
1. Install **Lemonade Server** from https://lemonade-server.ai and open it.
2. In Lemonade's **Models** page, download and load a chat model. `Qwen3-4B-Instruct-2507-GGUF` (2.5 GB) works well on a 16 GB laptop.
3. Right-click **`Make-Shortcuts.ps1`** → **Run with PowerShell**. This puts a **Herbie** shortcut on your Desktop and in the Start menu.
   To pin him: right-click the Desktop shortcut → **Pin to taskbar**.
4. Open **Herbie**. He opens in his own window. Pick the model in the top-right **Model** menu if needed.

No Python, Node or other installs: Herbie's helper is PowerShell, which ships with Windows.
`Start-Herbie.cmd` does the same as the shortcut but keeps a console window open, which is handy for troubleshooting.
Lemonade on a different port? `Start-Herbie.cmd -Lemonade http://localhost:PORT`.

## Jira (optional)
1. Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens.
2. Copy `.env.example` to `.env` in this folder and fill in your site, space key, email and token.
3. Click **Save ticket** in Herbie. A few seconds later he shows "Filed in Jira as KAN-12" with a link.

What Herbie files:

| Herbie | Jira |
| --- | --- |
| Category | Work type: Incident, Service Request, Problem, Change (missing types fall back to Task + a `category-…` label) |
| Priority | Priority (Critical → Highest) |
| Client | `[Client]` prefix on the title and a client label |
| Issue, Root cause, Steps, Resolution, Reason | Description sections, plus the original notes as a quote |
| Status: Resolved | Moved to the space's done status |
| Time in the notes ("45 min", "1.5 hours") | Work log entry |
| Always | Assigned to you, labeled `herbie` |

- Saving the same ticket twice never files a duplicate.
- Editing a ticket updates its Jira ticket. Changing its category files a new ticket of the new type and links the two
  (Incident → Problem keeps the Incident open; other changes close the old ticket).
- If Jira can't be reached, the ticket stays in Herbie with a **Send to Jira** button in Past tickets.
- Every Jira action is written to `herbie_jira.log`.

## How it works
- `index.html`: the Herbie app. Sends the notes plus Herbie's ticket rules (with worked examples that keep small
  models accurate) to Lemonade's OpenAI-compatible `/api/v1/chat/completions` endpoint and asks for a JSON ticket.
- `serve-herbie.ps1`: a tiny local web server. It serves the page, passes `/api/*` calls to Lemonade, and files tickets
  in Jira with the login from `.env`. The token never reaches the browser. It only accepts requests from Herbie's
  own page, and only serves Herbie's page files (never `.env`).
- Tickets are stored in the browser's local storage. **Export tickets** / **Import tickets** on the Past tickets screen
  make backups or move them to another PC.
- Each ticket records which model wrote it, how long it took and how many tokens it used.

## License
MIT. See [LICENSE](LICENSE).
