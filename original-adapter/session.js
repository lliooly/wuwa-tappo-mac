(() => {
  let values = window.__MACOS_INITIAL_SESSION__ || {};
  delete window.__MACOS_INITIAL_SESSION__;
  let pending = Promise.resolve();
  let failure;
  const valid = new Set(['infoToken', 'lastLoginTime', 'lang']);
  window.__MACOS_SESSION__ = {
    get(name) {
      const entry = values[name];
      return entry && entry.expires > Date.now() ? entry.value : null;
    },
    set(name, value, days) {
      if (!valid.has(name)) throw new Error('Unsupported session value');
      value = String(value); days = Number(days);
      if (!Number.isFinite(days)) throw new Error('Invalid session expiry');
      if (days <= 0 || !value) delete values[name];
      else values[name] = { value, expires: Date.now() + days * 86400000 };
      // Serialize writes so the two original setCookie calls cannot race.
      pending = pending.then(async () => {
        try {
          await window.webkit.messageHandlers.originalSession.postMessage({ name, value, days });
          failure = undefined;
        } catch (error) { failure = new Error('Login session could not be saved'); }
      });
    },
    receive(snapshot) { values = snapshot; },
    async flush() { await pending; if (failure) throw failure; }
  };
})();
