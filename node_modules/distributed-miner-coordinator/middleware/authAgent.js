const authAgent = (req, res, next) => {
  const agentSecret = req.headers['x-agent-secret'];

  if (!agentSecret) {
    return res.status(401).json({ error: 'Missing X-Agent-Secret header' });
  }

  if (agentSecret !== process.env.AGENT_SECRET) {
    return res.status(403).json({ error: 'Invalid agent secret' });
  }

  next();
};

module.exports = authAgent;
