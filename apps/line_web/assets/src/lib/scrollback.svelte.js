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
    lines.push(line);
    if (lines.length > MAX_LINES) {
      lines.splice(0, lines.length - MAX_LINES);
    }
  }

  function clear() {
    lines.length = 0;
  }

  return {
    get lines() { return lines; },
    push,
    clear
  };
}

export const scrollback = createScrollback();
