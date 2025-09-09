// Serverless function: GET /api/oracle/agent-per-ada?feed=<bech32_address>
// Uses BLOCKFROST_API_KEY env. Returns { agentPerAda, precision, source, method } on success.

const fetchCompat = globalThis.fetch || (async (...args) => (await import('node-fetch')).then(m => m.default(...args)));

// Token name 'OracleFeed' in hex for quick detection within UTXO assets
const ORACLE_FEED_HEX = '4f7261636c6546656564';

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
    const toBigInt = (v) => {
      if (typeof v === 'bigint') return v;
      if (typeof v === 'number') return BigInt(v);
      if (typeof v === 'string' && v.trim() !== '') return BigInt(v);
      return null;
    };
    const walk = (node) => {
      if (!node) return null;
      if (node.map) {
        let priceInt = null, precision = null;
        for (const entry of node.map) {
          const key = entry.k?.int;
          const raw = entry.v?.int;
          const bi = toBigInt(raw);
          if (key === 0 && bi != null) priceInt = bi;
          if (key === 3 && bi != null) precision = bi;
        }
        if (priceInt != null) {
          const precNum = precision != null ? Number(precision) : 0;
          // Return raw integer and precision to caller
          return { price: Number(priceInt), precision: precNum };
        }
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

function summarizePriceMapKeys(jsonVal) {
  try {
    const keys = new Set();
    const visit = (node) => {
      if (!node) return;
      if (node.map) {
        for (const entry of node.map) {
          const key = entry.k?.int;
          if (typeof key === 'number') keys.add(key);
          else if (typeof key === 'string') {
            const n = Number(key);
            if (!Number.isNaN(n)) keys.add(n);
          }
        }
      }
      if (typeof node === 'object') {
        for (const v of Object.values(node)) visit(v);
      }
    };
    visit(jsonVal);
    return Array.from(keys.values()).sort((a,b)=>a-b);
  } catch (_) { return []; }
}

async function fetchDatumJson(base, apiKey, datumHash) {
  try {
    const r = await fetchCompat(`${base}/api/v0/scripts/datum/${datumHash}`, { headers: { project_id: apiKey } });
    if (!r.ok) return null;
    const body = await r.json();
    if (body && body.json_value) return extractFromJson(body.json_value);
    return null;
  } catch (e) {
    console.error('oracle fetch datum json error:', e);
    return null;
  }
}

function hasOracleFeedToken(amountArray) {
  try {
    const amounts = Array.isArray(amountArray) ? amountArray : [];
    return amounts.some(a => typeof a?.unit === 'string' && a.unit.endsWith(ORACLE_FEED_HEX));
  } catch (_) {
    return false;
  }
}

async function extractFromInlineDatum(base, apiKey, inline, debug) {
  // Prefer json_value
  if (inline.json_value) {
    if (debug) {
      try {
        debug.jsonKeys = debug.jsonKeys || [];
        debug.jsonKeys.push(summarizePriceMapKeys(inline.json_value));
      } catch (_) {}
    }
    const out = extractFromJson(inline.json_value);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const adaPerAgent = out.price / Math.pow(10, precision);
      if (!adaPerAgent) return null;
      const agentPerAda = adaPerAgent ? 1 / adaPerAgent : null;
      if (agentPerAda == null) return null;
      return { agentPerAda, precision, source: 'json' };
    }
  }
  // Try datum hash via scripts/datum
  if (inline.hash) {
    const out = await fetchDatumJson(base, apiKey, inline.hash);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const adaPerAgent = out.price / Math.pow(10, precision);
      if (!adaPerAgent) return null;
      const agentPerAda = adaPerAgent ? 1 / adaPerAgent : null;
      if (agentPerAda == null) return null;
      return { agentPerAda, precision, source: 'json' };
    }
  }
  // Try bytes via CBOR
  if (inline.bytes) {
    const out = await decodeCborHex(inline.bytes);
    if (out && typeof out.price === 'number') {
      const precision = typeof out.precision === 'number' ? out.precision : 0;
      const adaPerAgent = out.price / Math.pow(10, precision);
      if (!adaPerAgent) return null;
      const agentPerAda = adaPerAgent ? 1 / adaPerAgent : null;
      if (agentPerAda == null) return null;
      return { agentPerAda, precision, source: 'cbor' };
    }
  }
  return null;
}

