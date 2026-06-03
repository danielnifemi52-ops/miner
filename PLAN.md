# Distributed Crypto Miner — PLAN.md

## Project Overview

A distributed Monero (XMR) mining system spanning Windows, Linux, Docker, Android, and browser
platforms. All agents report to a central coordinator server. Mining runs silently in the background
on boot, using CPU/RAM (RandomX algorithm) with minimal GPU requirement.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mining Engine | XMRig (native), WebAssembly (browser/iOS) |
| Coordinator Backend | Node.js + Express |
| Hosting (API) | Render Web Service (free tier) |
| Hosting (Dashboard) | Render Static Site (free, no spin-down) |
| Database | Supabase PostgreSQL (free tier, never expires) |
| Realtime | Supabase Realtime — live stats pushed to dashboard |
| Keep-Alive | UptimeRobot — pings coordinator every 5 mins (free) |
| Dashboard UI | React + Vite |
| Windows Agent | XMRig + PowerShell installer + Windows Service (NSSM) |
| Linux Agent | XMRig + Bash installer + systemd unit |
| Android Agent | Flutter APK + Foreground Service + XMRig binary |
| Web/iOS Miner | HTML + JavaScript (WebAssembly miner) |
| DB Client (server) | `@supabase/supabase-js` (Node.js) |
| DB Client (dashboard) | `@supabase/supabase-js` (React) — Realtime subscriptions |
| Communication | REST API + Supabase Realtime (replaces custom WebSocket) |
| Auth (Dashboard) | JWT (JSON Web Token) — password login |
| Auth (Agents) | Shared secret token in request headers |
| Secrets Management | Render + Supabase Environment Variables (never in code) |

---

## Repository Structure

```
distributed-miner/
├── coordinator/
│   ├── server/
│   │   ├── index.js               # Express API server
│   │   ├── .env                   # Secrets (gitignored)
│   │   ├── .env.example           # Template for setup
│   │   ├── middleware/
│   │   │   ├── authJwt.js         # Protects dashboard API routes
│   │   │   └── authAgent.js       # Protects agent API routes
│   │   ├── routes/
│   │   │   ├── auth.js            # POST /auth/login → returns JWT
│   │   │   ├── workers.js         # Worker registration & stats
│   │   │   └── config.js          # Config distribution endpoint
│   │   ├── db/
│   │   │   └── supabase.js          # Supabase client + query helpers
│   │   └── ws/                      # No custom WebSocket — Supabase Realtime handles this
│   ├── dashboard/
│   │   ├── src/
│   │   │   ├── App.jsx
│   │   │   ├── pages/
│   │   │   │   ├── Login.jsx          # Password login page
│   │   │   │   └── Dashboard.jsx      # Protected main view
│   │   │   ├── components/
│   │   │   │   ├── WorkerCard.jsx
│   │   │   │   ├── HashratChart.jsx
│   │   │   │   └── StatusBadge.jsx
│   │   │   ├── hooks/
│   │   │   │   ├── useWorkers.js
│   │   │   │   ├── useAuth.js             # JWT storage + validation
│   │   │   │   └── useRealtime.js         # Supabase Realtime subscription
│   │   │   └── utils/
│   │   │       ├── api.js                 # Axios instance with JWT header
│   │   │       └── supabase.js            # Supabase client (anon key)
│   │   └── package.json
│   └── render.yaml                    # Render deployment config (IaC)
│
├── agents/
│   ├── windows/
│   │   ├── install.ps1            # PowerShell installer
│   │   ├── uninstall.ps1
│   │   ├── config-template.json   # XMRig config template
│   │   └── service-wrapper.xml    # NSSM/WinSW service definition
│   │
│   ├── linux/
│   │   ├── install.sh             # Bash installer
│   │   ├── uninstall.sh
│   │   ├── config-template.json
│   │   └── xmrig-miner.service    # systemd unit file
│   │
│   └── android/
│       ├── app/
│       │   ├── src/main/
│       │   │   ├── MainActivity.kt
│       │   │   ├── MinerService.kt        # Foreground service
│       │   │   ├── XmrigRunner.kt         # Runs XMRig binary
│       │   │   └── WorkerReporter.kt      # Reports stats to coordinator
│       │   └── res/
│       └── pubspec.yaml (Flutter)
│
└── web-miner/
    ├── index.html                 # Standalone web miner page
    ├── miner.js                   # WebAssembly miner logic
    └── worker-reporter.js         # Reports stats to coordinator
```

