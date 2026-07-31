<script>
  import { login, register } from './lib/auth.js';

  let { onAuthed } = $props();

  let name = $state('');
  let password = $state('');
  let mode = $state('login');
  let busy = $state(false);
  let error = $state('');

  async function submit(e) {
    e.preventDefault();
    if (!name || !password || busy) return;
    busy = true;
    error = '';
    try {
      const fn = mode === 'login' ? login : register;
      const session = await fn({ name, password });
      onAuthed(session);
    } catch (err) {
      error = err.message || 'failed';
    } finally {
      busy = false;
    }
  }
</script>

<div class="login">
  <div class="brand">
    <div class="title">LINE IN THE SAND</div>
    <div class="subtitle">— phase 0 —</div>
  </div>

  <form onsubmit={submit}>
    <label>
      <span>name</span>
      <input
        bind:value={name}
        type="text"
        autocomplete="username"
        autocapitalize="off"
        autocorrect="off"
        spellcheck="false"
        required
        disabled={busy}
      />
    </label>

    <label>
      <span>password</span>
      <input
        bind:value={password}
        type="password"
        autocomplete={mode === 'login' ? 'current-password' : 'new-password'}
        required
        disabled={busy}
      />
    </label>

    {#if error}
      <div class="error">{error}</div>
    {/if}

    <button type="submit" disabled={busy}>
      {#if busy}…{:else}{mode}{/if}
    </button>

    <button
      type="button"
      class="switch"
      onclick={() => { mode = mode === 'login' ? 'register' : 'login'; error = ''; }}
      disabled={busy}
    >
      {mode === 'login' ? 'register instead' : 'log in instead'}
    </button>
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
</style>
