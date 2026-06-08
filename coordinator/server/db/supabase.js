const { createClient } = require('@supabase/supabase-js');
const ws = require('ws');

const useMock = !process.env.SUPABASE_URL || process.env.SUPABASE_URL.includes('your-project');

let supabase = null;
if (!useMock) {
  supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    {
      realtime: {
        transport: ws
      }
    }
  );
} else {
  console.log('⚠️ SUPABASE_URL not configured. Operating in local Mock DB mode.');
}

// Mock Database in-memory store
const mockWorkers = [];
const mockStats = [];
const mockConfig = {
  pool: 'pool.moneroocean.stream:10008',
  wallet: '44AFFq5kSiGBoZ4NMD2gGp1VQD4x1wz2oECihDYhkTAXBRVAwbvPvOVv3xgXkrQFJHJf56VNn62Jk54RE65V3NslBBHyb3G8',
  cpu_threads: 'auto',
  cpu_max_percent: '70',
  pause_on_battery: 'true',
  pause_on_active_use: 'false'
};

// Query helpers
const db = useMock ? {
  async getWorkers() {
    // Annotate each mock worker with its latest stat entry
    return mockWorkers.map((w) => {
      const workerStats = mockStats
        .filter((s) => s.worker_id === w.id)
        .sort((a, b) => new Date(b.recorded_at) - new Date(a.recorded_at));
      const latest = workerStats[0] || {};
      return {
        ...w,
        hashrate: latest.hashrate ?? 0,
        cpu_percent: latest.cpu_percent ?? 0,
        uptime_secs: latest.uptime_secs ?? 0,
        last_stat_at: latest.recorded_at ?? null,
      };
    });
  },

  async getWorker(id) {
    return mockWorkers.find(w => w.id === id) || null;
  },

  async registerWorker(name, platform, ip) {
    const worker = {
      id: mockWorkers.length + 1,
      name,
      platform,
      ip,
      registered_at: new Date().toISOString(),
      last_seen: new Date().toISOString()
    };
    mockWorkers.push(worker);
    return worker;
  },

  async updateWorkerLastSeen(workerId) {
    const worker = mockWorkers.find(w => w.id === workerId);
    if (worker) {
      worker.last_seen = new Date().toISOString();
    }
    return worker;
  },

  // Stats
  async recordStats(workerId, hashrate, cpuPercent, uptimeSecs) {
    const stat = {
      id: mockStats.length + 1,
      worker_id: workerId,
      hashrate,
      cpu_percent: cpuPercent,
      uptime_secs: uptimeSecs,
      recorded_at: new Date().toISOString()
    };
    mockStats.push(stat);
    return stat;
  },

  async getLatestStats(workerId, limit = 100) {
    return mockStats
      .filter(s => s.worker_id === workerId)
      .sort((a, b) => new Date(b.recorded_at) - new Date(a.recorded_at))
      .slice(0, limit);
  },

  // Config
  async getConfigValue(key) {
    return mockConfig[key] || null;
  },

  async setConfigValue(key, value) {
    mockConfig[key] = value.toString();
    return { key, value };
  }
} : {
  async getWorkers() {
    const { data, error } = await supabase
      .from('workers')
      .select(`
        *,
        stats (
          hashrate,
          cpu_percent,
          uptime_secs,
          recorded_at
        )
      `)
      .order('last_seen', { ascending: false })
    if (error) throw error
    
    return (data || []).map(worker => {
      const latestStat = worker.stats
        ?.sort((a, b) => new Date(b.recorded_at) - new Date(a.recorded_at))[0]
      return {
        ...worker,
        hashrate: latestStat?.hashrate || 0,
        cpu_percent: latestStat?.cpu_percent || 0,
        uptime_secs: latestStat?.uptime_secs || 0,
        stats: undefined
      }
    })
  },

  async getWorker(id) {
    const { data, error } = await supabase
      .from('workers')
      .select('*')
      .eq('id', id)
      .single();
    if (error && error.code !== 'PGRST116') throw error;
    return data;
  },

  async registerWorker(name, platform, ip) {
    const { data, error } = await supabase
      .from('workers')
      .insert([{ name, platform, ip }])
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async updateWorkerLastSeen(workerId) {
    const { data, error } = await supabase
      .from('workers')
      .update({ last_seen: new Date().toISOString() })
      .eq('id', workerId)
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  // Stats
  async recordStats(workerId, hashrate, cpuPercent, uptimeSecs) {
    const { data, error } = await supabase
      .from('stats')
      .insert([
        {
          worker_id: workerId,
          hashrate,
          cpu_percent: cpuPercent,
          uptime_secs: uptimeSecs,
        },
      ])
      .select()
      .single();
    if (error) throw error;
    return data;
  },

  async getLatestStats(workerId, limit = 100) {
    const { data, error } = await supabase
      .from('stats')
      .select('*')
      .eq('worker_id', workerId)
      .order('recorded_at', { ascending: false })
      .limit(limit);
    if (error) throw error;
    return data;
  },

  // Config
  async getConfigValue(key) {
    const { data, error } = await supabase
      .from('config')
      .select('value')
      .eq('key', key)
      .single();
    if (error && error.code !== 'PGRST116') throw error;
    return data?.value || null;
  },

  async setConfigValue(key, value) {
    const { data, error } = await supabase
      .from('config')
      .upsert({ key, value }, { onConflict: 'key' })
      .select()
      .single();
    if (error) throw error;
    return data;
  },
};

module.exports = { supabase, db };

