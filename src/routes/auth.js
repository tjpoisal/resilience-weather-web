const express = require('express');
const router  = express.Router();
const crypto  = require('crypto');
const { getUser, createUser, grantPro } = require('../lib/users');

// ─── Pro accounts — instant login, no magic link ─────────────────────────────
const FOREVER_PRO = new Set([
  'tjpoisal@gmail.com',
  'tim@getstackmax.com',
]);

// ─── POST /auth/login ─────────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'Email required' });
  const lower = email.toLowerCase().trim();

  // Basic email format check
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(lower)) {
    return res.status(400).json({ error: 'Invalid email address' });
  }

  try {
    let user = await getUser(lower);
    if (!user) user = await createUser(lower);

    // Pro accounts get instant session
    if (FOREVER_PRO.has(lower)) {
      req.session.email = lower;
      req.session.plan  = 'pro';
      req.session.name  = user.name || 'Tim';
      return res.json({ ok: true, plan: 'pro', name: req.session.name, redirect: '/dashboard' });
    }

    // All other accounts: auto-create session as free
    // (No email infrastructure yet — log them in directly)
    req.session.email = lower;
    req.session.plan  = user.plan || 'free';
    req.session.name  = user.name || lower.split('@')[0];
    return res.json({
      ok: true,
      plan: req.session.plan,
      name: req.session.name,
      redirect: '/dashboard',
    });

  } catch (e) {
    console.error('Login error:', e);
    res.status(500).json({ error: 'Login failed. Try again.' });
  }
});

// ─── GET /auth/status ─────────────────────────────────────────────────────────
router.get('/status', (req, res) => {
  res.json({
    email:    req.session?.email   ?? null,
    plan:     req.session?.plan    ?? 'free',
    name:     req.session?.name    ?? null,
    loggedIn: !!req.session?.email,
  });
});

// ─── POST /auth/logout ────────────────────────────────────────────────────────
router.post('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/'));
});

// ─── Stripe webhook helper ────────────────────────────────────────────────────
router.grantProByEmail = grantPro;

module.exports = router;
