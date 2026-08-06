import { Socket } from 'phoenix';

const SOCKET_PATH = '/socket';

export function createConnection({ token, playerId, onMessage, onStatus }) {
  const socket = new Socket(SOCKET_PATH, {
    params: { token }
  });

  let channel = null;
  let status = 'disconnected';

  function setStatus(s) {
    status = s;
    if (onStatus) onStatus(s);
  }

  socket.onOpen(() => setStatus('connected'));
  socket.onClose(() => setStatus('disconnected'));
  socket.onError(() => setStatus('error'));

  socket.connect();

  channel = socket.channel(`player:${playerId}`, { token });

  channel.on('msg', (payload) => {
    if (onMessage) onMessage({ scope: 'actor', ...payload });
  });

  channel.on('room_msg', (payload) => {
    if (onMessage) onMessage({ scope: 'room', ...payload });
  });

  channel.on('system', (payload) => {
    if (onMessage) onMessage({ scope: 'system', ...payload });
  });

  channel
    .join()
    .receive('ok', () => setStatus('joined'))
    .receive('error', (reason) => {
      setStatus('error');
      if (onMessage) {
        onMessage({
          scope: 'system',
          kind: 'error',
          text: `Channel join failed: ${JSON.stringify(reason)}`
        });
      }
    })
    .receive('timeout', () => setStatus('timeout'));

  return {
    send(raw) {
      return new Promise((resolve, reject) => {
        if (!channel) return reject(new Error('no channel'));
        channel
          .push('cmd', { raw })
          .receive('ok', resolve)
          .receive('error', reject)
          .receive('timeout', () => reject(new Error('timeout')));
      });
    },

    disconnect() {
      if (channel) {
        channel.leave();
        channel = null;
      }
      socket.disconnect();
      setStatus('disconnected');
    },

    getStatus() {
      return status;
    }
  };
}
