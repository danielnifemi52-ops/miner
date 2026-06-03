const WorkerReporter = {
  coordinatorUrl: '',
  agentSecret: '',

  init(url, secret) {
    this.coordinatorUrl = url.replace(/\/$/, '');
    this.agentSecret = secret;
  },

  async register(name) {
    const response = await fetch(`${this.coordinatorUrl}/api/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Agent-Secret': this.agentSecret
      },
      body: JSON.stringify({
        name: name,
        platform: 'web',
        ip: 'web'
      })
    });
    if (!response.ok) {
      throw new Error(`Failed to register: ${response.statusText}`);
    }
    return await response.json();
  },

  async reportStats(workerId, hashrate, uptimeSecs) {
    const response = await fetch(`${this.coordinatorUrl}/api/stats`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Agent-Secret': this.agentSecret
      },
      body: JSON.stringify({
        worker_id: parseInt(workerId),
        hashrate: parseFloat(hashrate),
        cpu_percent: 0,
        uptime_secs: parseInt(uptimeSecs)
      })
    });
    if (!response.ok) {
      throw new Error(`Failed to report stats: ${response.statusText}`);
    }
    return await response.json();
  },

  async fetchConfig() {
    const response = await fetch(`${this.coordinatorUrl}/api/config`, {
      headers: {
        'X-Agent-Secret': this.agentSecret
      }
    });
    if (!response.ok) {
      throw new Error(`Failed to fetch config: ${response.statusText}`);
    }
    return await response.json();
  }
};

// Export for module systems or just run as global
if (typeof module !== 'undefined' && module.exports) {
  module.exports = WorkerReporter;
}
