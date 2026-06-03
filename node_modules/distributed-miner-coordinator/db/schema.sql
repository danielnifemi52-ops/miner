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
  worker_id   INTEGER REFERENCES workers(id) ON DELETE CASCADE,
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

-- Enable Realtime on stats and workers tables
ALTER PUBLICATION supabase_realtime ADD TABLE stats;
ALTER PUBLICATION supabase_realtime ADD TABLE workers;

-- Create index for faster queries
CREATE INDEX idx_stats_worker_id ON stats(worker_id);
CREATE INDEX idx_stats_recorded_at ON stats(recorded_at);
CREATE INDEX idx_workers_platform ON workers(platform);
