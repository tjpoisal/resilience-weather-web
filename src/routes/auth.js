const express = require('express');
const router  = express.Router();
const crypto  = require('crypto');

// ─── Pro users — email : hashed password ─────────────────────────────────
// To generate a hash: node -e "const c=require('crypto');console.log(c.createHash('sha256').update('yourpassword').digest('hex'))"
const PRO_USERS = {
  'tjpoisal@gmail.com': {
    passwordHash: null, // set on first login via /auth/set-password, or hardcoded below
    plan: 'pro',
    name: 'Tim',
    forever: true, // never expires
  }
};

// ─── Lifetime Pro emails (always Pro, no password needed for demo) ────────
const LIFETIME_PRO = new Set(['tjpoisal@gmail.com']);

function hashPassword(pw) {
  return crypto.createHash('sha256').update(pw + 'rw-salt-2026').digest('hex');
}

// POST /auth/login
router.post('/login', (req, res) => {
  const { email, password } = req.body;
  if (!email) return res.status(400).json({ error: 'Email required' });

  const lower = email.toLowerCase().trim();

  // Lifetime Pro — just email, no password needed on web
  if (LIFETIME_PRO.has(lower)) {
    req.session.email = lower;
    req.session.plan  = 'pro';
    req.session.name  = PRO_USERS[lower]?.name ?? 'Pro User';
    return res.json({ ok: true, plan: 'pro', name: req.session.name });
  }

  // Regular users
  const user = PRO_USERS[lower];
  if (!user) return res.status(401).json({ error: 'Account not found.' });
  if (user.passwordHash && hashPassword(password || '') !== user.passwordHash) {
    return res.status(401).json({ error: 'Incorrect password.' });
  }

  req.session.email = lower;
  req.session.plan  = user.plan;
  req.session.name  = user.name;
  res.json({ ok: true, plan: user.plan, name: user.name });
});

// POST /auth/logout
router.post('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/');
});

// GET /auth/status
router.get('/status', (req, res) => {
  res.json({
    email: req.session?.email ?? null,
    plan:  req.session?.plan  ?? 'free',
    name:  req.session?.name  ?? null,
  });
});

// POST /auth/set-password  (first-time setup for Pro users)
router.post('/set-password', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email + password required' });
  const lower = email.toLowerCase().trim();
  if (!PRO_USERS[lower]) return res.status(404).json({ error: 'Account not found' });
  PRO_USERS[lower].passwordHash = hashPassword(password);
  res.json({ ok: true, message: 'Password set. You can now log in.' });
});

// Legacy demo routes (keep for testing)
router.post('/demo-pro',  (req, res) => { req.session.plan = 'pro';  res.json({ ok: true }); });
router.post('/demo-free', (req, res) => { req.session.plan = 'free'; res.json({ ok: true }); });

module.exports = router;
