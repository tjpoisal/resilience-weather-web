const express  = require('express');
const router   = express.Router();
const { grantPro, revokePro } = require('../lib/users');

function getStripe() {
  return require('stripe')(process.env.STRIPE_SECRET_KEY);
}

// ─── Create Stripe Checkout session ──────────────────────────────────────────
router.post('/create-checkout', async (req, res) => {
  try {
    const stripe = getStripe();
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      customer_email: req.session?.email || undefined,
      success_url: `${process.env.APP_URL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:  `${process.env.APP_URL}/billing/cancel`,
      metadata: { source: 'resilience_weather_web' },
    });
    res.json({ url: session.url });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ─── Stripe webhook ────────────────────────────────────────────────────────
router.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const stripe = getStripe();
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature'], process.env.STRIPE_WEBHOOK_SECRET);
  } catch (e) {
    return res.status(400).send(`Webhook Error: ${e.message}`);
  }

  try {
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      if (session.customer_email) {
        await grantPro(session.customer_email, session.customer);
        console.log(`✅ Pro granted: ${session.customer_email}`);
      }
    }
    if (event.type === 'customer.subscription.deleted') {
      const sub = event.data.object;
      const customer = await stripe.customers.retrieve(sub.customer);
      if (customer.email) {
        await revokePro(customer.email);
        console.log(`⛔ Pro revoked: ${customer.email}`);
      }
    }
  } catch (e) {
    console.error('Webhook handler error:', e);
  }

  res.json({ received: true });
});

// ─── Verify session after checkout + grant Pro ────────────────────────────
router.get('/success', async (req, res) => {
  try {
    if (req.query.session_id) {
      const stripe = getStripe();
      const session = await stripe.checkout.sessions.retrieve(req.query.session_id);
      if (session.payment_status === 'paid') {
        const email = session.customer_email || req.session?.email;
        if (email) {
          await grantPro(email, session.customer);
          req.session.plan = 'pro';
          req.session.email = email;
          req.session.stripeCustomerId = session.customer;
        }
      }
    }
  } catch (e) {
    console.error('Success handler error:', e);
  }
  res.render('success', { isPro: true });
});

router.get('/cancel', (_req, res) => res.redirect('/upgrade'));

// ─── Billing portal ────────────────────────────────────────────────────────
router.get('/portal', async (req, res) => {
  const customerId = req.session?.stripeCustomerId;
  if (!customerId) return res.redirect('/upgrade');
  try {
    const stripe = getStripe();
    const portal = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: `${process.env.APP_URL}/dashboard`,
    });
    res.redirect(portal.url);
  } catch (e) {
    res.redirect('/dashboard');
  }
});

module.exports = router;
