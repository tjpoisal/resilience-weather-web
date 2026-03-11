const express = require('express');
const router  = express.Router();

// Minimal session-based auth placeholder
// Swap for real auth (Clerk, Auth0, Supabase) in production

router.post('/demo-pro', (req, res) => {
  req.session.plan = 'pro';
  res.json({ ok: true });
});

router.post('/demo-free', (req, res) => {
  req.session.plan = 'free';
  res.json({ ok: true });
});

router.get('/status', (req, res) => {
  res.json({ plan: req.session?.plan ?? 'free' });
});

router.post('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/');
});

module.exports = router;
