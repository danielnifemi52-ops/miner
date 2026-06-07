const express = require('express');
const { db } = require('../db/supabase');
const authAgent = require('../middleware/authAgent');
const authJwt = require('../middleware/authJwt');
const router = express.Router();

// Register a new worker (agent endpoint)
router.post('/register', authAgent, async (req, res) => {
  try {
    const { name, platform, ip } = req.body;

    if (!name || !platform) {
      return res.status(400).json({ error: 'name and platform required' });
    }

    const worker = await db.registerWorker(name, platform, ip || '');
    res.status(201).json(worker);
  } catch (error) {
    console.error('Register worker error:', error);
    res.status(500).json({ error: 'Failed to register worker' });
  }
});

// Report stats (agent endpoint)
router.post('/stats', authAgent, async (req, res) => {
  try {
    const { worker_id, hashrate, cpu_percent, uptime_secs } = req.body;

    if (!worker_id) {
      return res.status(400).json({ error: 'worker_id required' });
    }

    // Update last seen
    await db.updateWorkerLastSeen(worker_id);

    // Record stats
    const stats = await db.recordStats(
      worker_id,
      hashrate || 0,
      cpu_percent || 0,
      uptime_secs || 0
    );

    res.json({ success: true, stats });
  } catch (error) {
    console.error('Stats endpoint error:', error);
    res.status(500).json({ error: 'Failed to record stats' });
  }
});

// Get all workers (dashboard endpoint)
// GET /api/workers       — primary route (dashboard & tests)
// GET /api/workers/all   — backwards-compatible alias
async function handleGetWorkers(req, res) {
  try {
    console.log('[workers] GET /workers called');
    const workers = await db.getWorkers();
    console.log(`[workers] returning ${workers.length} workers`);
    res.json(workers);
  } catch (error) {
    console.error('Get workers error:', error);
    res.status(500).json({ error: 'Failed to fetch workers' });
  }
}

router.get('/workers', authJwt, handleGetWorkers);
router.get('/workers/all', authJwt, handleGetWorkers);

module.exports = router;
