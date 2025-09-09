// api/blockfrost/[...path].js

const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

export default async function handler(req, res) {
  try {
    const segments = req.query.path || [];
    const path = Array.isArray(segments) ? segments.join('/') : String(segments || '');
    const base = process.env.BLOCKFROST_BASE || 'https://cardano-mainnet.blockfrost.io';
    const apiKey = process.env.BLOCKFROST_API_KEY;
    if (!apiKey) {
      res.status(500).json({ error: 'Missing BLOCKFROST_API_KEY env on server' });
      return;
    }
    const url = `${base.replace(/\/$/, '')}/api/v0/${path}`;
    const upstream = await fetchCompat(url, {
      method: req.method,
      headers: {
        'project_id': apiKey,
        'Content-Type': 'application/json',
      },
    });
    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    console.error('Blockfrost proxy error:', err);
    res.status(500).json({ error: 'Blockfrost proxy error', detail: String(err && err.stack || err) });
  }
} 