<script>
  import Login from './Login.svelte';
  import Terminal from './Terminal.svelte';
  import { scrollback } from './lib/scrollback.svelte.js';
  import { createConnection } from './lib/socket.js';
  import { loadSession, saveSession, clearSession } from './lib/auth.js';

  let session = $state(loadSession());
  let status = $state('disconnected');
  let conn = null;

  $effect(() => {
    if (conn) {
      conn.disconnect();
      conn = null;
    }
    if (!session) return;

    scrollback.push({ scope: 'system', text: 'Connecting...' });

    conn = createConnection({
      token: session.token,
      playerId: session.player_id,
      onStatus: (s) => { status = s; },
      onMessage: (msg) => {
        scrollback.push({
          scope: msg.scope,
          kind: msg.kind,
          text: msg.text
        });
      }
    });

    return () => {
      if (conn) {
        conn.disconnect();
        conn = null;
      }
    };
  });

  function handleAuth(newSession) {
    saveSession(newSession);
    session = newSession;
    scrollback.clear();
  }

  function handleSubmit(raw) {
    if (!conn) {
      scrollback.push({ scope: 'system', kind: 'error', text: 'Not connected.' });
      return;
    }
    if (raw === '/clear') { scrollback.clear(); return; }
    if (raw === '/logout') { clearSession(); session = null; return; }

    conn.send(raw).catch((err) => {
      scrollback.push({
        scope: 'system',
        kind: 'error',
        text: `command failed: ${err.message || err}`
      });
    });
  }
</script>

{#if !session}
  <Login onAuthed={handleAuth} />
{:else}
  <Terminal onSubmit={handleSubmit} {status} />
{/if}
