require('dotenv').config();
const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const path = require('path');

const app = express();

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '../views'));
app.use(express.static(path.join(__dirname, '../public')));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
app.use(session({
  secret: process.env.SESSION_SECRET || 'resilience-secret',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 7 * 24 * 60 * 60 * 1000 },
}));

// Middleware: attach plan to every request
app.use((req, _res, next) => {
  req.isPro = req.session?.plan === 'pro';
  next();
});

// Health check endpoint (no DB required)
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Home — landing page
app.get('/', (req, res) => {
  res.render('home', { appUrl: process.env.APP_URL || 'http://localhost:3000' });
});

// Dashboard — placeholder
app.get('/dashboard', async (req, res) => {
  res.render('dashboard', {
    isPro: req.isPro,
    plan: req.session?.plan ?? 'free',
    userName: req.session?.name ?? null,
    stripeKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    priceId: process.env.STRIPE_PRICE_ID || '',
  });
});

// Paywall
app.get('/upgrade', (req, res) => {
  if (req.isPro) return res.redirect('/');
  res.render('paywall', {
    stripeKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    priceId: process.env.STRIPE_PRICE_ID || '',
    appUrl: process.env.APP_URL || 'http://localhost:3000',
  });
});

// API: Get weather alerts for user (with geolocation)
app.post('/api/weather/alerts', express.json(), (req, res) => {
  const { latitude, longitude } = req.body;
  
  if (!latitude || !longitude) {
    return res.status(400).json({ error: 'Latitude and longitude required' });
  }

  // TODO: Fetch from NOAA API based on coordinates
  res.json({
    location: { latitude, longitude },
    alerts: [],
    nextCheck: new Date(Date.now() + 15 * 60000).toISOString(), // 15 min from now
  });
});

// API: Register for push notifications
app.post('/api/notifications/subscribe', express.json(), (req, res) => {
  const { subscription, preferences } = req.body;
  
  // TODO: Store subscription in database
  // preferences should include: [ 'rain', 'snow', 'highwind', 'uv', 'allergy' ]
  
  res.json({ success: true, message: 'Subscribed to notifications' });
});

const resilience = require('./routes/resilience');
app.use('/api', resilience);
// Error handling
app.use((err, req, res, next) => {
  console.error('Error:', err.message);
  res.status(500).json({ error: 'Internal server error', message: err.message });
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ Resilience Weather API listening on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
