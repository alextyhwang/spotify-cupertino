// Spotify Cupertino: a sidebar-only, macOS-style layout for Spotify.
// - No top bar. The sidebar holds: window controls + back/forward, Spotify's own search box,
//   navigation, and a footer with the account button, Friend Activity and Settings.
// - Spotify's native back/forward, search, account and Friend Activity elements are kept
//   (they ignore programmatic clicks) and positioned into the sidebar by CSS, using the
//   sidebar's measured box (--gs-nav-*).
// - Playlists move from the sidebar to a "Your Playlists" grid at the top of Home.
// - Backdrop: the current track's album art. Spotify's lyrics button is hidden when
//   Spicy Lyrics or Beautiful Lyrics is installed.
(function spotifyCupertino() {
  const S = window.Spicetify;
  const navBar = document.querySelector(".Root__nav-bar");
  if (!S?.Player?.addEventListener || !S.Platform?.History || !S.Platform?.RootlistAPI || !navBar) {
    setTimeout(spotifyCupertino, 300);
    return;
  }
  const root = document.documentElement;
  const H = S.Platform.History;
  const path = () => H.location?.pathname || "/";

  // ── Search suggestions (once) ────────────────────────────────────────────
  // Spotify's suggestion dropdown sits behind its "enableSearchSuggestions" flag, which is off
  // for most accounts. Turn it on once through Spicetify's Experimental features store, which
  // applies stored values at startup, then reload once. Users can still switch it off there.
  try {
    const DONE = "spotify-cupertino:suggestions-defaulted", EXP = "spicetify-exp-features";
    if (!localStorage.getItem(DONE)) {
      localStorage.setItem(DONE, "1");
      const exp = JSON.parse(localStorage.getItem(EXP) || "{}") || {};
      if (exp.enableSearchSuggestions?.value !== true) {
        exp.enableSearchSuggestions = { description: "Enables the search suggestions dropdown", ...exp.enableSearchSuggestions, value: true };
        localStorage.setItem(EXP, JSON.stringify(exp));
        setTimeout(() => location.reload(), 500);
      }
    }
  } catch {}

  // ── Title bar ───────────────────────────────────────────────────────────
  // macOS draws the window buttons 20 pt from the left edge (fixed by Spotify's native side)
  // and centres them vertically in a "title bar" height the UI reports, in points. Report
  // 20 + 7 + 7 + 20 = 54 pt so the 14 pt buttons sit 20 pt from the top too, at any zoom.
  // CSS needs that height in CSS px (pt ÷ zoom) to line up back/forward and the search box.
  const INSET = 20, BUTTON = 14, TITLEBAR_PT = 2 * INSET + BUTTON;
  const C = S.Platform.ControlMessageAPI;
  if (C?.setTitlebarHeight && !C.__gsTitlebar) {
    const send = C.setTitlebarHeight.bind(C);
    C.setTitlebarHeight = () => send(TITLEBAR_PT); // Spotify re-sends on zoom changes
    C.__gsTitlebar = true;
    send(TITLEBAR_PT); // the startup call ran before this theme loaded
  }
  // The window's corner radius (16 pt, measured) in CSS px, so inner corners near the window's
  // corners can be concentric: inner radius = window radius - inset.
  const WINDOW_RADIUS_PT = 16;
  const syncTitlebar = () => {
    const zoom = outerWidth / innerWidth || 1;
    root.style.setProperty("--gs-titlebar", `${(TITLEBAR_PT / zoom).toFixed(2)}px`);
    root.style.setProperty("--gs-window-r", `${(WINDOW_RADIUS_PT / zoom).toFixed(2)}px`);
  };
  syncTitlebar();
  window.addEventListener("resize", syncTitlebar);

  // ── Backdrop ─────────────────────────────────────────────────────────────
  const imageUrl = (uri, size = 300) => {
    if (!uri) return "";
    if (uri.startsWith("spotify:image:")) return `https://i.scdn.co/image/${uri.slice(14)}`;
    if (uri.startsWith("spotify:mosaic:")) return `https://mosaic.scdn.co/${size}/${uri.slice(15).split(":").join("")}`;
    return uri;
  };
  let lastArt = "";
  const updateArt = () => {
    const meta = S.Player.data?.item?.metadata || {};
    const url = imageUrl(meta.image_small_url || meta.image_url);
    if (!url || url === lastArt) return;
    lastArt = url;
    root.style.setProperty("--g-art", `url("${url}")`);
  };
  S.Player.addEventListener("songchange", updateArt);
  updateArt();
  [800, 2500, 6000].forEach((ms) => setTimeout(updateArt, ms)); // player data can arrive after load

  // ── Lyrics extension detection ──────────────────────────────────────────
  const lyricsExt = /spicy-?lyrics|beautiful-?lyrics/i;
  const syncLyrics = () =>
    root.classList.toggle(
      "gs-has-lyrics-ext",
      (S.Config?.extensions || []).some((e) => lyricsExt.test(e)) ||
        (S.Config?.custom_apps || []).some((a) => lyricsExt.test(a)) ||
        !!document.querySelector("#SpicyLyrics_PageButton, [id^='BeautifulLyrics'], [class*='BeautifulLyrics']")
    );

  // ── Sidebar ─────────────────────────────────────────────────────────────
  const svg = (d) =>
    `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const ICONS = {
    home: svg('<path d="M3.5 10.5 12 3.5l8.5 7"/><path d="M5.5 9v11h4.5v-6h4v6h4.5V9"/>'),
    browse: svg('<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/>'),
    liked: svg('<path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.3a4.3 4.3 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20Z"/>'),
    playlists: svg('<path d="M4 6h11M4 11h11M4 16h7"/><circle cx="17.5" cy="16.5" r="2.5"/><path d="M20 16.5V6.5l-2.5.8"/>'),
    whatsnew: svg('<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15Z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>'),
    marketplace: svg('<path d="M4 9.5 5.5 4h13L20 9.5"/><path d="M4 9.5h16v2a2.7 2.7 0 0 1-5.3 0 2.7 2.7 0 0 1-5.4 0 2.7 2.7 0 0 1-5.3 0Z"/><path d="M5.5 13.5V20h13v-6.5"/>'),
    settings: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/>'),
  };
  const NAV = [
    { section: null, items: [
      { id: "home", label: "Home", run: () => H.push("/"), on: (p) => p === "/" },
      { id: "browse", label: "Browse", run: () => H.push("/search"), on: (p) => p.startsWith("/search") },
      // Playlists live on Home, and Spotify has no other library pages (albums/artists redirect
      // to Liked Songs), so Liked Songs joins the top group instead of a one-item "Library".
      { id: "liked", label: "Liked Songs", run: () => H.push("/collection/tracks"), on: (p) => p.startsWith("/collection/tracks") },
    ] },
    { section: "Discover", items: [
      { id: "whatsnew", label: "What's New", run: () => H.push("/content-feed"), on: (p) => p.startsWith("/content-feed") },
      // Only when the Spicetify Marketplace custom app is installed (it's optional).
      ...((S.Config?.custom_apps || []).includes("marketplace")
        ? [{ id: "marketplace", label: "Marketplace", run: () => H.push("/marketplace"), on: (p) => p.startsWith("/marketplace") }]
        : []),
    ] },
  ];
  const buildSidebar = () => {
    if (document.getElementById("gs-sidebar")?.isConnected) return;
    const side = document.createElement("div");
    side.id = "gs-sidebar";
    const nav = NAV.map((g) => `
      ${g.section ? `<div class="gs-section">${g.section}</div>` : ""}
      ${g.items.map((i) => `<button type="button" class="gs-item" data-nav="${i.id}">${ICONS[i.id]}<span>${i.label}</span></button>`).join("")}`).join("");
    side.innerHTML = `
      <div class="gs-side-top" aria-hidden="true"></div>
      <div class="gs-search-slot" aria-hidden="true"></div>
      <nav class="gs-nav" aria-label="Navigation">${nav}</nav>
      <div class="gs-side-footer">
        <div class="gs-account-slot" aria-hidden="true"></div>
        <button type="button" class="gs-icon-btn" data-nav="settings" aria-label="Settings" title="Settings">${ICONS.settings}</button>
      </div>`;
    for (const g of NAV) for (const i of g.items) side.querySelector(`[data-nav="${i.id}"]`).addEventListener("click", i.run);
    side.querySelector('[data-nav="settings"]').addEventListener("click", () => H.push("/preferences"));
    navBar.prepend(side);
    syncActive();
  };
  const syncActive = () => {
    const p = path();
    for (const g of NAV) for (const i of g.items) document.querySelector(`#gs-sidebar [data-nav="${i.id}"]`)?.classList.toggle("is-active", i.on(p));
    document.querySelector('#gs-sidebar [data-nav="settings"]')?.classList.toggle("is-active", p.startsWith("/preferences"));
  };

  // Position Spotify's native pieces over the sidebar's slots.
  const placeNative = () => {
    const box = (sel) => document.querySelector(sel)?.getBoundingClientRect();
    const nav = navBar.getBoundingClientRect();
    const search = box("#gs-sidebar .gs-search-slot");
    const account = box("#gs-sidebar .gs-account-slot");
    const set = (k, v) => root.style.setProperty(k, `${Math.round(v)}px`);
    set("--gs-nav-left", nav.left);
    set("--gs-nav-top", nav.top);
    set("--gs-nav-width", nav.width);
    if (search) { set("--gs-search-top", search.top); set("--gs-search-left", search.left); set("--gs-search-width", search.width); }
    if (account) { set("--gs-account-top", account.top); set("--gs-account-left", account.left); }
  };
  new ResizeObserver(placeNative).observe(navBar);
  window.addEventListener("resize", placeNative);

  // ── Player style: bar (default) · float · side ───────────────────────────
  const STYLES = [["bar", "Bar"], ["float", "Floating"], ["side", "In sidebar"]];
  const KEY = "glassify:player-style";
  let style = "bar";
  try { style = localStorage.getItem(KEY) || "bar"; } catch {}
  const applyStyle = (s) => {
    style = STYLES.some(([id]) => id === s) ? s : "bar";
    for (const [id] of STYLES) root.classList.toggle(`gs-player-${id}`, id === style);
    try { localStorage.setItem(KEY, style); } catch {}
    requestAnimationFrame(() => { placeNative(); measure(); });
  };
  // Floating player spans the content area; the sidebar card reserves its own height.
  const mainView = document.querySelector(".Root__main-view");
  const playerBar = document.querySelector(".Root__now-playing-bar");
  const measure = () => {
    const set = (k, v) => root.style.setProperty(k, `${Math.round(v)}px`);
    if (mainView) { const r = mainView.getBoundingClientRect(); set("--gs-main-left", r.left); set("--gs-main-width", r.width); }
    if (playerBar && style === "side") set("--gs-player-h", playerBar.getBoundingClientRect().height + 12);
  };
  if (mainView) new ResizeObserver(measure).observe(mainView);
  if (playerBar) new ResizeObserver(measure).observe(playerBar);
  applyStyle(style);
  window.SpotifyCupertino = window.GlassifySidebar = { setPlayerStyle: applyStyle, get playerStyle() { return style; } };
  const registerMenu = (tries = 0) => {
    const M = S.Menu;
    if (!M?.Item || !M?.SubMenu) { if (tries < 30) setTimeout(() => registerMenu(tries + 1), 200); return; }
    const items = STYLES.map(([id, label]) => new M.Item(label, style === id, () => {
      applyStyle(id);
      items.forEach((it, i) => { it.isEnabled = STYLES[i][0] === style; });
    }));
    new M.SubMenu("Player style", items).register();
  };
  registerMenu();

  // A short placeholder fits the sidebar's search box ("What do you want to play?" is cut off).
  const shortPlaceholder = () => {
    const input = document.querySelector(".Root__globalNav input.main-topBar-searchBar");
    if (input && input.placeholder !== "Search") input.placeholder = "Search";
  };

  // ── Home: "Your Playlists" grid ─────────────────────────────────────────
  let playlists = null;
  const loadPlaylists = async () => {
    const res = await S.Platform.RootlistAPI.getContents();
    const out = [];
    const walk = (items) => { for (const i of items || []) { if (i.type === "playlist") out.push(i); else if (i.items) walk(i.items); } };
    walk(res.items);
    playlists = out;
  };
  const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const renderGrid = (host) => {
    const sec = document.createElement("section");
    sec.id = "gs-home-playlists";
    sec.setAttribute("aria-label", "Your Playlists");
    const tiles = [
      `<button type="button" class="gs-tile" data-uri="liked"><span class="gs-tile-art gs-liked-art">${ICONS.liked}</span><span class="gs-tile-name">Liked Songs</span></button>`,
      ...(playlists || []).map((p) => {
        const img = imageUrl(p.images?.[0]?.url);
        return `<button type="button" class="gs-tile" data-uri="${esc(p.uri)}"><span class="gs-tile-art">${img ? `<img src="${esc(img)}" alt="" loading="lazy">` : ICONS.playlists}</span><span class="gs-tile-name">${esc(p.name)}</span></button>`;
      }),
    ].join("");
    const count = (playlists || []).length + 1;
    sec.innerHTML = `<div class="gs-head"><h2 class="gs-h2">Your Playlists</h2>${count > 12 ? `<button type="button" class="gs-more" aria-expanded="false">Show all ${count}</button>` : ""}</div><div class="gs-grid">${tiles}</div>`;
    sec.addEventListener("click", (e) => {
      const more = e.target.closest(".gs-more");
      if (more) {
        const open = sec.classList.toggle("is-expanded");
        more.setAttribute("aria-expanded", String(open));
        more.textContent = open ? "Show less" : `Show all ${count}`;
        fitRows();
        return;
      }
      const t = e.target.closest(".gs-tile");
      if (!t) return;
      const uri = t.dataset.uri;
      H.push(uri === "liked" ? "/collection/tracks" : `/playlist/${uri.split(":").pop()}`);
    });
    host.prepend(sec);
    // Collapsed: exactly two full rows, whatever the width.
    const grid = sec.querySelector(".gs-grid");
    const fitRows = () => {
      const cols = getComputedStyle(grid).gridTemplateColumns.split(" ").length || 1;
      const open = sec.classList.contains("is-expanded");
      grid.querySelectorAll(".gs-tile").forEach((t, i) => { t.hidden = !open && i >= cols * 2; });
    };
    new ResizeObserver(fitRows).observe(grid);
    fitRows();
    // The library list omits some covers (e.g. auto-generated mosaics); fetch those lazily.
    sec.querySelectorAll(".gs-tile").forEach(async (tile) => {
      const uri = tile.dataset.uri;
      if (uri === "liked" || tile.querySelector("img")) return;
      try {
        const meta = await S.Platform.PlaylistAPI.getMetadata(uri);
        const img = imageUrl(meta?.images?.[0]?.url);
        if (img) tile.querySelector(".gs-tile-art").innerHTML = `<img src="${esc(img)}" alt="" loading="lazy">`;
      } catch { /* keep the placeholder */ }
    });
  };
  const ensureHomeGrid = () => {
    if (path() !== "/" || !playlists) return;
    const host = document.querySelector(".main-home-content");
    if (host && !host.querySelector("#gs-home-playlists")) renderGrid(host);
  };
  S.Platform.RootlistAPI.getEvents?.()?.addListener?.("update", () => loadPlaylists().then(() => { document.getElementById("gs-home-playlists")?.remove(); ensureHomeGrid(); }));

  // ── Wiring ──────────────────────────────────────────────────────────────
  // Narrow on purpose: no subtree observer on the whole app (the player's time label
  // changes every second). The Home grid is (re)inserted after each navigation, retrying
  // briefly while Home renders; the sidebar is re-added if React replaces the nav bar.
  // Insert the grid in the same frame Spotify creates Home, before it paints; polling left
  // Home visible for up to 150 ms without the grid, then shifted everything down. The observer
  // only runs for a few seconds after a navigation to Home, never in the background.
  let homeWatch = null;
  const ensureHomeSoon = () => {
    ensureHomeGrid();
    if (path() !== "/" || homeWatch) return;
    const target = document.querySelector(".Root__main-view");
    if (!target) return;
    homeWatch = new MutationObserver(ensureHomeGrid);
    homeWatch.observe(target, { childList: true, subtree: true });
    setTimeout(() => { homeWatch?.disconnect(); homeWatch = null; }, 3000);
  };
  H.listen(() => { ensureHomeSoon(); setTimeout(() => { syncActive(); shortPlaceholder(); }, 60); });
  new MutationObserver(() => { buildSidebar(); placeNative(); }).observe(navBar, { childList: true });

  buildSidebar();
  placeNative();
  syncLyrics();
  shortPlaceholder();
  loadPlaylists().then(ensureHomeSoon);
  setTimeout(() => { placeNative(); syncLyrics(); shortPlaceholder(); measure(); }, 2000);
})();
