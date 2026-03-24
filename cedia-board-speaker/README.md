# CEDIA Board Meeting — Speaker Queue

A real-time speaker queue management tool for CEDIA board meetings.
Built with plain HTML/JS, Supabase (real-time database), and Vercel (hosting).

---

## Four Pages

| URL | Purpose |
|-----|---------|
| `/display` | **Display screen** — put this on the meeting room TV/projector |
| `/join` | **Request to speak** — board members open this on their phones (QR code) |
| `/moderator` | **Moderator panel** — manages topics, queue, and speaker timer |
| `/qr` | **QR code page** — print this and place on the meeting table |

---

## Setup: Step by Step

### 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a free project
2. In the Supabase dashboard, go to **SQL Editor**
3. Paste the entire contents of `supabase/schema.sql` and click **Run**
4. Go to **Project Settings > API** and copy:
   - **Project URL** (looks like `https://xxxx.supabase.co`)
   - **anon / public key** (the long `eyJ...` token)

### 2. Configure the App

Open `config.js` and replace the placeholder values:

```js
const CONFIG = {
  SUPABASE_URL: 'https://your-project-id.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIs...',
  SPEAKER_TIME_SECONDS: 120
};
```

### 3. Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/cedia-board-speaker.git
git push -u origin main
```

### 4. Deploy to Vercel

1. Go to [vercel.com](https://vercel.com) and click **Add New Project**
2. Import your GitHub repository
3. Leave all settings as default (no build command needed)
4. Click **Deploy**

Vercel will give you a URL like `https://cedia-board-speaker.vercel.app`

### 5. Done

Your four pages will be live at:
- `https://your-app.vercel.app/display`
- `https://your-app.vercel.app/join`
- `https://your-app.vercel.app/moderator`
- `https://your-app.vercel.app/qr`

---

## How to Run a Meeting

1. **Before the meeting:** Open `/qr` and print it, or display it on a secondary screen
2. **On the meeting room TV:** Open `/display` — leave it full screen
3. **On your laptop/tablet:** Open `/moderator`
4. **To start:** Type the first discussion topic in the Moderator panel and click **Set Topic**
5. **Board members** scan the QR code and join the queue on their phones
6. **When ready:** Click **Start Next Speaker** — the 2-minute timer begins on the display screen
7. **When time is up:** The display turns red and shows overtime. Click **Next Speaker** when you're ready to move on
8. **New topic:** Type a new topic in the Moderator panel — this automatically clears the queue

---

## Customisation

- **Speaker time:** Change `SPEAKER_TIME_SECONDS` in `config.js` (default: 120 = 2 minutes)
- **Moderator URL security:** For a harder-to-guess URL, rename `moderator.html` to something like `mod-a7f3k.html` and update `vercel.json` if needed

---

## Tech Stack

- **Frontend:** Vanilla HTML, CSS, JavaScript — no build step
- **Database:** [Supabase](https://supabase.com) (PostgreSQL + real-time WebSocket subscriptions)
- **Hosting:** [Vercel](https://vercel.com) (static file serving)
- **QR Code:** [qrcodejs](https://github.com/davidshimjs/qrcodejs)
- **Fonts:** Google Fonts (Barlow Condensed, DM Sans)