---

## Phase 1 — Coordinator Server (Render)

**Goal:** Central server that all agents connect to. Distributes config, collects stats, serves dashboard. Deployed on Render free tier with Supabase as the database and realtime engine.

### Components
- **REST API** (Express)
  - `POST /auth/login` — takes admin password, returns signed JWT (24h expiry)
  - `POST /api/register` — agent registers itself (name, platform, IP) — agent secret required
  - `POST /api/stats` — agent reports hashrate, CPU usage, uptime — agent secret required
  - `GET /api/config` — agent fetches its mining config — agent secret required
  - `GET /api/workers` — dashboard fetches all worker data — JWT required
- **Auth middleware**
  - `authJwt.js` — validates Bearer JWT on all dashboard-facing routes
  - `authAgent.js` — validates `X-Agent-Secret` header on all agent-facing routes
- **Supabase** — replaces both the database and the custom WebSocket server
  - Coordinator writes stats rows → Supabase Realtime broadcasts inserts to dashboard automatically
  - No `ws/socket.js` needed
- **Render Web Service** — runs the Node.js coordinator, always-on via UptimeRobot pings

### Environment Variables (set in Render dashboard)
```env
# Dashboard admin access
ADMIN_PASSWORD=yourStrongPasswordHere

# JWT signing secret (random long string)
JWT_SECRET=aRandomLongSecretString64CharsOrMore

# Shared secret all agents include in requests
AGENT_SECRET=anotherSecretTokenForAgents

# Supabase (from your Supabase project settings)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key   # server-side only, full DB access

# App config
PORT=3000
JWT_EXPIRES_IN=24h
NODE_ENV=production
```

### Dashboard Environment Variables (set in Render Static Site)
```env
# Supabase (anon/public key — safe to expose in frontend)
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key

# Coordinator API URL
VITE_API_URL=https://your-coordinator.onrender.com
```

> ⚠️ The **service role key** is only used server-side (coordinator). Never expose it in the frontend.
> The **anon key** is safe for the dashboard — Supabase Row Level Security (RLS) controls access.

### Config distributed to agents
```json
{
  "pool": "pool.moneroocean.stream:10008",
  "wallet": "YOUR_XMR_WALLET_ADDRESS",
  "cpu_threads": "auto",
  "cpu_max_percent": 70,
  "pause_on_battery": true,
  "pause_on_active_use": false
}
```

### Services Layout
```
Render Web Service      → coordinator Node.js API (port 3000)
Render Static Site      → React dashboard (no spin-down)
Supabase                → PostgreSQL database + Realtime engine
UptimeRobot             → pings GET /health every 5 mins to prevent Render spin-down
```

### Supabase Realtime Flow
```
Agent → POST /api/stats → coordinator → INSERT into Supabase stats table
                                                    ↓
                              Supabase Realtime broadcasts INSERT event
                                                    ↓
                              Dashboard useRealtime() hook receives update
                                                    ↓
                              Worker card updates live — no polling needed
```

### Database Schema (run in Supabase SQL Editor)
```sql
-- Workers table
CREATE TABLE workers (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  platform      TEXT NOT NULL,         -- windows | linux | android | web
  ip            TEXT,
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen     TIMESTAMPTZ
);

-- Stats table (Realtime enabled on this table)
CREATE TABLE stats (
  id          SERIAL PRIMARY KEY,
  worker_id   INTEGER REFERENCES workers(id),
  hashrate    REAL,                    -- H/s
  cpu_percent REAL,
  uptime_secs INTEGER,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Config table
CREATE TABLE config (
  id    SERIAL PRIMARY KEY,
  key   TEXT UNIQUE NOT NULL,
  value TEXT NOT NULL
);

-- Enable Realtime on stats table
ALTER PUBLICATION supabase_realtime ADD TABLE stats;
ALTER PUBLICATION supabase_realtime ADD TABLE workers;
```

