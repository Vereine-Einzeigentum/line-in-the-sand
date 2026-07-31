<script>
  import { scrollback } from './lib/scrollback.svelte.js';

  let { onSubmit, status = 'connected' } = $props();

  let input = $state('');
  let feedEl;
  let inputEl;
  let commsOpen = $state(false);
  let optsOpen = $state(false);
  let commsChannel = $state('global');
  let theme = $state('dark');
  let anim = $state('on');
  let density = $state('dense');

  // Command history
  let history = $state([]);
  let historyIdx = $state(-1);

  // HUD state (Phase 0 defaults — server will push updates later)
  let meters = $state([
    { k: 'HP', val: 100, keep: 'full' },
    { k: 'FATIGUE', val: 0, keep: 'empty' },
    { k: 'STRESS', val: 0, keep: 'empty' },
  ]);
  let signal = $state(50);
  let money = $state(0);
  let factions = $state([
    { glyph: '淼', glyphColor: 'var(--chop)', name: 'THE BOUNDLESS', standing: 0, positive: true },
    { glyph: '★', glyphColor: 'var(--sand)', name: 'DISTRICT POLICE', standing: 0, positive: true },
  ]);

  // Minimap state
  const MM_EMPTY = [
    '███████',
    '█░░░░░█',
    '█░░◉░░█',
    '█░░░░░█',
    '█░░░░░█',
    '███████',
    '       ',
  ];
  let mmGrid = $state(MM_EMPTY);
  let mmHere = $state({ x: 3, y: 2 });
  const MM_COL = {
    '█': 'var(--line-2)', '░': 'var(--text-faint)', '≈': 'var(--cyan-dim)',
    '▨': 'var(--rust)', '▣': 'var(--text-dim)', '↓': 'var(--jade)',
  };

  // Comms messages
  let commsData = $state({
    global: [],
    sector: [],
    union: [],
  });
  let commsInput = $state('');

  // Auto-scroll feed when new lines arrive
  $effect(() => {
    const _ = scrollback.lines.length;
    if (feedEl) {
      queueMicrotask(() => {
        feedEl.scrollTop = feedEl.scrollHeight;
      });
    }
  });

  // Sync theme/anim to document root
  $effect(() => {
    document.documentElement.dataset.theme = theme;
  });
  $effect(() => {
    document.documentElement.dataset.anim = anim;
  });

  function meterColor(m) {
    if (m.keep === 'full') return m.val < 28 ? 'var(--red)' : m.val < 55 ? 'var(--ember)' : 'var(--amber)';
    return m.val > 70 ? 'var(--red)' : m.val > 45 ? 'var(--ember)' : 'var(--cyan-dim)';
  }

  function meterBlocks(m) {
    const N = 12;
    const fill = Math.max(0, Math.min(N, Math.round(m.val / 100 * N)));
    return { fill, empty: N - fill, color: meterColor(m) };
  }

  function sigBars() {
    const bars = [];
    const active = Math.round(signal / 100 * 6);
    for (let i = 0; i < 6; i++) {
      bars.push({ height: 5 + i * 1.6, on: i < active });
    }
    return bars;
  }

  function renderMmChar(x, y) {
    if (x === mmHere.x && y === mmHere.y) return { char: '◉', cls: 'here' };
    const c = mmGrid[y]?.[x];
    if (!c || c === ' ') return { char: ' ', cls: '' };
    return { char: c, color: MM_COL[c] || 'var(--text-faint)' };
  }

  function now() {
    const d = new Date();
    return d.toTimeString().slice(0, 8);
  }

  function lineClass(line) {
    let cls = 'line';
    if (line.scope === 'echo') cls += ' echo';
    else if (line.scope === 'system') cls += ' sys';
    else if (line.scope === 'room') cls += ' room-line';
    if (line.kind === 'error') cls += ' warn';
    return cls;
  }

  function submit() {
    const raw = input.trim();
    if (!raw) return;
    history = [raw, ...history.slice(0, 49)];
    historyIdx = -1;
    scrollback.push({ scope: 'echo', text: `› ${raw}` });
    onSubmit(raw);
    input = '';
    autoResize();
  }

  function onKeydown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      submit();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (history.length === 0) return;
      historyIdx = Math.min(historyIdx + 1, history.length - 1);
      input = history[historyIdx];
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (historyIdx <= 0) {
        historyIdx = -1;
        input = '';
      } else {
        historyIdx -= 1;
        input = history[historyIdx];
      }
    }
  }

  function autoResize() {
    if (!inputEl) return;
    inputEl.style.height = 'auto';
    inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + 'px';
  }

  function quickCmd(cmd) {
    if (cmd === 'say') {
      input = 'say ';
      inputEl?.focus();
      return;
    }
    scrollback.push({ scope: 'echo', text: `› ${cmd}` });
    onSubmit(cmd);
  }

  function toggleComms() {
    commsOpen = !commsOpen;
  }

  function sendComms() {
    const msg = commsInput.trim();
    if (!msg) return;
    onSubmit(`${commsChannel === 'global' ? 'say' : 'say'} ${msg}`);
    commsInput = '';
  }

  function commsKeydown(e) {
    if (e.key === 'Enter') sendComms();
  }

  const commsTitles = {
    global: 'GLOBAL COMMS',
    sector: 'SECTOR COMMS',
    union: 'UNION · PRIVATE',
  };
