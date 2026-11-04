// Local inventory requests use the native main-thread store shared by all windows.
(() => {
  let store;
  const request = (action, values = {}) => window.__TAURI_INTERNALS__.invoke('offline_atlas_request', {action, values});
  const receive = user => {
    if (!store) return;
    store.updateUserInfo(user);
    window.dispatchEvent(new CustomEvent('offline-atlas-changed'));
  };
  window.__OFFLINE_FULL_ATLAS__ = {
    request,
    receive,
    async initialize(globalStore) {
      store = globalStore;
      receive(await request('user'));
      const status = await request('status');
      if (status.recoveryMessage) window.setTimeout(() => window.alert(status.recoveryMessage), 500);
    },
    async api(action, values = {}) { return {code: 0, data: await request(action, values), message: '本地离线数据'}; }
  };
})();
