import { useState } from 'react'
import './App.css'

const LANGS = {
  go: { emoji: '🐹', name: 'Go' },
  python: { emoji: '🐍', name: 'Python' },
  rust: { emoji: '🦀', name: 'Rust' },
  ts: { emoji: '🟦', name: 'TS' },
}

let seq = 0

async function knock() {
  const id = ++seq
  const t0 = performance.now()
  try {
    const res = await fetch('/api/knock', { cache: 'no-store' })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const sig = await res.json()
    return { id, sig, rtt: performance.now() - t0 }
  } catch (err) {
    return { id, error: err.message }
  }
}

const ms = (v) => `${v.toFixed(2)} ms`

function countBy(items, key) {
  const counts = new Map()
  for (const item of items) counts.set(key(item), (counts.get(key(item)) ?? 0) + 1)
  return [...counts].sort((a, b) => b[1] - a[1])
}

function Tile({ answer: { id, sig, rtt, error } }) {
  if (error) {
    return (
      <div className="tile failed">
        <div className="who">⚠️ failed <span className="id">#{id}</span></div>
        <div className="pod">{error}</div>
      </div>
    )
  }
  const lang = LANGS[sig.lang] ?? { emoji: '❔', name: sig.lang }
  return (
    <div className={`tile ${sig.lang}`} title={JSON.stringify(sig, null, 2)}>
      <div className="who">
        {lang.emoji} {lang.name} <span className="id">#{id}</span>
      </div>
      <div className="pod">{sig.pod}</div>
      <dl>
        <dt>took</dt>
        <dd>{sig.took_us} µs</dd>
        <dt>rtt</dt>
        <dd>{ms(rtt)}</dd>
        <dt>network</dt>
        <dd>≈ {ms(rtt - sig.took_us / 1000)}</dd>
      </dl>
    </div>
  )
}

function Tally({ answers }) {
  const ok = answers.filter((a) => a.sig)
  const langOf = Object.fromEntries(ok.map((a) => [a.sig.pod, a.sig.lang]))
  const failed = answers.length - ok.length
  return (
    <aside className="tally">
      <h2>Tally <small>{ok.length} answers</small></h2>
      <h3>by language</h3>
      {countBy(ok, (a) => a.sig.lang).map(([lang, n]) => (
        <div key={lang} className={`row ${lang}`}>
          <span className="label">{LANGS[lang]?.emoji} {LANGS[lang]?.name ?? lang}</span>
          <span className="bar" style={{ width: `${(100 * n) / ok.length}%` }} />
          <span className="n">{n}</span>
        </div>
      ))}
      <h3>by pod</h3>
      {countBy(ok, (a) => a.sig.pod).map(([pod, n]) => (
        <div key={pod} className={`row ${langOf[pod]}`}>
          <span className="label pod">{pod}</span>
          <span className="bar" style={{ width: `${(100 * n) / ok.length}%` }} />
          <span className="n">{n}</span>
        </div>
      ))}
      {failed > 0 && <p className="failed-count">⚠️ {failed} failed</p>}
    </aside>
  )
}

export default function App() {
  const [answers, setAnswers] = useState([])
  const [n, setN] = useState(20)
  const [parallel, setParallel] = useState(false)
  const [busy, setBusy] = useState(false)

  const add = (answer) => setAnswers((prev) => [answer, ...prev])

  async function fire(count) {
    setBusy(true)
    if (parallel) await Promise.all(Array.from({ length: count }, () => knock().then(add)))
    else for (let i = 0; i < count; i++) add(await knock())
    setBusy(false)
  }

  return (
    <div className="app">
      <header>
        <h1>🚪 knock-knock</h1>
        <div className="controls">
          <button onClick={() => fire(1)} disabled={busy}>Knock</button>
          <span className="group">
            <button onClick={() => fire(n)} disabled={busy}>Fire {n}</button>
            <input
              type="number" min="1" max="1000" value={n} aria-label="N"
              onChange={(e) => setN(Math.max(1, Math.min(1000, Number(e.target.value) || 1)))}
            />
          </span>
          <span className="group toggle">
            <button className={parallel ? '' : 'on'} onClick={() => setParallel(false)}>sequential</button>
            <button className={parallel ? 'on' : ''} onClick={() => setParallel(true)}>parallel</button>
          </span>
          <button className="clear" onClick={() => { setAnswers([]); seq = 0 }} disabled={busy}>Clear</button>
        </div>
      </header>
      <main>
        <section className="tiles">
          {answers.length === 0 && <p className="empty">Nobody has knocked yet.</p>}
          {answers.map((a) => <Tile key={a.id} answer={a} />)}
        </section>
        <Tally answers={answers} />
      </main>
    </div>
  )
}
