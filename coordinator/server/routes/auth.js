const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const router = express.Router();

router.post('/login', async (req, res) => {
  const { password } = req.body;

  if (!password) {
    return res.status(400).json({ error: 'Password required' });
  }

  const storedPassword = process.env.ADMIN_PASSWORD || '';

  // Support both bcrypt-hashed and plain-text ADMIN_PASSWORD env vars.
  // If the stored value looks like a bcrypt hash, use bcrypt.compare().
  // Otherwise fall back to a trimmed plain-text comparison.
  let passwordValid = false;
  if (storedPassword.startsWith('$2b$') || storedPassword.startsWith('$2a$')) {
    try {
      passwordValid = await bcrypt.compare(password, storedPassword);
    } catch (err) {
      console.error('bcrypt.compare error:', err);
      passwordValid = false;
    }
  } else {
    passwordValid = password.trim() === storedPassword.trim();
  }

  if (!passwordValid) {
    console.warn(`Login attempt failed at ${new Date().toISOString()}`);
    return res.status(403).json({ error: 'Invalid password' });
  }

  const token = jwt.sign(
    { role: 'admin' },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
  );

  console.log(`Admin login successful at ${new Date().toISOString()}`);
  res.json({ token });
});

module.exports = router;
