# Herbie: job notes → Jira tickets, powered by AMD Lemonade

Herbie turns a freelance IT technician's rough job notes into clean, ITIL-style support tickets
(Incident / Request / Problem / Change, with impact, urgency, priority, root cause, steps taken and resolution),
then files them in Jira with one click. Type the notes, click **Talk** and say them, or click **Snap** to add a photo
of an error screen or device label.

▶ **Watch the 3-minute demo:** https://youtu.be/upkcFmf89ao

Herbie's AI runs entirely on your own PC through [Lemonade](https://lemonade-server.ai), AMD's local AI server.
Job notes, voice recordings and photos stay on your machine unless you choose to send them.
Your data is private by default, with no cloud AI fees.
If you use Jira, Herbie files the finished ticket and its photos there in one click.

## What's new
**v1.2: Lemonade Omni upgrade, stronger ITIL focus**
- **Snap:** Add photo feature. Lemonade Omni reads the photo and enters the key details (error codes, serial numbers,
  service tags) into the ticket. The photo is saved locally and attached in Jira (if desired).
- **Read-back:** Herbie reads a ticket's client and summary out loud, on new and past tickets, accelerating ticket review.
- **Added ITIL fields:** Requested by, Affected item, and Approved by, with priority now set from impact × urgency.
- **Client required:** every ticket needs a client name before it can be saved.

**v1.1: Voice notes**
- **Talk:** say your notes and Whisper turns them into text on your PC, spelling IT terms correctly with a built-in
  word list.

**v1.0: Local AI**
- **Lemonade:** Herbie moves from a paid cloud AI service to AMD Lemonade. Herbie writes tickets with or without a network connection.
  Job notes stay on your PC and there are no metered cloud AI fees.

## Lemonade: Herbie's AI engine
![Herbie's workflow: the technician types, talks or snaps a photo; Herbie's app and local helper send voice to Whisper-Base, notes to Qwen3-4B, and photos and the read-back to the LMX-Omni-5.5B-Lite bundle on AMD Lemonade; photos are kept in a local folder, and only the finished ticket and its photos go to Jira](docs/herbie-workflow.png)

Every AI job in Herbie runs on Lemonade, and each one uses the model that tested best for it:

| Job | Lemonade model | Where it runs |
|---|---|---|
| Writing the ticket | **Qwen3-4B-Instruct** | GPU |
| Voice notes → text | **Whisper-Base** | NPU |
| Reading photos (Snap) | **LMX-Omni-5.5B-Lite** (its Qwen3.5-4B vision model) | GPU |
| Reading a ticket aloud | **Kokoro**, the voice inside the Omni bundle | CPU |

Herbie finds the Omni bundle and its parts automatically. **No Omni?** Snap falls back to a separate vision model
(such as `Gemma-4-E2B-it-GGUF`), and read-back uses `kokoro-v1`.

## Why local AI matters for freelance techs
- **Privacy:** job notes and photos of client screens often contain passwords and internal details. With Lemonade, no
  cloud AI ever sees them.
- **Cost:** a cloud AI charges for every ticket. Lemonade runs Herbie with no AI fees and comparable results (see
  Performance below).
- **Works anywhere:** Herbie writes tickets with no internet. Once you're back online, one click sends them to Jira.
- **Hands-free:** talk your notes on the way out of a job and listen to ticket summaries whenever you like.

## Setup (Windows)
1. **Install Lemonade Server** from https://lemonade-server.ai and open it.
2. **Download the models** in Lemonade's **Models** page:
   - `Qwen3-4B-Instruct-2507-GGUF` (2.5 GB): writes the tickets. **Required.**
   - `Whisper-Base`: turns voice notes into text. *Recommended.*
   - `LMX-Omni-5.5B-Lite` (9.3 GB): reads photos and speaks the read-back. *Recommended.* Lemonade aims it at 32 GB
     machines; it ran fine on our 24 GB laptop. From a terminal: `lemonade pull LMX-Omni-5.5B-Lite`.
3. **Make the shortcut:** right-click **`Make-Shortcuts.ps1`** → **Run with PowerShell**. This puts **Herbie** on your
   Desktop and in the Start menu. To pin him, right-click the Desktop shortcut → **Pin to taskbar**.
4. **Open Herbie.** He opens in his own window. If asked, pick **Qwen3-4B** in the top-right **Model** menu. Herbie
   finds Whisper and Omni on his own.

No Python, Node or other installs: Herbie's helper is PowerShell, which ships with Windows.
`Start-Herbie.cmd` does the same as the shortcut but keeps a console window open, which is handy for troubleshooting.
Lemonade on a different port? `Start-Herbie.cmd -Lemonade http://localhost:PORT`.

## Talk your notes
Click **🎤 Talk**, say what you did on the job, and click **Stop**. Lemonade's Whisper turns your voice into text on
your PC and adds it to the notes box. Check it, then click **Create ticket**.

## Snap a photo
1. Click **📷 Snap** and pick a photo, or paste a screenshot (Ctrl+V) or drag a picture onto the notes box.
2. Lemonade Omni reads it and shows what it found next to the photo: error code and message, product, device, serial
   number or service tag.
3. Check the numbers, and click **Add to notes**.

The photo stays with the ticket: it's saved in Herbie's `photos` folder, shown in Past tickets, and attached in Jira.
Codes from the photo reach the ticket word for word, and the device fills in **Affected item**.

## Hear a read-back
Click **🔊 Read aloud** on a new ticket, or the **🔊** next to any ticket in Past tickets. Omni's Kokoro voice reads the
client and summary in a few seconds, so you can find the right ticket without reading through the list. Click **■** to stop.

