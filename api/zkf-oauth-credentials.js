const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    const apiBase = process.env.SMART_WALLET_API_BASE || 'https://wallet-api.zkfold.io';
    const apiKey = process.env.SMART_WALLET_API_KEY || '';
    const url = `${apiBase.replace(/\/$/, '')}/v0/oauth/credentials`;

    const headers = {};
    if (apiKey) headers['api-key'] = apiKey;

    const upstream = await fetchCompat(url, { method: 'GET', headers });
    const text = await upstream.text();
    const ct = upstream.headers.get('content-type') || 'application/json;charset=utf-8';

    res.status(upstream.status);
    res.setHeader('Content-Type', ct);
    res.send(text);
  } catch (err) {
    console.error('zkFold oauth credentials proxy error:', err);
    res.status(500).json({ error: 'zkFold credentials proxy error', detail: String(err && err.stack || err) });
  }
} 