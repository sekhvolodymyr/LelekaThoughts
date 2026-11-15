/** Coalesce event bursts and serialize refreshes; requests during a fetch get one trailing refresh. */
export function refreshQueue(run: () => Promise<void>, delay = 250) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let running = false;
  let stopped = false;
  let waiting: {resolve: () => void; reject: (e: unknown) => void}[] = [];
  async function flush() {
    timer = undefined;
    if (running || stopped || !waiting.length) return;
    running = true;
    const batch = waiting; waiting = [];
    try { await run(); batch.forEach(w => w.resolve()); }
    catch (e) { batch.forEach(w => w.reject(e)); }
    finally { running = false; if (waiting.length && !stopped) timer = setTimeout(flush, delay); }
  }
  return {
    request() {
      if (stopped) return Promise.resolve();
      const result = new Promise<void>((resolve, reject) => waiting.push({resolve, reject}));
      if (!running && !timer) timer = setTimeout(flush, delay);
      return result;
    },
    stop() { stopped = true; clearTimeout(timer); waiting.forEach(w => w.resolve()); waiting = []; },
  };
}
