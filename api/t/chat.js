// Ensure fetch is available (Node 16 fallback)
const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

module.exports = async (req, res) => {
  try {
    const baseUrl = process.env.T_BACKEND_URL || 'https://api.fluxpointstudios.com';
    const apiKey = process.env.T_BACKEND_API_KEY || '';

    if (!apiKey) {
      res.status(500).json({ error: 'Missing T_BACKEND_API_KEY env' });
      return;
    }

    const targetUrl = `${baseUrl.replace(/\/$/, '')}/chat`;

    const upstream = await fetchCompat(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': apiKey,
      },
      body: typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {}),
    });

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    res.status(500).json({ error: 'Proxy error', detail: String(err) });
  }
}; 