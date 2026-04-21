import { useEffect, useRef, useState } from 'react';
import { init, Terminal } from 'ghostty-web';

type Status = 'connecting' | 'disconnected' | 'error' | string;

// ghostty-web's bundled FitAddon reserves 15px on the right for a native
// vertical scrollbar (proposeDimensions subtracts a hard-coded constant).
// Ghostty renders its scrollbar as a canvas overlay (not a DOM scrollbar),
// so those 15px would show up as an artificial gap and narrow the cols
// reported to the PTY — causing wrapping at e.g. 148 instead of 150.
// Fit ourselves against the host's full client area.
function fitTerminal(term: Terminal, host: HTMLElement): void {
  const metrics = term.renderer?.getMetrics();
  if (!metrics || metrics.width === 0 || metrics.height === 0) return;
  if (host.clientWidth === 0 || host.clientHeight === 0) return;
  const cols = Math.max(2, Math.floor(host.clientWidth / metrics.width));
  const rows = Math.max(1, Math.floor(host.clientHeight / metrics.height));
  if (cols !== term.cols || rows !== term.rows) term.resize(cols, rows);
}

const textEncoder = new TextEncoder();

// ghostty-web's `init()` loads the inlined WASM once into a process-wide
// Ghostty instance. Memoize the promise so parallel pane mounts don't race.
let ghosttyReady: Promise<void> | null = null;
function ensureGhostty() {
  if (!ghosttyReady) ghosttyReady = init();
  return ghosttyReady;
}

export function TerminalPane({ sessionName }: { sessionName: string }) {
  const [status, setStatus] = useState<Status>('connecting');
  const hostRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);

  useEffect(() => {
    let disposed = false;
    const host = hostRef.current;
    if (!host) return;

    const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(
      `${proto}//${window.location.host}/ws?session=${encodeURIComponent(sessionName)}`,
    );
    ws.binaryType = 'arraybuffer';
    const abort = new AbortController();

    ws.onopen = () => setStatus(sessionName);
    ws.onclose = () => setStatus('disconnected');
    ws.onerror = () => setStatus('error');

    const sendResize = (cols: number, rows: number) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'resize', cols, rows }));
      }
    };

    ensureGhostty()
      .then(() => {
        if (disposed) return;
        const term = new Terminal({
          cols: 80,
          rows: 24,
          scrollback: 10000,
          fontSize: 14,
          fontFamily: 'Menlo, Consolas, "DejaVu Sans Mono", "Courier New", monospace',
          theme: {
            background: '#0d0d0d',
            foreground: '#e5e5e5',
          },
        });
        term.open(host);
        fitTerminal(term, host);
        const resizeObserver = new ResizeObserver(() => fitTerminal(term, host));
        resizeObserver.observe(host);
        abort.signal.addEventListener('abort', () => resizeObserver.disconnect());

        term.onData((data) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(textEncoder.encode(data));
          }
        });
        term.onResize(({ cols, rows }) => sendResize(cols, rows));

        // fitTerminal resolves dimensions synchronously above, so onResize
        // has already fired by now. Push once more to cover the
        // ws-not-yet-open case: either send immediately or once the socket
        // reaches OPEN.
        const pushCurrent = () => sendResize(term.cols, term.rows);
        if (ws.readyState === WebSocket.OPEN) pushCurrent();
        else ws.addEventListener('open', pushCurrent, { once: true, signal: abort.signal });

        ws.onmessage = (ev) => {
          if (ev.data instanceof ArrayBuffer) {
            term.write(new Uint8Array(ev.data));
          } else {
            try {
              const msg = JSON.parse(String(ev.data));
              if (msg?.type === 'error' || msg?.type === 'sessionEnded') {
                setStatus(msg.message || msg.type);
              }
            } catch {
              /* ignore non-JSON text frames */
            }
          }
        };

        term.focus();
        termRef.current = term;
      })
      .catch((err) => {
        if (!disposed) setStatus(`wasm init failed: ${err?.message ?? err}`);
      });

    return () => {
      disposed = true;
      abort.abort();
      ws.close();
      termRef.current?.dispose();
      termRef.current = null;
    };
  }, [sessionName]);

  return (
    <>
      <div id="status">{status}</div>
      <div id="term" ref={hostRef} />
    </>
  );
}