> Enable Realtime in Supabase Dashboard → Database → Replication → toggle on `stats` and `workers` tables.

### Deliverables
- [ ] `coordinator/server/index.js`
- [ ] `coordinator/server/.env.example`
- [ ] `coordinator/server/middleware/authJwt.js`
- [ ] `coordinator/server/middleware/authAgent.js`
- [ ] `coordinator/server/routes/auth.js`
- [ ] `coordinator/server/routes/workers.js`
- [ ] `coordinator/server/routes/config.js`
- [ ] `coordinator/server/db/supabase.js`
- [ ] `coordinator/server/db/schema.sql`
- [ ] `coordinator/render.yaml`

---

## Phase 2 — Dashboard UI

**Goal:** Web UI showing all connected workers, their hashrate, platform, and status in real time.

### Features
- **Login page** — password input, submits to `/auth/login`, stores JWT in `localStorage`
- Auto-redirect to login if JWT is missing or expired
- All API calls include `Authorization: Bearer <token>` header via Axios interceptor
- Live worker grid (name, platform icon, hashrate, CPU%, uptime, status)
- Total network hashrate
- Online/offline/idle status badges
- Historical hashrate chart (per worker + total)
- Simple settings panel (update wallet address, thread limits)
- Logout button — clears JWT and redirects to login

### Tech
- React + Vite
- WebSocket connection to coordinator
- Recharts for hashrate graphs
- Deployed as **Render Static Site** (free, never spins down)
- Build command: `npm run build` → `dist/` folder served by Render

### Deliverables
- [ ] `coordinator/dashboard/src/App.jsx` (with protected route logic)
- [ ] `coordinator/dashboard/src/pages/Login.jsx`
- [ ] `coordinator/dashboard/src/pages/Dashboard.jsx`
- [ ] `coordinator/dashboard/src/components/WorkerCard.jsx`
- [ ] `coordinator/dashboard/src/components/HashrateChart.jsx`
- [ ] `coordinator/dashboard/src/hooks/useAuth.js`
- [ ] `coordinator/dashboard/src/hooks/useWorkers.js`
- [ ] `coordinator/dashboard/src/hooks/useRealtime.js`
- [ ] `coordinator/dashboard/src/utils/api.js`
- [ ] `coordinator/dashboard/src/utils/supabase.js`

---

## Phase 3 — Windows Agent

**Goal:** Silent background Windows Service that starts on boot, mines XMR, reports to coordinator.

### Install Flow
1. User runs `install.ps1` as Administrator
2. Script prompts for coordinator URL and **agent secret**
3. Script downloads XMRig binary
4. Fetches config from coordinator (`GET /api/config` with `X-Agent-Secret` header)
5. Registers device with coordinator (`POST /api/register` with `X-Agent-Secret` header)
6. Saves agent secret to `C:\ProgramData\xmrig-agent\agent.conf`
7. Installs XMRig as a Windows Service using **NSSM** (Non-Sucking Service Manager)
8. Service starts immediately and on every boot
9. A stats reporter runs alongside, POSTing hashrate to coordinator every 60s