async function extractFromDatumHash(base, apiKey, hash, debug) {
  if (!hash) return null;
  try {
    const r = await fetchCompat(`${base}/api/v0/scripts/datum/${hash}`, { headers: { project_id: apiKey } });
    if (!r.ok) return null;
    const body = await r.json();
    if (debug && body?.json_value) {
      try {
        debug.jsonKeys = debug.jsonKeys || [];
        debug.jsonKeys.push(summarizePriceMapKeys(body.json_value));
      } catch (_) {}
    }
    if (body && body.json_value) {
      const out = extractFromJson(body.json_value);
      if (out && typeof out.price === 'number') {
        const precision = typeof out.precision === 'number' ? out.precision : 0;
        const adaPerAgent = out.price / Math.pow(10, precision);
        if (!adaPerAgent) return null;
        const agentPerAda = adaPerAgent ? 1 / adaPerAgent : null;
        if (agentPerAda == null) return null;
        return { agentPerAda, precision, source: 'json' };
      }
    }
    // Fallback: bytes present, decode as CBOR
    if (body && body.bytes) {
      if (debug) { try { debug.bytesSeen = true; } catch (_) {} }
      const out = await decodeCborHex(body.bytes);
      if (out && typeof out.price === 'number') {
        const precision = typeof out.precision === 'number' ? out.precision : 0;
        const adaPerAgent = out.price / Math.pow(10, precision);
        if (!adaPerAgent) return null;
        const agentPerAda = adaPerAgent ? 1 / adaPerAgent : null;
        if (agentPerAda == null) return null;
        return { agentPerAda, precision, source: 'cbor' };
      }
    }
  } catch (e) {
    console.error('oracle fetch datum json error:', e);
  }
  return null;
}

async function tryAddressUtxos(base, apiKey, feed, debug) {
  const url = `${base}/api/v0/addresses/${encodeURIComponent(feed)}/utxos?order=desc&page=1&count=100`;
  const resp = await fetchCompat(url, { headers: { project_id: apiKey } });
  if (!resp.ok) return null;
  const list = await resp.json();
  const oracle = [];
  const others = [];
  for (const utxo of list) {
    if (hasOracleFeedToken(utxo.amount)) oracle.push(utxo); else others.push(utxo);
  }
  // Prefer UTXOs that carry the OracleFeed NFT
  for (const utxo of [...oracle, ...others]) {
    if (debug && utxo?.amount) {
      try { debug.utxoUnits = debug.utxoUnits || []; debug.utxoUnits.push((utxo.amount || []).map(a => a.unit)); } catch (_) {}
    }
    const inline = utxo.inline_datum;
    if (inline) {
      const res = await extractFromInlineDatum(base, apiKey, inline, debug);
      if (res) return { ...res, method: hasOracleFeedToken(utxo.amount) ? 'address_utxos_oracle' : 'address_utxos' };
    }
    // Fallback: try datum hash fields
    const hash = utxo.data_hash || utxo.datum_hash || utxo.plutus_data_hash;
    if (hash) {
      const res = await extractFromDatumHash(base, apiKey, hash, debug);
      if (res) return { ...res, method: hasOracleFeedToken(utxo.amount) ? 'address_utxos_hash_oracle' : 'address_utxos_hash' };
    }
    // Deeper fallback: fetch the transaction's outputs to locate inline datum for this exact UTXO
    try {
      const txh = utxo.tx_hash;
      const outIdx = utxo.output_index;
      if (txh != null && outIdx != null) {
        const txUtxoResp = await fetchCompat(`${base}/api/v0/txs/${txh}/utxos`, { headers: { project_id: apiKey } });
        if (txUtxoResp.ok) {
          const data = await txUtxoResp.json();
          const outputs = Array.isArray(data.outputs) ? data.outputs : [];
          let candidate = outputs.find(o => (o.output_index === outIdx) || (o.index === outIdx));
          if (!candidate && outputs[outIdx]) candidate = outputs[outIdx];
          if (candidate) {
            if (debug) {
              try {
                debug.txProbes = debug.txProbes || [];
                debug.txProbes.push({ tx: txh, outIdx, hasInline: !!candidate.inline_datum, hasHash: !!(candidate.data_hash || candidate.datum_hash || candidate.plutus_data_hash) });
              } catch (_) {}
            }
            if (candidate.inline_datum) {
              const res = await extractFromInlineDatum(base, apiKey, candidate.inline_datum, debug);
              if (res) return { ...res, method: 'address_utxo_tx_output_inline' };
            }
            const dh = candidate.data_hash || candidate.datum_hash || candidate.plutus_data_hash;
            if (dh) {
              const res = await extractFromDatumHash(base, apiKey, dh, debug);
              if (res) return { ...res, method: 'address_utxo_tx_output_hash' };
            }
          }
        }
      }
    } catch (_) {}
  }
  return null;
}