## ITIL fields
Herbie follows ITIL, the standard most IT service desks use, so every ticket answers who, what, how bad and who
approved it.

| Field | How Herbie fills it |
|---|---|
| **Client** | From your notes. **Required:** Herbie won't save a ticket without one ("Unknown" doesn't count). |
| **Requested by** | The person who asked, if your notes name them. Optional. |
| **Affected item** | The PC, printer, app or service. Snap fills it from the label. Optional. |
| **Impact** | How much of the business is affected: one user, several users, or the whole office. |
| **Urgency** | How fast it's needed: it can wait, it's slowing work, or work has stopped. |
| **Priority** | Set automatically from impact and urgency (see below). You can still change it by hand. |
| **Approved by** | Shown only on Changes and Requests. Optional, with a reminder on a Change that has none. |

**How priority is set**
- **Critical:** the whole office is affected *and* work has stopped.
- **High:** the whole office is affected and work is slowed, *or* several users can't work at all.
- **Medium:** the whole office is affected but it can wait, several users are slowed, *or* one user can't work at all.
- **Low:** one user is slowed, *or* it can wait and affects only one or a few users.

Herbie makes the first call on impact and urgency from your notes. You can change either one, and priority updates to
match.

## Performance (measured)
Tested on an **ASUS Zenbook S 16**: AMD Ryzen AI 9 365 (10 cores), Radeon 880M graphics, XDNA 2 NPU, 24 GB RAM,
Windows 11 Pro, Lemonade 2026.45.3. Lemonade ran Qwen3-4B on the GPU (llama.cpp, Vulkan, Q4_K_M), Whisper-Base on
the NPU, and Kokoro on the CPU.

### Cloud AI vs Lemonade
32 test job notes, 20 written out cleanly and 12 in real-world shorthand ("qb froze again, 4th time. restarted svc"),
each with the ITIL category a technician would expect. All ran with Herbie's same rules.

| | Cloud: Claude Opus 5.5 | Lemonade v1.1 | **Lemonade v1.2 (ITIL)** |
|---|---|---|---|
| Right category, all 32 notes | 32/32 | 30/32 | **30/32** |
| Clean notes | 20/20 | 20/20 | **20/20** |
| Shorthand notes | 12/12 | 10/12 | **10/12** |
| Time per ticket | not measured\* | 12.6 s | **~7.9 s** |
| Where job notes go | cloud servers | this laptop | **this laptop** |
| Works with no internet | no | yes | **yes** |
| AI fees | billed per use | none | **none** |

**What this shows:** a 4-billion-parameter model running on a laptop through Lemonade keeps pace with Anthropic's top
cloud model. It matched every clean note, missed just 2 of 12 shorthand notes, and scored a perfect 32/32 in earlier
runs. v1.2 also cut ticket time from 12.6 s to about 7.9 s, with the same accuracy.

\*The cloud answers came from pasting all 32 notes into one claude.ai chat, so there is no per-ticket time. Herbie on
Lemonade was timed one ticket at a time, the way the app works.

### Lemonade Omni: reading real photos

| Photo | Omni-Lite result |
|---|---|
| Dell service tag | exact |
| Small, rotated serial sticker | exact |
| Adobe warning screen | exact |
| Non-IT slide | ignored, no made-up codes |

### Test it on your own PC
Want to check our numbers? The [`eval/`](eval) folder has the 32 test notes and a one-click script, `Run-Voice-Eval.cmd`,
that runs them through Herbie on your own Lemonade setup and scores the results. It takes about 15 minutes.

## Jira (optional)
1. Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens.
2. Copy `.env.example` to `.env` and fill in your Jira site, space key, email and token.
3. Click **Save ticket**. Herbie files it in Jira, photos included, and shows the link.

| Herbie | Jira |
|---|---|
| Category | Work type (Incident, Service Request, Problem, Change) |
| Priority | Priority |
| Client | `[Client]` in the title, plus a label |
| Requested by, Affected item, Impact, Urgency, Approved by | **Details** section at the top |
| Issue, Root cause, Steps, Resolution | Description, plus your original notes |
| Snap photos | Attachments |
| Time in your notes ("45 min") | Work log |

- **No duplicates:** saving twice never files a second ticket or attaches a photo twice.
- **Edits sync:** changing a ticket in Herbie updates it in Jira.
- **Offline? No problem:** the ticket waits in Herbie. Click **Send to Jira** when you're back online.
- **Photos:** kept on your PC; once attached, Jira stores a copy in its cloud, like the ticket text.

## How it works
- **`index.html`:** the Herbie app. It sends your notes, voice and photos to Lemonade's OpenAI-compatible API and shows
  the ticket for you to review.
- **`serve-herbie.ps1`:** a tiny local server. It passes requests to Lemonade, saves photos, and files tickets in Jira.
  Your Jira token never reaches the browser.
- **Storage:** tickets are kept in Herbie's window; **Export** / **Import** in Past tickets backs them up. Photos are
  kept in the `photos` folder.

## Credits
- **Designed, tested and used in the field by** Damien Nguyen, a freelance IT technician.
- **Code written with** Claude (Anthropic).
- **Runs on** [AMD Lemonade](https://lemonade-server.ai): Qwen3-4B-Instruct, Whisper-Base and LMX-Omni-5.5B-Lite, all on
  your own PC.
- **v1.1 release notes written by** Qwen3-4B-Instruct, running on Lemonade.

## License
MIT. See [LICENSE](LICENSE).