### Service Behavior
- Runs as `LocalSystem` account
- No taskbar icon, no window
- Auto-restarts on crash
- Logs to `C:\ProgramData\xmrig-agent\logs\`

### CPU Throttle
- Default: 70% max CPU
- Configurable via coordinator config endpoint

### Deliverables
- [ ] `agents/windows/install.ps1`
- [ ] `agents/windows/uninstall.ps1`
- [ ] `agents/windows/config-template.json`
- [ ] `agents/windows/service-wrapper.xml`
- [ ] `agents/windows/reporter.ps1` (stats heartbeat)

---

## Phase 4 — Linux Agent

**Goal:** systemd daemon that starts on boot, mines XMR, reports stats.

### Install Flow
1. User runs `sudo bash install.sh`
2. Script prompts for coordinator URL and **agent secret**
3. Script downloads XMRig binary to `/opt/xmrig/`
4. Fetches config from coordinator (with `X-Agent-Secret` header)
5. Registers device (with `X-Agent-Secret` header)
6. Saves agent secret to `/etc/xmrig-agent/agent.conf` (root-owned, chmod 600)
7. Installs systemd unit to `/etc/systemd/system/xmrig-miner.service`
8. Enables and starts service

### systemd Unit Behavior
- `Restart=always` — auto-restarts on crash
- `After=network.target` — waits for network before starting
- Runs as a dedicated low-privilege user `xmrig`
- Logs via `journalctl -u xmrig-miner`

### Deliverables
- [ ] `agents/linux/install.sh`
- [ ] `agents/linux/uninstall.sh`
- [ ] `agents/linux/xmrig-miner.service`
- [ ] `agents/linux/config-template.json`
- [ ] `agents/linux/reporter.sh`

---

## Phase 5 — Android Agent (Flutter APK)

**Goal:** Android app with a persistent Foreground Service that mines in the background.

### Architecture
```
MainActivity (UI)
└── MinerService (Foreground Service)
    ├── XmrigRunner       — spawns XMRig binary as subprocess
    ├── WorkerReporter    — POSTs stats to coordinator every 60s
    └── BatteryMonitor    — pauses mining when battery < 20%
```

### Key Behaviors
- **Foreground Service** with a minimal notification (required by Android OS)
  - Notification: "⛏ Miner running — tap to open"
- Starts automatically on device boot via `RECEIVE_BOOT_COMPLETED` broadcast receiver
- Pauses when battery drops below 20%
- Resumes when charging or battery recovers
- CPU throttle: 60% max (configurable)

### XMRig on Android
- XMRig has prebuilt ARM64 binaries for Android
- Bundled inside the APK assets, extracted to app's private storage on first run
- Executed as a subprocess from `XmrigRunner.kt`
- Agent secret stored in Android `EncryptedSharedPreferences` (secure storage)
- All coordinator requests include `X-Agent-Secret` header

### Permissions Required
```
FOREGROUND_SERVICE
RECEIVE_BOOT_COMPLETED
INTERNET
BATTERY_STATS (optional, for battery monitoring)
```

### Deliverables
- [ ] `agents/android/app/src/main/MainActivity.kt`
- [ ] `agents/android/app/src/main/MinerService.kt`
- [ ] `agents/android/app/src/main/XmrigRunner.kt`
- [ ] `agents/android/app/src/main/WorkerReporter.kt`
- [ ] `agents/android/app/src/main/BootReceiver.kt`
- [ ] `agents/android/app/src/main/AndroidManifest.xml`

---

## Phase 6 — Web Miner (Browser / iOS)

**Goal:** A webpage friends/family open in any browser. Mines using WebAssembly, reports to coordinator.

### How It Works
- Uses a WebAssembly build of a CPU miner (e.g. `cryptonight-wasm` or similar)
- Runs in a Web Worker so it doesn't block the UI
- User opens the page, clicks "Start Mining"
- Reports hashrate + worker name to coordinator every 60s

### Features
- Simple UI: worker name input, start/stop button, live hashrate display
- Throttle slider (10%–80% CPU)
- Works on iOS Safari (no app needed)
- Mobile-responsive

### Limitations vs Native
- ~10–30% of native hashrate (WebAssembly overhead)
- Stops when tab is closed or phone locks screen
- Best used as supplementary workers

### Deliverables
- [ ] `web-miner/index.html`
- [ ] `web-miner/miner.js`
- [ ] `web-miner/worker.js` (Web Worker)
- [ ] `web-miner/reporter.js`

---

## Phase 7 — Testing & Deployment

### Supabase Setup Steps
- [ ] Create account at [supabase.com](https://supabase.com) (free)
- [ ] Create new project → note the **Project URL** and **API keys**
- [ ] Open SQL Editor → paste and run `schema.sql`
- [ ] Enable Realtime on `stats` and `workers` tables (Database → Replication)
- [ ] Copy **service role key** (for coordinator) and **anon key** (for dashboard)

### Render Setup Steps
- [ ] Push project to GitHub (private repo)
- [ ] Create **Render Web Service** → connect GitHub repo → add environment variables (including Supabase keys)
- [ ] Create **Render Static Site** → connect GitHub repo → set build command `npm run build`, publish dir `dist`
- [ ] Set `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` on Static Site
- [ ] Sign up for **UptimeRobot** (free) → monitor `GET https://your-coordinator.onrender.com/health` every 5 mins

