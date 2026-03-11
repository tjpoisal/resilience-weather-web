require('dotenv').config();
const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const path = require('path');

const billingRouter = require('./routes/billing');
const weatherRouter = require('./routes/weather');
const authRouter    = require('./routes/auth');

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

app.use('/billing', billingRouter);
app.use('/weather', weatherRouter);
app.use('/auth',    authRouter);

// Home — dashboard
app.get('/', async (req, res) => {
  res.render('dashboard', {
    isPro: req.isPro,
    plan: req.session?.plan ?? 'free',
    userName: req.session?.name ?? null,
    stripeKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    priceId: process.env.STRIPE_PRICE_ID || '',
  });
});

// Paywall page
app.get('/upgrade', (req, res) => {
  if (req.isPro) return res.redirect('/');
  res.render('paywall', {
    stripeKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    priceId: process.env.STRIPE_PRICE_ID || '',
    appUrl: process.env.APP_URL || 'http://localhost:3000',
  });
});

// Stripe success / cancel
app.get('/billing/success', (req, res) => {
  req.session.plan = 'pro';
  res.render('success', { isPro: true });
});
app.get('/billing/cancel', (req, res) => {
  res.redirect('/upgrade');
});

// Portal — manage subscription
app.get('/billing/portal', async (req, res) => {
  if (!req.session.stripeCustomerId) return res.redirect('/upgrade');
  try {
    const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
    const session = await stripe.billingPortal.sessions.create({
      customer: req.session.stripeCustomerId,
      return_url: process.env.APP_URL + '/',
    });
    res.redirect(session.url);
  } catch (e) {
    res.redirect('/');
  }
});

// Login page
app.get('/login', (req, res) => {
  if (req.session?.plan === 'pro') return res.redirect('/');
  res.render('login');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🌩  Resilience Weather Web running on port ${PORT}`));


