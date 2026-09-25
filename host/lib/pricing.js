'use strict'

// API list prices for the `usage` cost estimate. The one place to update.
//
// This is an ESTIMATE: tokens x public pay-as-you-go API prices. On a
// subscription plan (Claude Pro/Max, ChatGPT Plus/Pro) nothing is billed
// per token; the figure is the "API-equivalent cost" of the same work.
//
// USD per million tokens. Models are matched by id, then by the longest id
// that the transcript's model starts with followed by "-" (so dated ids
// such as claude-haiku-4-5-20251001 match claude-haiku-4-5). A model not
// listed is reported under `pricing.unpriced` and costs null.
//
// Updating: change the numbers, add ids, bump AS_OF. Costs are computed
// when `usage` answers, never stored, so a new table applies to history.

const AS_OF = '2026-09-25'

const SOURCES = {
  claude: 'Anthropic API list prices (claude.com/pricing; Claude API skill model table cached 2026-06-24). ' +
    'Cache writes: 1.25x input (5 min), 2x input (1 h). Fast mode: 2x.',
  codex: 'OpenAI API list prices for the GPT-5 family as last known (openai.com/api/pricing); verify before relying on them.'
}

// input, output, cacheWrite5m, cacheWrite1h, cacheRead; fast: multiplier
// for `usage.speed: "fast"` (research preview) where it exists.
const claude = (input, output, cacheRead, extra = {}) => ({
  input, output, cacheWrite5m: input * 1.25, cacheWrite1h: input * 2, cacheRead, ...extra
})

const CLAUDE = {
  'claude-fable-5-1': claude(10, 50, 0.25),
  'claude-mythos-5-1': claude(10, 50, 0.25),
  'claude-fable-5': claude(10, 50, 1),
  'claude-mythos-5': claude(10, 50, 1),
  'claude-mythos-preview': claude(10, 50, 1),
  'claude-opus-5-5': claude(4, 20, 0.2, { fast: 2 }),
  'claude-opus-5': claude(5, 25, 0.5, { fast: 2 }),
  'claude-opus-4-8': claude(5, 25, 0.5),
  'claude-opus-4-7': claude(5, 25, 0.5),
  'claude-opus-4-6': claude(5, 25, 0.5),
  'claude-opus-4-5': claude(5, 25, 0.5),
  'claude-opus-4-1': claude(15, 75, 1.5),
  'claude-opus-4-0': claude(15, 75, 1.5),
  'claude-opus-4': claude(15, 75, 1.5),
  'claude-sonnet-5': claude(2, 10, 0.2),
  'claude-sonnet-4-6': claude(3, 15, 0.3),
  'claude-sonnet-4-5': claude(3, 15, 0.3),
  'claude-sonnet-4-0': claude(3, 15, 0.3),
  'claude-sonnet-4': claude(3, 15, 0.3),
  'claude-3-7-sonnet': claude(3, 15, 0.3),
  'claude-haiku-4-5': claude(1, 5, 0.1),
  'claude-3-5-haiku': claude(0.8, 4, 0.08),
  'claude-3-haiku': claude(0.25, 1.25, 0.03)
}

// OpenAI: input_tokens include the cached ones; cached input has its own
// price, there is no cache-write charge.
const openai = (input, output, cacheRead) => ({ input, output, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead })

const CODEX = {
  'gpt-5.2-codex': openai(1.75, 14, 0.175),
  'gpt-5.2': openai(1.75, 14, 0.175),
  'gpt-5.1-codex-max': openai(1.25, 10, 0.125),
  'gpt-5.1-codex-mini': openai(0.25, 2, 0.025),
  'gpt-5.1-codex': openai(1.25, 10, 0.125),
  'gpt-5.1': openai(1.25, 10, 0.125),
  'gpt-5-codex-mini': openai(0.25, 2, 0.025),
  'gpt-5-codex': openai(1.25, 10, 0.125),
  'gpt-5-mini': openai(0.25, 2, 0.025),
  'gpt-5-nano': openai(0.05, 0.4, 0.005),
  'gpt-5': openai(1.25, 10, 0.125),
  'codex-mini-latest': openai(1.5, 6, 0.375),
  'o4-mini': openai(1.1, 4.4, 0.275),
  o3: openai(2, 8, 0.5),
  'gpt-4.1': openai(2, 8, 0.5)
}

const TABLES = { claude: CLAUDE, codex: CODEX }
const SORTED = {}
for (const [agent, table] of Object.entries(TABLES)) {
  SORTED[agent] = Object.keys(table).sort((a, b) => b.length - a.length)
}

// The price entry for `model`, or null.
function priceFor (agent, model) {
  const table = TABLES[agent]
  if (!table || typeof model !== 'string' || !model) return null
  const id = model.toLowerCase()
  if (table[id]) return table[id]
  for (const key of SORTED[agent]) {
    if (id.startsWith(key) && id[key.length] === '-') return table[key]
  }
  return null
}

// USD for one bucket: { input, output, cacheWrite5m, cacheWrite1h,
// cacheRead } token counts (input excludes cached input). Null when the
// model has no price.
function costUsd (agent, model, t, speed) {
  const p = priceFor(agent, model)
  if (!p) return null
  const mult = speed === 'fast' && p.fast ? p.fast : 1
  const usd = (t.input || 0) * p.input +
    (t.output || 0) * p.output +
    (t.cacheWrite5m || 0) * p.cacheWrite5m +
    (t.cacheWrite1h || 0) * p.cacheWrite1h +
    (t.cacheRead || 0) * p.cacheRead
  return usd * mult / 1e6
}

const NOTE = 'Estimate at public API list prices. On a subscription plan this is the API-equivalent cost, not what you pay.'

module.exports = { AS_OF, SOURCES, NOTE, priceFor, costUsd, TABLES }
