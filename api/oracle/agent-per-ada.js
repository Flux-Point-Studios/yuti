// Serverless function: GET /api/oracle/agent-per-ada?feed=<bech32_address>
// Uses BLOCKFROST_API_KEY env. Returns { agentPerAda, precision, source, method } on success.

// Ensure fetch is available (Node <18 fallback)
const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

// Lazy import cbor only if needed to keep cold start small
async function decodeCborHex(hex) {
  try {
    const { default: cbor } = await import('cbor');
    const buf = Buffer.from(hex.replace(/[^0-9a-fA-F]/g, ''), 'hex');
    const decoded = await cbor.decodeFirst(buf);
    const find = (node) => {
      if (!node) return null;
      if (node instanceof Map) {
        let price = null, precision = null;
        if (node.has(0)) {
          const v = node.get(0);
          if (typeof v === 'bigint' || typeof v === 'number') price = Number(v);
        }
        if (node.has(3)) {
          const p = node.get(3);
          if (typeof p === 'bigint' || typeof p === 'number') precision = Number(p);
        }
        if (price != null) return { price, precision };
        for (const v of node.values()) {
          const r = find(v);
          if (r) return r;
        }
      } else if (Array.isArray(node)) {
        for (const it of node) {
          const r = find(it);
          if (r) return r;
        }
      } else if (typeof node === 'object') {
        for (const v of Object.values(node)) {
          const r = find(v);
          if (r) return r;
        }
      }
      return null;
    };
    return find(decoded);
  } catch (e) {
    console.error('oracle cbor decode error:', e);
    return null;
  }
}

function extractFromJson(jsonVal) {
  try {
    // Look for Charli3 CDDL-style maps
    const walk = (node) => {
      if (!node) return null;
      if (node.map) {
        // Blockfrost style: { map: [ { k:{int:0}, v:{int:334136} }, ... ] }
        let priceInt = null, precision = null;
        for (const entry of node.map) {
          const key = entry.k?.int;
          const val = entry.v?.int;
          if (key === 0 && (typeof val === 'number')) priceInt = val;
          if (key === 3 && (typeof val === 'number')) precision = val;
        }
        if (priceInt != null) return { price: priceInt, precision };
      }
      if (typeof node === 'object') {
        for (const v of Object.values(node)) {
          const r = walk(v);
          if (r) return r;
        }
      }
      return null;
    };
    const res = walk(jsonVal);
    if (res) return res;
  } catch (e) {
    console.error('oracle json extract error:', e);
  }
  return null;
}

export default async function handler(req, res) {
  try {
    const feed = req.query.feed || req.query.address;
    if (!feed) return res.status(400).json({ error: 'Missing feed address ?feed=' });

    const apiKey = process.env.BLOCKFROST_API_KEY;
    if (!apiKey) return res.status(500).json({ error: 'Missing BLOCKFROST_API_KEY env' });

    const base = 'https://cardano-mainnet.blockfrost.io';

    // 1) Try address UTXOs first
    const utxosResp = await fetchCompat(`${base}/api/v0/addresses/${encodeURIComponent(feed)}/utxos?order=desc&page=1`, {
      headers: { project_id: apiKey }
    });
    if (utxosResp.ok) {
      const list = await utxosResp.json();
      for (const utxo of list) {
        const inline = utxo.inline_datum;
        if (!inline) continue;
        if (inline.json_value) {
          const out = extractFromJson(inline.json_value);
          if (out && typeof out.price === 'number') {
            const precision = typeof out.precision === 'number' ? out.precision : 0;
            const agentPerAda = out.price / Math.pow(10, precision);
            return res.status(200).json({ agentPerAda, precision, source: 'json', method: 'address_utxos' });
          }
        } else if (inline.bytes) {
          const out = await decodeCborHex(inline.bytes);
          if (out && typeof out.price === 'number') {
            const precision = typeof out.precision === 'number' ? out.precision : 0;
            const agentPerAda = out.price / Math.pow(10, precision);
            return res.status(200).json({ agentPerAda, precision, source: 'cbor', method: 'address_utxos' });
          }
        }
      }
    }

    // 2) Fallback: latest tx and outputs at this address
    const txsResp = await fetchCompat(`${base}/api/v0/addresses/${encodeURIComponent(feed)}/transactions?order=desc&page=1`, {
      headers: { project_id: apiKey }
    });
    if (txsResp.ok) {
      const txs = await txsResp.json();
      if (Array.isArray(txs) && txs.length) {
        const hash = txs[0].tx_hash;
        const outResp = await fetchCompat(`${base}/api/v0/txs/${hash}/utxos`, { headers: { project_id: apiKey } });
        if (outResp.ok) {
          const data = await outResp.json();
          for (const o of data.outputs || []) {
            if (o.address !== feed) continue;
            const inline = o.inline_datum;
            if (!inline) continue;
            if (inline.json_value) {
              const out = extractFromJson(inline.json_value);
              if (out && typeof out.price === 'number') {
                const precision = typeof out.precision === 'number' ? out.precision : 0;
                const agentPerAda = out.price / Math.pow(10, precision);
                return res.status(200).json({ agentPerAda, precision, source: 'json', method: 'tx_outputs' });
              }
            } else if (inline.bytes) {
              const out = await decodeCborHex(inline.bytes);
              if (out && typeof out.price === 'number') {
                const precision = typeof out.precision === 'number' ? out.precision : 0;
                const agentPerAda = out.price / Math.pow(10, precision);
                return res.status(200).json({ agentPerAda, precision, source: 'cbor', method: 'tx_outputs' });
              }
            }
          }
        }
      }
    }

    return res.status(404).json({ error: 'Feed datum not found or unsupported format' });
  } catch (err) {
    console.error('oracle proxy error:', err);
    res.status(500).json({ error: 'Oracle proxy error', detail: String(err && err.stack || err) });
  }
} 