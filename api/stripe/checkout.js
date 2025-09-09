// api/stripe/checkout.js

const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    const { plan, userId, email, successUrl, cancelUrl } = req.body || {};
    if (!plan || !userId || !email) {
      res.status(400).json({ error: 'Missing required fields: plan, userId, email' });
      return;
    }

    const secret = process.env.STRIPE_SECRET_KEY;
    const pricePremium = process.env.STRIPE_PRICE_PREMIUM; // price_xxx for Premium
    if (!secret || !pricePremium) {
      res.status(500).json({ error: 'Missing Stripe env (STRIPE_SECRET_KEY, STRIPE_PRICE_PREMIUM)' });
      return;
    }

    const priceId = plan === 'PREMIUM' ? pricePremium : pricePremium;
    const origin = (req.headers['x-forwarded-proto'] ? req.headers['x-forwarded-proto'] + '://' : 'https://') + (req.headers.host || '');
    const okSuccess = successUrl || `${origin}/payment-success?status=success&session_id={CHECKOUT_SESSION_ID}`;
    const okCancel = cancelUrl || `${origin}/pricing?status=cancel`;

    const body = new URLSearchParams({
      mode: 'subscription',
      'line_items[0][price]': priceId,
      'line_items[0][quantity]': '1',
      success_url: okSuccess,
      cancel_url: okCancel,
      client_reference_id: userId,
      customer_email: email,
    });

    const upstream = await fetchCompat('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${secret}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    });

    const text = await upstream.text();
    if (!upstream.ok) {
      console.error('Stripe checkout error:', text);
      res.status(upstream.status).json({ error: 'Stripe error', detail: text });
      return;
    }
    const data = JSON.parse(text);
    res.status(200).json({ url: data.url, id: data.id });
  } catch (err) {
    console.error('stripe checkout error:', err);
    res.status(500).json({ error: 'Checkout error', detail: String(err && err.stack || err) });
  }
} 