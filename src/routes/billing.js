const express = require('express');
const router  = express.Router();

function getStripe() {
  return require('stripe')(process.env.STRIPE_SECRET_KEY);
}

// Create Stripe Checkout session
router.post('/create-checkout', async (req, res) => {
  try {
    const stripe = getStripe();
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      success_url: `${process.env.APP_URL}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url:  `${process.env.APP_URL}/billing/cancel`,
      metadata: { source: 'resilience_weather_web' },
    });
    res.json({ url: session.url });
  } catch (e) {
    console.error('Checkout error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// Stripe webhook — handle subscription events
router.post('/webhook', express.raw({ type: 'application/json' }), (req, res) => {
  const stripe = getStripe();
  const sig = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (e) {
    return res.status(400).send(`Webhook Error: ${e.message}`);
  }
  // Log events — extend with DB writes as needed
  console.log(`Stripe event: ${event.type}`);
  res.json({ received: true });
});

// Check session and grant pro
router.get('/verify/:sessionId', async (req, res) => {
  try {
    const stripe = getStripe();
    const session = await stripe.checkout.sessions.retrieve(req.params.sessionId);
    if (session.payment_status === 'paid') {
      req.session.plan = 'pro';
      req.session.stripeCustomerId = session.customer;
      res.json({ pro: true });
    } else {
      res.json({ pro: false });
    }
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