### Agent Testing Checklist
- [ ] Test Windows agent on one machine first
- [ ] Test Linux agent on one machine first
- [ ] Install Android APK via sideloading (enable Unknown Sources)
- [ ] Share web miner URL with family/friends (iOS users)
- [ ] Monitor dashboard for all workers reporting in real time
- [ ] Verify XMR hashrate appearing on MoneroOcean pool dashboard

### Free Tier Limits to Know
| Resource | Free Limit | Impact |
|---|---|---|
| Render Web Service | Spins down after 15min inactivity | Fixed by UptimeRobot |
| Render Static Site | 100GB bandwidth/mo | More than enough |
| Supabase DB | 500MB storage | More than enough for ~20 workers |
| Supabase Realtime | 200 concurrent connections | More than enough |
| Supabase project | **Never expires** | No 90-day limit like Render PostgreSQL |

---

## Mining Pool

**Recommended: MoneroOcean** (`pool.moneroocean.stream`)
- Auto-switches to most profitable CPU-mineable coin
- Pays out in XMR regardless
- No minimum payout threshold for small miners
- Free, reliable, well-established

**Wallet:** Create a Monero wallet at [getmonero.org](https://www.getmonero.org/downloads/) or use the
Feather Wallet desktop app.

---

## CPU Throttle Settings (Recommended)

| Device Type | Max CPU % | Notes |
|---|---|---|
| Desktop PC | 70% | Plenty of cooling |
| Laptop | 50% | Heat management |
| Server | 80% | Built for sustained load |
| Android phone | 50–60% | Battery + heat |
| Old/weak device | 30–40% | Prevent slowdown |

---

## Security Model

### Two-layer auth
| Layer | Who | Method |
|---|---|---|
| Dashboard | You (admin) | Password → JWT (24h expiry) |
| Agents | Your devices | Shared `AGENT_SECRET` in `X-Agent-Secret` header |

### Rules
- Dashboard login: password typed by you → server validates → returns signed JWT
- JWT stored in browser `localStorage`, sent as `Authorization: Bearer <token>` on every request
- Agents never use the JWT — they use the separate `AGENT_SECRET`
- Supabase Realtime connection from dashboard uses the **anon key** — safe, read-only via RLS
- Coordinator uses the **service role key** server-side only — never exposed to frontend
- `.env` file used locally for development only — **gitignored**
- All production secrets set via **Render Environment Variables UI** — never in code
- `AGENT_SECRET` stored securely per platform:
  - Windows: `C:\ProgramData\xmrig-agent\agent.conf` (Admin-only access)
  - Linux: `/etc/xmrig-agent/agent.conf` (chmod 600, root-owned)
  - Android: `EncryptedSharedPreferences`
- Coordinator API is only accessible via Render's HTTPS URL — no open ports to manage
- Render provides **free HTTPS** automatically on all services (no Nginx/Certbot needed)

---

## Build Order Summary

| Phase | Component | Est. Effort |
|---|---|---|
| 1 | Coordinator server (Render + Supabase + API) | Medium |
| 2 | Dashboard UI (React + Supabase Realtime → Render Static Site) | Medium |
| 3 | Windows agent (PowerShell + NSSM service) | Medium |
| 4 | Linux agent (Bash + systemd) | Easy |
| 5 | Android APK (Flutter + Foreground Service) | Hard |
| 6 | Web miner (HTML + WASM) | Easy–Medium |
| 7 | Supabase + Render deployment + UptimeRobot | Easy |
