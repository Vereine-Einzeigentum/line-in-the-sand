<script>
  import { login, requestAccount } from './lib/auth.js';

  let { onAuthed } = $props();

  let name = $state('');
  let password = $state('');
  let email = $state('');
  let mode = $state('login');
  let busy = $state(false);
  let error = $state('');
  let info = $state('');

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    busy = true;
    error = '';
    info = '';

    try {
      if (mode === 'login') {
        if (!name || !password) return;
        const session = await login({ name, password });
        onAuthed(session);
      } else if (mode === 'request') {
        if (!name || !email) return;
        await requestAccount({ name, email });
        info = 'check your email for a temporary password';
        mode = 'login';
        email = '';
      }
    } catch (err) {
      error = err.message || 'failed';
    } finally {
      busy = false;
    }
  }

  function switchMode(to) {
    mode = to;
    error = '';
    info = '';
    password = '';
  }
</script>

<div class="login">
  <div class="brand">
    <div class="title">LINE IN THE SAND</div>
    <div class="subtitle">— phase 0 —</div>
  </div>

  <form onsubmit={submit}>
    {#if mode === 'login'}
      <label>
        <span>name</span>
        <input bind:value={name} type="text" autocomplete="username"
          autocapitalize="off" autocorrect="off" spellcheck="false"
          required disabled={busy} />
      </label>
      <label>
        <span>password</span>
        <input bind:value={password} type="password"
          autocomplete="current-password" required disabled={busy} />
      </label>

    {:else if mode === 'request'}
      <label>
        <span>name</span>
        <input bind:value={name} type="text" autocomplete="username"
          autocapitalize="off" autocorrect="off" spellcheck="false"
          required disabled={busy} />
      </label>
      <label>
        <span>email</span>
        <input bind:value={email} type="email" autocomplete="email"
          required disabled={busy} />
      </label>
    {/if}

    {#if error}
      <div class="error">{error}</div>
    {/if}
    {#if info}
      <div class="info">{info}</div>
    {/if}

    <button type="submit" disabled={busy}>
      {#if busy}…{:else if mode === 'login'}login{:else}request{/if}
    </button>

    {#if mode === 'login'}
      <button type="button" class="switch"
        onclick={() => switchMode('request')} disabled={busy}>
        request an account
      </button>
    {:else}
      <button type="button" class="switch"
        onclick={() => switchMode('login')} disabled={busy}>
        log in instead
      </button>
    {/if}
  </form>
</div>

<style>
  .login {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    padding: 24px;
    gap: 24px;
  }

  .brand {
    text-align: center;
    user-select: none;
  }
  .title {
    font-size: 18px;
    letter-spacing: 0.15em;
    color: var(--amber);
  }
  .subtitle {
    font-size: 11px;
    color: var(--text-faint);
    margin-top: 4px;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 12px;
    width: 100%;
    max-width: 320px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  label span {
    font-size: 11px;
    color: var(--text-faint);
  }

  input {
    padding: 8px;
    border: 1px solid var(--line-2);
    background: var(--void-2);
    color: var(--text);
    font-size: 14px;
  }
  input:focus { border-color: var(--amber-dim); }

  button {
    padding: 10px;
    border: 1px solid var(--line-2);
    background: var(--void-2);
    color: var(--text);
    font-size: 14px;
    text-transform: lowercase;
  }
  button:hover:not(:disabled) { border-color: var(--amber-dim); color: var(--amber); }
  button:disabled { opacity: 0.4; }
  button.switch {
    border: none;
    background: transparent;
    color: var(--text-faint);
    font-size: 11px;
    padding: 4px;
  }

  .error {
    color: var(--red);
    font-size: 12px;
    padding: 4px 0;
  }

  .info {
    color: var(--cyan);
    font-size: 12px;
    padding: 4px 0;
  }
</style>
