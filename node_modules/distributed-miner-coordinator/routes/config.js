const express = require('express');
const { db } = require('../db/supabase');
const authAgent = require('../middleware/authAgent');
const authJwt = require('../middleware/authJwt');
const jwt = require('jsonwebtoken');
const router = express.Router();

// Get mining config (accessible by dashboard [authJwt] OR agents [authAgent])
router.get('/', async (req, res) => {
  const agentSecret = req.headers['x-agent-secret'];
  const authHeader = req.headers.authorization;
  let authenticated = false;

  if (agentSecret && agentSecret === process.env.AGENT_SECRET) {
    authenticated = true;
  } else if (authHeader) {
    const token = authHeader.split(' ')[1];
    if (token) {
      try {
        jwt.verify(token, process.env.JWT_SECRET);
        authenticated = true;
      } catch (err) {
        // Fall through
      }
    }
  }

  if (!authenticated) {
    return res.status(401).json({ error: 'Unauthorized. Agent secret or JWT required.' });
  }

  try {
    const config = {
      pool: await db.getConfigValue('pool') || 'pool.moneroocean.stream:10008',
      wallet: await db.getConfigValue('wallet') || '',
      cpu_threads: await db.getConfigValue('cpu_threads') || 'auto',
      cpu_max_percent: parseInt(await db.getConfigValue('cpu_max_percent') || '70'),
      pause_on_battery: (await db.getConfigValue('pause_on_battery')) === 'true',
      pause_on_active_use: (await db.getConfigValue('pause_on_active_use')) === 'true',
    };
    res.json(config);
  } catch (error) {
    console.error('Get config error:', error);
    res.status(500).json({ error: 'Failed to fetch config' });
  }
});

// Get mining config for backward compatibility (agent endpoint)
router.get('/mining', authAgent, async (req, res) => {
  try {
    const config = {
      pool: await db.getConfigValue('pool') || 'pool.moneroocean.stream:10008',
      wallet: await db.getConfigValue('wallet') || '',
      cpu_threads: await db.getConfigValue('cpu_threads') || 'auto',
      cpu_max_percent: parseInt(await db.getConfigValue('cpu_max_percent') || '70'),
      pause_on_battery: (await db.getConfigValue('pause_on_battery')) === 'true',
      pause_on_active_use: (await db.getConfigValue('pause_on_active_use')) === 'true',
    };
    res.json(config);
  } catch (error) {
    console.error('Get config error:', error);
    res.status(500).json({ error: 'Failed to fetch config' });
  }
});

// Update config (dashboard endpoint)
router.patch('/', authJwt, async (req, res) => {
  try {
    const { key, value } = req.body;
    if (!key || value === undefined) {
      return res.status(400).json({ error: 'key and value are required' });
    }

    const result = await db.setConfigValue(key, value);
    res.json({ success: true, config: result });
  } catch (error) {
    console.error('Update config error:', error);
    res.status(500).json({ error: 'Failed to update config' });
  }
});

module.exports = router;
