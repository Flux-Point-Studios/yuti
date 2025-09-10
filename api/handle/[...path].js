module.exports = async (req, res) => {
  // CORS preflight
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  try {
    const parts = Array.isArray(req.query.path) ? req.query.path : [req.query.path].filter(Boolean);
    const joined = parts.join('/');

    // Preserve original query string
    const originalUrl = req.url || '';
    const qIndex = originalUrl.indexOf('?');
    const queryString = qIndex >= 0 ? originalUrl.substring(qIndex) : '';

    const targetUrl = `https://api.handle.me/${joined}${queryString}`;

    const upstream = await fetch(targetUrl, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
    });

    const bodyText = await upstream.text();

    // Pass-through status and content-type; add caching to ease rate limits
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json; charset=utf-8');
    // Cache at the edge for 5 minutes; allow stale while revalidating for 10 minutes
    res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');

    res.status(upstream.status).send(bodyText);
  } catch (err) {
    res.status(500).json({ error: 'Handle proxy failed', message: String(err) });
  }
}; 