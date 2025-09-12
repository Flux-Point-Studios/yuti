export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const { code, code_verifier, redirect_uri, client_id } = req.body || {};
    if (!code || !redirect_uri || !client_id) {
      res.status(400).json({ error: 'Missing parameters' });
      return;
    }

    const tokenUrl = 'https://oauth2.googleapis.com/token';
    const clientSecret = process.env.SMART_WALLET_GOOGLE_CLIENT_SECRET || '';

    const form = new URLSearchParams();
    form.set('code', code);
    form.set('client_id', client_id);
    form.set('redirect_uri', redirect_uri);
    form.set('grant_type', 'authorization_code');

    if (code_verifier) {
      form.set('code_verifier', code_verifier);
    }
    if (clientSecret) {
      form.set('client_secret', clientSecret);
    }

    const upstream = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
    });

    const text = await upstream.text();
    const ct = upstream.headers.get('content-type') || 'application/json;charset=utf-8';
    res.status(upstream.status);
    res.setHeader('Content-Type', ct);

    // Pass-through JSON or text transparently
    try {
      res.send(JSON.parse(text));
    } catch {
      res.send(text);
    }
  } catch (err) {
    res.status(500).json({ error: 'google token exchange error', detail: String(err && err.stack || err) });
  }
} 