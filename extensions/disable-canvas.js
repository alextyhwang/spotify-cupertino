// NAME: Disable Canvas
// DESCRIPTION: Turns off Spotify's looping "Canvas" track videos via the client's own canvasVideosEnabled setting.
// VERSION: 1.0.0
(function disableCanvas() {
  const KEY = 'canvasVideosEnabled';
  const api = window.Spicetify?.Platform?.LocalStorageAPI;
  if (!api) return setTimeout(disableCanvas, 300);
  const enforce = () => {
    try { if (api.getItem(KEY) !== false) api.setItem(KEY, false); } catch (e) { console.warn('[disable-canvas]', e); }
  };
  enforce();
  // Re-apply if anything flips it back on (e.g. the context-menu "Show looping visuals" item).
  try {
    api.getEvents().addListener('update', (ev) => {
      if (ev?.data?.key === KEY && ev.data.value !== false) setTimeout(enforce, 0);
    });
  } catch (_) {}
})();
