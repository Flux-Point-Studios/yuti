// GET /api/blockfrost-proxy?path=<route> relays the wallet's chain reads to Iagon Insight,
// which serves the Blockfrost API under /api/v0. INSIGHT_API_KEY is server-only. Only the
// routes the Flutter client sends are relayed, so the key is not an open Cardano API.

const INSIGHT_MAINNET_V0 = 'https://mainnet.insight.iagon.com/api/v0';

const WALLET_ROUTES = [
  /^addresses\/[0-9A-Za-z]+(\/utxos)?$/,
  /^accounts\/stake1[0-9a-z]+(\/addresses(\/assets)?)?$/,
];

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }
  const path = req.query.path;
  if (typeof path !== 'string' || !WALLET_ROUTES.some((route) => route.test(path))) {
    res.status(403).json({ error: 'Route not relayed' });
    return;
  }
  const apiKey = process.env.INSIGHT_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: 'Missing INSIGHT_API_KEY env on server' });
    return;
  }

  let upstream;
  try {
    upstream = await fetch(`${INSIGHT_MAINNET_V0}/${path}`, { headers: { project_id: apiKey } });
  } catch (err) {
    console.error('Insight relay request failed:', err);
    res.status(502).json({ error: 'Upstream unreachable' });
    return;
  }
  const contentType = upstream.headers.get('content-type') || '';
  const text = await upstream.text();
  if (!contentType.includes('application/json')) {
    res.status(502).json({ error: 'Upstream non-JSON' });
    return;
  }
  res.status(upstream.status);
  res.setHeader('Content-Type', contentType);
  res.send(text);
}
