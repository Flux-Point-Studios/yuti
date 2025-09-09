// api/blockfrost/[...path].js

const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    const segments = req.query.path || [];
    const path = Array.isArray(segments) ? segments.join('/') : String(segments || '');
    const qs = Object.entries(req.query)
      .filter(([k]) => k !== 'path')
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(Array.isArray(v) ? v[0] : v)}`)
      .join('&');
    const base = process.env.BLOCKFROST_BASE || 'https://cardano-mainnet.blockfrost.io';
    const apiKey = process.env.BLOCKFROST_API_KEY;
    if (!apiKey) {
      res.status(500).json({ error: 'Missing BLOCKFROST_API_KEY env on server' });
      return;
    }
    const url = `${base.replace(/\/$/, '')}/api/v0/${path}${qs ? `?${qs}` : ''}`;
    const upstream = await fetchCompat(url, {
      method: 'GET',
      headers: {
        'project_id': apiKey,
      },
    });
    const text = await upstream.text();
    const ct = upstream.headers.get('content-type') || '';
    if (!ct.includes('application/json')) {
      res.status(502).json({ error: 'Upstream non-JSON', detail: text.slice(0, 200) });
      return;
    }
    res.status(upstream.status);
    res.setHeader('Content-Type', ct);
    res.send(text);
  } catch (err) {
    console.error('Blockfrost proxy error:', err);
    res.status(500).json({ error: 'Blockfrost proxy error', detail: String(err && err.stack || err) });
  }
} 