</script>

<!-- CRT overlays -->
<div id="crt"></div>
<div id="vig"></div>
<div id="flick"></div>

<div class="app">
  <!-- TOP BAR -->
  <header>
    <div class="minimap">
      <span class="lbl">SECTOR</span>
      <div class="mm-grid">
        {#each mmGrid as row, y}
          {#each row.split('') as _, x}
            {@const cell = renderMmChar(x, y)}
            {#if cell.cls === 'here'}
              <span class="here">{cell.char}</span>
            {:else if cell.char === ' '}
              {' '}
            {:else}
              <span style:color={cell.color}>{cell.char}</span>
            {/if}
          {/each}
          {'\n'}
        {/each}
      </div>
      <div class="coord">—</div>
    </div>
    <div class="status">
      <div class="meters">
        {#each meters as m}
          {@const b = meterBlocks(m)}
          <div class="meter">
            <span class="ml">{m.k}</span>
            <span class="mt">
              <span class="br">[</span><span style:color={b.color}>{'█'.repeat(b.fill)}</span><span class="e">{'░'.repeat(b.empty)}</span><span class="br">]</span>
            </span>
            <span class="mv">{m.val}</span>
          </div>
        {/each}
      </div>
      <div class="srow" style="align-items:center">
        <div class="sig" title="SIGNAL">
          <div class="bars">
            {#each sigBars() as bar}
              <b style:height="{bar.height}px" class:on={bar.on}></b>
            {/each}
          </div>
          <div>
            <div class="lvl">SIG {signal}</div>
          </div>
        </div>
        <div style="flex:1"></div>
        <div class="money"><span style="unicode-bidi:isolate">{money}</span> <small>dirham</small></div>
      </div>
      <div class="facs">
        {#each factions as fac}
          <div class="fac">
            <span class="g" style:color={fac.glyphColor}>{fac.glyph}</span>
            <div class="meta">
              <div class="nm">{fac.name}</div>
              <div class="cl" class:pos={fac.standing >= 0} class:neg={fac.standing < 0}>
                {fac.standing >= 0 ? '+' : ''}{fac.standing} {fac.standing >= 0 ? '▲' : '▼'}
              </div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  </header>

  <!-- BODY -->
  <div class="body" class:shift={commsOpen}>
    <button class="fab comms-btn" onclick={toggleComms} title="Comms">☰</button>
    <button class="fab opts-btn" onclick={() => optsOpen = true} title="Options">⚙</button>

    <!-- COMMS DRAWER -->
    <aside class="comms" class:open={commsOpen}>
      <div class="ch">
        {#each ['global', 'sector', 'union'] as ch}
          <button class:on={commsChannel === ch} onclick={() => commsChannel = ch}>
            {ch.toUpperCase()}
          </button>
        {/each}
      </div>
      <div class="head">
        <span class="ttl">{commsTitles[commsChannel]}</span>
        <button class="x" onclick={() => commsOpen = false}>×</button>
      </div>
      <div class="stream">
        {#each (commsData[commsChannel] || []) as msg}
          <div class="cmsg">
            <div class="h">
              <span class="u u1">{msg.from || 'unknown'}</span>
            </div>
            <div class="b">{msg.text}</div>
          </div>
        {/each}
      </div>
      <div class="csend">
        <input bind:value={commsInput} onkeydown={commsKeydown} placeholder="message {commsChannel}…">
        <button onclick={sendComms}>↵</button>
      </div>
    </aside>

    <!-- LOCAL FEED -->
    <main class="feed" bind:this={feedEl}>
      {#each scrollback.lines as line (line.id)}
        <div class="ev" style:margin-bottom={density === 'dense' ? '10px' : '18px'}>
          <div class="t">{new Date(line.ts).toTimeString().slice(0, 8)}</div>
          <div class={lineClass(line)}>{line.text}</div>
        </div>
      {/each}
    </main>
  </div>

  <!-- DOCK -->
  <div class="dock">
    <div class="qbar">
      <button onclick={() => quickCmd('look')}>look</button>
      <button onclick={() => quickCmd('north')}>go north</button>
      <button onclick={() => quickCmd('inventory')}>inventory</button>
      <button onclick={() => quickCmd('who')}>who</button>
      <button onclick={() => quickCmd('say')}>say…</button>
    </div>
    <div class="entry" class:focused={false}>
      <span class="pr">›</span>
      <textarea
        bind:this={inputEl}
        bind:value={input}
        onkeydown={onKeydown}
        oninput={autoResize}
        rows="1"
        placeholder="type a command…"
      ></textarea>
      <button class="send" onclick={submit}>▸</button>
    </div>
    <div class="status-dot">
      <span class="dot dot--{status}">●</span>
      <span class="status-text">{status}</span>
    </div>
  </div>
</div>

<!-- OPTIONS MODAL -->
{#if optsOpen}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="scrim open" onclick={(e) => { if (e.target === e.currentTarget) optsOpen = false; }}>
    <div class="opts">
      <div class="oh">
        <span class="t">System · 设置</span>
        <span class="chop">淼</span>
      </div>
      <div class="ob">
        <div class="orow">
          <div>
            <div class="ol">Display mode</div>
            <div class="od">Cream = Boundless-owned ground</div>
          </div>
          <div class="seg">
            <button class:on={theme === 'dark'} onclick={() => theme = 'dark'}>DARK</button>
            <button class:on={theme === 'light'} onclick={() => theme = 'light'}>CREAM</button>
          </div>
        </div>
        <div class="orow">
          <div>
            <div class="ol">Animations</div>
            <div class="od">Scanlines, flicker, message reveal</div>
          </div>
          <div class="seg">
            <button class:on={anim === 'on'} onclick={() => anim = 'on'}>ON</button>
            <button class:on={anim === 'off'} onclick={() => anim = 'off'}>OFF</button>
          </div>
        </div>
        <div class="orow">
          <div>
            <div class="ol">Feed density</div>
            <div class="od">Lines per event block</div>
          </div>
          <div class="seg">
            <button class:on={density === 'dense'} onclick={() => density = 'dense'}>DENSE</button>
            <button class:on={density === 'roomy'} onclick={() => density = 'roomy'}>ROOMY</button>
          </div>
        </div>
      </div>
      <div class="ofoot">
        <span>淼 رسوم العهود · CLIENT v0.9</span>
        <span>{new Date().toTimeString().slice(0, 5)}</span>
      </div>
    </div>
  </div>
{/if}

<style>
  /* CRT overlays */
  :global(#crt){position:fixed;inset:0;pointer-events:none;z-index:90;
    background:repeating-linear-gradient(0deg,rgba(0,0,0,var(--scan-op)) 0 1px,transparent 1px 3px);
    mix-blend-mode:multiply;}
  :global(html[data-theme="light"] #crt){mix-blend-mode:normal;background:repeating-linear-gradient(0deg,rgba(120,100,60,var(--scan-op)) 0 1px,transparent 1px 3px);}
  :global(#vig){position:fixed;inset:0;pointer-events:none;z-index:89;
    background:radial-gradient(120% 90% at 50% 40%,transparent 55%,rgba(0,0,0,0.55));}
  :global(html[data-theme="light"] #vig){background:radial-gradient(120% 90% at 50% 40%,transparent 60%,rgba(120,100,60,0.14));}
  :global(html[data-anim="off"] #crt),:global(html[data-anim="off"] #flick){display:none}
  :global(#flick){position:fixed;inset:0;pointer-events:none;z-index:91;background:rgba(255,200,120,0.015);animation:flick 6s steps(2) infinite}
  @keyframes flick{0%,97%,100%{opacity:0}98%{opacity:1}}

  .app{display:flex;flex-direction:column;height:100%;height:100dvh;position:relative;z-index:10}

  /* TOP BAR */
  header{display:flex;gap:8px;padding:8px;border-bottom:1px solid var(--line);
    background:linear-gradient(180deg,var(--panel),var(--void));flex:none}
  .minimap{flex:none;width:112px;border:1px solid var(--line-2);background:#0b0810;
    padding:5px 6px 6px;border-radius:2px;position:relative}
  .mm-grid{font-size:12px;line-height:1.02;letter-spacing:2px;white-space:pre;text-align:center;font-family:var(--mono)}
  :global(.minimap .here){color:var(--amber);text-shadow:var(--glow) var(--amber)}
  .lbl{position:absolute;top:-1px;right:3px;font-size:8px;color:var(--text-faint);letter-spacing:1px}
  .coord{font-size:8px;color:var(--amber-dim);text-align:center;margin-top:3px;letter-spacing:1px}

  .status{flex:1;display:flex;flex-direction:column;gap:5px;min-width:0}
  .srow{display:flex;gap:6px}
  .meters{display:flex;flex-direction:column;gap:3px}
  .meter{display:flex;align-items:center;gap:7px;font-family:var(--mono);line-height:1}
  .meter .ml{width:52px;font-size:9px;letter-spacing:1px;color:var(--text-dim);text-transform:uppercase;text-align:right;flex:none}
  .meter .mt{font-size:14px;letter-spacing:0;white-space:pre;flex:1;min-width:0;overflow:hidden}
  .meter .mt .br{color:var(--text-faint)}
  .meter .mt .e{color:var(--line-2)}
  .meter .mv{font-size:10px;color:var(--text-dim);width:28px;flex:none;text-align:right}
  .sig{display:flex;align-items:center;gap:5px}
  .sig .bars{display:flex;align-items:flex-end;gap:1.5px;height:13px}
  .sig .bars b{width:3px;background:var(--cyan);box-shadow:var(--glow) var(--cyan);opacity:.25;border-radius:1px}
  .sig .bars b.on{opacity:1}
  .sig .lvl{font-size:11px;color:var(--cyan);font-weight:700}
  .money{font-size:14px;color:var(--gold);font-weight:700;white-space:nowrap;display:flex;align-items:baseline;gap:4px}
  .money small{font-size:8px;color:var(--text-faint);font-weight:400;letter-spacing:.5px}
  .facs{display:flex;gap:5px}
  .fac{flex:1;border:1px solid var(--line);border-radius:2px;padding:2px 6px;background:var(--void-2);
    display:flex;align-items:center;gap:6px;min-width:0}
  .fac .g{font-size:14px;line-height:1;flex:none}
  .fac .meta{min-width:0;flex:1}
  .fac .nm{font-size:8px;color:var(--text-dim);letter-spacing:.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .fac .cl{font-size:11px;font-weight:700;color:var(--text-dim)}
  .fac .cl.pos{color:var(--green)} .fac .cl.neg{color:var(--ember)}

  /* MAIN FEED */
  .body{flex:1;display:flex;min-height:0;position:relative;--dw:min(300px,84vw)}
  .feed{flex:1;overflow-y:auto;padding:12px 14px 14px;scrollbar-width:thin;scrollbar-color:var(--line-2) transparent}
  .feed::-webkit-scrollbar{width:6px} .feed::-webkit-scrollbar-thumb{background:var(--line-2);border-radius:3px}
  .ev{opacity:1}
  :global(html[data-anim="on"]) .ev{animation:appear .25s ease}
  @keyframes appear{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:none}}
  @media(prefers-reduced-motion:reduce){.ev{animation:none!important}}
  .ev .t{font-size:8px;color:var(--text-faint);letter-spacing:1px;margin-bottom:1px}
  .line{color:var(--text)}
  .line.echo{color:var(--text-dim);opacity:0.7}
  .line.sys{color:var(--cyan)}
  .line.sys::before{content:"» ";color:var(--cyan-dim)}
  .line.warn{color:var(--magenta)}
  .line.warn::before{content:"!! ";color:var(--magenta)}
  .line.room-line{border-left:2px solid var(--amber-dim);padding-left:10px}

  /* COMMS DRAWER */
  .comms{position:absolute;top:0;left:0;bottom:0;width:300px;max-width:84vw;z-index:40;
    background:var(--panel);border-right:1px solid var(--line-2);
    display:flex;flex-direction:column;transform:translateX(-103%);transition:transform .26s cubic-bezier(.4,0,.2,1);
    box-shadow:8px 0 30px rgba(0,0,0,.5)}
  .comms.open{transform:none}
  .comms .ch{display:flex;border-bottom:1px solid var(--line);flex:none}
  .comms .ch button{flex:1;background:none;border:none;color:var(--text-faint);font-family:var(--mono);
    font-size:10px;letter-spacing:.5px;padding:8px 4px;cursor:pointer;border-bottom:2px solid transparent}
  .comms .ch button.on{color:var(--amber);border-bottom-color:var(--amber)}
  .comms .head{display:flex;align-items:center;justify-content:space-between;padding:7px 10px;border-bottom:1px solid var(--line);flex:none}
  .comms .head .ttl{font-size:9px;letter-spacing:1.5px;color:var(--text-dim);text-transform:uppercase}
  .comms .head .x{background:none;border:1px solid var(--line-2);color:var(--text-dim);border-radius:2px;width:22px;height:22px;cursor:pointer;font-size:13px}
  .comms .stream{flex:1;overflow-y:auto;padding:9px 10px;scrollbar-width:thin;scrollbar-color:var(--line-2) transparent}
  .comms .stream::-webkit-scrollbar{width:5px}.comms .stream::-webkit-scrollbar-thumb{background:var(--line-2)}
  .cmsg{margin-bottom:8px;font-size:12px;line-height:1.45}
  .cmsg .h{font-size:9px;color:var(--text-faint);letter-spacing:.5px;display:flex;gap:6px;margin-bottom:1px}
  .cmsg .h .u{font-weight:700;color:var(--amber)}
  .cmsg .b{color:var(--text)}
  .comms .csend{display:flex;gap:6px;padding:8px;border-top:1px solid var(--line);flex:none}
  .comms .csend input{flex:1;background:var(--void-2);border:1px solid var(--line-2);color:var(--text);
    font-family:var(--mono);font-size:12px;padding:7px 9px;border-radius:2px;outline:none}
  .comms .csend input:focus{border-color:var(--amber-dim)}
  .comms .csend button{background:var(--amber-dim);border:none;color:#1a0f00;font-weight:700;padding:0 11px;border-radius:2px;cursor:pointer;font-family:var(--mono)}

  /* BOTTOM INPUT */
  .dock{flex:none;border-top:1px solid var(--line);background:linear-gradient(0deg,var(--panel),var(--void));padding:7px 8px}
  .qbar{display:flex;gap:5px;margin-bottom:6px;overflow-x:auto;scrollbar-width:none}
  .qbar::-webkit-scrollbar{display:none}
  .qbar button{flex:none;background:var(--void-2);border:1px solid var(--line-2);color:var(--text-dim);
    font-family:var(--mono);font-size:10px;padding:4px 9px;border-radius:2px;cursor:pointer;letter-spacing:.5px;white-space:nowrap}
  .qbar button:hover{border-color:var(--amber-dim);color:var(--amber)}
  .entry{display:flex;align-items:flex-end;gap:7px;border:1px solid var(--line-2);background:var(--void-2);border-radius:3px;padding:6px 8px}
  .entry:focus-within{border-color:var(--amber);box-shadow:0 0 0 1px var(--amber-dim) inset}
  .entry .pr{color:var(--amber);font-weight:700;padding-top:2px}
  .entry textarea{flex:1;background:none;border:none;color:var(--text);font-family:var(--mono);font-size:13px;
    resize:none;outline:none;line-height:1.4;max-height:120px;overflow-y:auto}
  .entry textarea::placeholder{color:var(--text-faint)}
  .entry .send{background:none;border:none;color:var(--amber);cursor:pointer;font-size:16px;padding:0 2px;align-self:center}
  .status-dot{display:flex;align-items:center;gap:5px;margin-top:4px;padding:0 2px}
  .dot{font-size:8px;user-select:none}
  .dot--joined,.dot--connected{color:var(--green)}
  .dot--disconnected{color:var(--text-faint)}
  .dot--error{color:var(--red)}
  .dot--timeout{color:var(--ember)}
  .status-text{font-size:8px;color:var(--text-faint);letter-spacing:.5px;text-transform:uppercase}

  /* corner buttons */
  .fab{position:absolute;z-index:45;width:38px;height:38px;border-radius:3px;border:1px solid var(--line-2);
    background:var(--panel);color:var(--text-dim);cursor:pointer;font-size:15px;display:flex;align-items:center;justify-content:center}
  .fab:hover{color:var(--amber);border-color:var(--amber-dim)}
  .fab.comms-btn{top:8px;left:8px;display:none;transition:transform .26s cubic-bezier(.4,0,.2,1)}
  .fab.opts-btn{bottom:64px;right:10px}

  /* OPTIONS MODAL */
  .scrim{position:fixed;inset:0;z-index:70;background:rgba(5,3,10,.7);backdrop-filter:blur(2px);
    display:flex;align-items:center;justify-content:center;padding:18px}
  .opts{width:330px;max-width:100%;background:var(--panel);border:1px solid var(--line-2);border-radius:4px;overflow:hidden}
  .opts .oh{display:flex;align-items:center;justify-content:space-between;padding:11px 13px;border-bottom:1px solid var(--line);background:var(--panel-2)}
  .opts .oh .t{font-size:11px;letter-spacing:2px;color:var(--amber);text-transform:uppercase}
  .opts .oh .chop{color:var(--red);font-size:15px;border:1px solid var(--gold);border-radius:50%;width:24px;height:24px;display:flex;align-items:center;justify-content:center}
  .opts .ob{padding:6px 13px 13px}
  .orow{display:flex;align-items:center;justify-content:space-between;padding:11px 0;border-bottom:1px solid var(--line)}
  .orow:last-child{border-bottom:none}
  .orow .ol{font-size:12px;color:var(--text)}
  .orow .od{font-size:9px;color:var(--text-faint);margin-top:2px}
  .seg{display:flex;border:1px solid var(--line-2);border-radius:3px;overflow:hidden}
  .seg button{background:var(--void-2);border:none;color:var(--text-dim);font-family:var(--mono);font-size:10px;
    padding:6px 11px;cursor:pointer;letter-spacing:.5px}
  .seg button.on{background:var(--amber-dim);color:#1a0f00;font-weight:700}
  .opts .ofoot{padding:9px 13px;border-top:1px solid var(--line);font-size:8px;color:var(--text-faint);letter-spacing:.5px;
    display:flex;justify-content:space-between;background:var(--void-2)}

  /* desktop */
  @media(min-width:860px){
    .fab.comms-btn{display:none!important}
    .comms{position:relative;transform:none!important;max-width:none;width:280px;box-shadow:none;flex:none}
    header{padding:10px}
    .minimap{width:120px}
    .feed{padding:16px 22px}
    .dock{padding:9px 16px}
  }
  @media(max-width:859px){
    .fab.comms-btn{display:flex}
    .comms{box-shadow:none}
    .body.shift .feed{transform:translateX(var(--dw))}
    .body.shift .comms-btn{transform:translateX(var(--dw))}
    .feed{transition:transform .26s cubic-bezier(.4,0,.2,1)}
  }
</style>
