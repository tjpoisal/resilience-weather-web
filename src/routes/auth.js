const express  = require('express');
const router   = express.Router();
const crypto   = require('crypto');
const { getUser, createUser, grantPro } = require('../lib/users');

// Magic link tokens (in-memory, swap for Redis/DB in prod)
const magicTokens = new Map(); // token -> { email, expires }

function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}

// ─── POST /auth/login — passwordless magic link OR direct for known Pro ───────
router.post('/login', async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'Email required' });
  const lower = email.toLowerCase().trim();

  try {
    // Check if user exists
    let user = await getUser(lower);

    // First time — create account
    if (!user) user = await createUser(lower);

    // Hardcoded forever-Pro accounts get instant access (no magic link)
    const FOREVER_PRO = new Set(['tjpoisal@gmail.com']);
    if (FOREVER_PRO.has(lower)) {
      req.session.email = lower;
      req.session.plan  = 'pro';
      req.session.name  = user.name || 'Tim';
      return res.json({ ok: true, plan: 'pro', name: req.session.name, method: 'instant' });
    }

    // Generate magic link token
    const token = generateToken();
    magicTokens.set(token, { email: lower, expires: Date.now() + 15 * 60 * 1000 });

    // In production: send email with magic link
    // For now: return token directly (dev mode)
    const magicUrl = `${process.env.APP_URL || 'http://localhost:3000'}/auth/verify?token=${token}`;

    console.log(`Magic link for ${lower}: ${magicUrl}`);

    res.json({
      ok: true,
      method: 'magic_link',
      message: 'Check your email for a sign-in link.',
      // dev only — remove in prod:
      devUrl: process.env.NODE_ENV !== 'production' ? magicUrl : undefined,
    });
  } catch (e) {
    console.error('Login error:', e);
    res.status(500).json({ error: 'Login failed. Try again.' });
  }
});

// ─── GET /auth/verify?token=xxx — magic link click ───────────────────────────
router.get('/verify', async (req, res) => {
  const { token } = req.query;
  if (!token) return res.redirect('/login?error=invalid');

  const entry = magicTokens.get(token);
  if (!entry || Date.now() > entry.expires) {
    return res.redirect('/login?error=expired');
  }

  magicTokens.delete(token);

  try {
    const user = await getUser(entry.email) || await createUser(entry.email);
    req.session.email = entry.email;
    req.session.plan  = user.plan || 'free';
    req.session.name  = user.name || entry.email.split('@')[0];
    res.redirect('/dashboard');
  } catch (e) {
    res.redirect('/login?error=failed');
  }
});

// ─── GET /auth/status ──────────────────────────────────────────────────────
router.get('/status', (req, res) => {
  res.json({
    email: req.session?.email ?? null,
    plan:  req.session?.plan  ?? 'free',
    name:  req.session?.name  ?? null,
    loggedIn: !!req.session?.email,
  });
});

// ─── POST /auth/logout ─────────────────────────────────────────────────────
router.post('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/'));
});

// ─── Stripe webhook helpers — called from billing.js ──────────────────────
router.grantProByEmail = grantPro;

module.exports = router;
