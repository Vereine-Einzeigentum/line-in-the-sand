import { untrack } from 'svelte';

const MAX_LINES = 2000;

function createScrollback() {
  let lines = $state([]);
  let counter = 0;

  function push(entry) {
    const line = {
      id: ++counter,
      scope: entry.scope || 'system',
      kind: entry.kind || null,
      text: entry.text || '',
      ts: Date.now()
    };

    // Scrollback is a sink. Callers may invoke push() from inside a Svelte
    // effect, but writing a log line must never subscribe that effect to the
    // scrollback it just mutated or the effect can invalidate itself forever.
    untrack(() => {
      lines.push(line);
      if (lines.length > MAX_LINES) {
        lines.splice(0, lines.length - MAX_LINES);
      }
    });
  }

  function clear() {
    untrack(() => {
      lines.length = 0;
    });
  }

  return {
    get lines() { return lines; },
    push,
    clear
  };
}

export const scrollback = createScrollback();