async function tryRecentTxs(base, apiKey, feed, debug) {
  const perPage = 25;
  const maxPages = 12;
  // Pass A: prefer outputs returning to the same feed address
  for (let page = 1; page <= maxPages; page++) {
    const txsResp = await fetchCompat(`${base}/api/v0/addresses/${encodeURIComponent(feed)}/transactions?order=desc&page=${page}&count=${perPage}`, {
      headers: { project_id: apiKey }
    });
    if (!txsResp.ok) break;
    const txs = await txsResp.json();
    if (!Array.isArray(txs) || txs.length === 0) break;
    for (const t of txs) {
      const hash = t.tx_hash;
      const outResp = await fetchCompat(`${base}/api/v0/txs/${hash}/utxos`, { headers: { project_id: apiKey } });
      if (!outResp.ok) continue;
      const data = await outResp.json();
      const outputs = (data.outputs || []);
      const oracleOutputs = outputs.filter(o => hasOracleFeedToken(o.amount));
      const sameAddr = outputs.filter(o => o.address === feed);
      const ordered = [...oracleOutputs, ...sameAddr, ...outputs];
      for (const o of ordered) {
        if (debug && o?.amount) {
          try { debug.outputUnits = debug.outputUnits || []; debug.outputUnits.push((o.amount || []).map(a => a.unit)); } catch (_) {}
        }
        // Try inline first
        if (o.inline_datum) {
          const res = await extractFromInlineDatum(base, apiKey, o.inline_datum, debug);
          if (res) return { ...res, method: hasOracleFeedToken(o.amount) ? 'tx_outputs_oracle' : (o.address === feed ? 'tx_outputs_sameaddr' : 'tx_outputs_any') };
        }
        // Then try datum hash present on the output
        const hashField = o.data_hash || o.datum_hash || o.plutus_data_hash;
        if (hashField) {
          const res = await extractFromDatumHash(base, apiKey, hashField, debug);
          if (res) return { ...res, method: hasOracleFeedToken(o.amount) ? 'tx_outputs_hash_oracle' : (o.address === feed ? 'tx_outputs_hash_sameaddr' : 'tx_outputs_any_hash') };
        }
      }
    }
  }
  return null;
}

export default async function handler(req, res) {
  try {
    const feed = req.query.feed || req.query.address;
    const debugMode = req.query.debug === '1' || req.query.debug === 'true';
    if (!feed) return res.status(400).json({ error: 'Missing feed address ?feed=' });

    const apiKey = process.env.BLOCKFROST_API_KEY;
    if (!apiKey) return res.status(500).json({ error: 'Missing BLOCKFROST_API_KEY env' });

    const base = 'https://cardano-mainnet.blockfrost.io';

    const debug = debugMode ? {} : null;

    const byUtxo = await tryAddressUtxos(base, apiKey, feed, debug);
    if (byUtxo) return res.status(200).json(byUtxo);

    const byTx = await tryRecentTxs(base, apiKey, feed, debug);
    if (byTx) return res.status(200).json(byTx);

    if (debugMode) return res.status(404).json({ error: 'Feed datum not found or unsupported format', feed, debug });
    return res.status(404).json({ error: 'Feed datum not found or unsupported format', feed });
  } catch (err) {
    console.error('oracle proxy error:', err);
    res.status(500).json({ error: 'Oracle proxy error', detail: String(err && err.stack || err) });
  }
} 