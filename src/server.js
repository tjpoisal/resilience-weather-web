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

// Home — landing page (or redirect to dashboard if authenticated)
app.get('/', (req, res) => {
  if (req.session?.email) return res.redirect('/dashboard');
  res.render('home');
});

// Dashboard — authenticated users only
app.get('/dashboard', async (req, res) => {
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
  if (req.session?.email && req.session?.plan === 'pro') return res.redirect('/');
  res.render('login');
});


// Download page
app.get('/download', (req, res) => {
  const APP_VERSION = process.env.APP_VERSION || '1.0.0';
  const APP_URL     = process.env.APP_URL || 'http://localhost:3000';
  
  // These will be populated when builds are ready
  const androidApkUrl   = process.env.ANDROID_APK_URL   || null;
  const iosManifestUrl  = process.env.IOS_MANIFEST_URL  || null;

  res.render('download', {
    isPro: req.isPro,
    androidApkUrl,
    iosManifestUrl,
    androidVersion: APP_VERSION,
    iosVersion:     APP_VERSION,
    androidSize:    process.env.ANDROID_APK_SIZE || null,
  });
});

// iOS OTA manifest (plist)
app.get('/ios/manifest.plist', (req, res) => {
  const APP_URL    = process.env.APP_URL || 'http://localhost:3000';
  const ipaUrl     = process.env.IOS_IPA_URL || `${APP_URL}/ios/ResilienceWeather.ipa`;
  const version    = process.env.APP_VERSION || '1.0.0';
  const bundleId   = process.env.IOS_BUNDLE_ID || 'com.getstackmax.resilienceweather';

  res.set('Content-Type', 'text/xml');
  res.send(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${ipaUrl}</string>
        </dict>
        <dict>
          <key>kind</key><string>display-image</string>
          <key>url</key><string>${APP_URL}/images/icon-57.png</string>
        </dict>
        <dict>
          <key>kind</key><string>full-size-image</string>
          <key>url</key><string>${APP_URL}/images/icon-512.png</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${bundleId}</string>
        <key>bundle-version</key><string>${version}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>Resilience Weather</string>
        <key>subtitle</key><string>by Get Stack MAX LLC</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>`);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🌩  Resilience Weather Web running on port ${PORT}`));


