// ==UserScript==
// @name         Feed Remote
// @namespace    feed-remote
// @version      1.2.0
// @description  Scroll TikTok, YouTube Shorts and Instagram Reels with global hotkeys (requires feed-remote-helper.ps1)
// @homepageURL  https://github.com/baris-bilaloglu/feed-remote
// @downloadURL  https://raw.githubusercontent.com/baris-bilaloglu/feed-remote/main/firefox/feed-remote.user.js
// @updateURL    https://raw.githubusercontent.com/baris-bilaloglu/feed-remote/main/firefox/feed-remote.user.js
// @match        *://*.tiktok.com/*
// @match        *://*.youtube.com/*
// @match        *://*.instagram.com/*
// @grant        GM_xmlhttpRequest
// @connect      localhost
// @run-at       document-idle
// @noframes
// ==/UserScript==

(function () {
  "use strict";
  const PORT = 17345;
  const ID = Math.random().toString(36).slice(2, 10);
  let seq = -1;
  let boot = "";

  // Only the TikTok home feed, YouTube Shorts and Instagram Reels count as a feed
  function isFeed() {
    if (document.visibilityState !== "visible") return false;
    const h = location.hostname;
    const p = location.pathname;
    if (h.includes("tiktok.com")) return p === "/" || p.startsWith("/foryou") || p.startsWith("/following");
    if (h.includes("youtube.com")) return p.startsWith("/shorts/");
    if (h.includes("instagram.com")) return p.startsWith("/reels") || p.startsWith("/reel/");
    return false;
  }

  const url = (path, extra = "") =>
    `http://localhost:${PORT}/${path}?id=${ID}&feed=${isFeed() ? 1 : 0}${extra}`;

  function poll() {
    GM_xmlhttpRequest({
      method: "GET",
      url: url("wait", `&since=${seq}&boot=${boot}`),
      timeout: 15000,
      onload: (r) => {
        try {
          const d = JSON.parse(r.responseText);
          boot = d.boot;
          seq = d.seq;
          if (d.cmd) act(d.cmd);
        } catch (e) {}
        setTimeout(poll, 0);
      },
      onerror: () => setTimeout(poll, 3000), // helper not running: retry every 3 s
      ontimeout: () => setTimeout(poll, 0)
    });
  }

  // Tell the helper right away when the page stops or starts being a feed,
  // so the mouse side buttons switch back to normal back / forward.
  let lastFeed = null;
  function report(force) {
    const f = isFeed();
    if (f === lastFeed && !force) return;
    lastFeed = f;
    GM_xmlhttpRequest({ method: "GET", url: url("state"), timeout: 3000 });
  }
  setInterval(report, 1000);
  document.addEventListener("visibilitychange", () => report(true));
  window.addEventListener("pagehide", () =>
    GM_xmlhttpRequest({ method: "GET", url: url("state", "&gone=1"), timeout: 1000 })
  );

  function act(cmd) {
    if (!isFeed()) return; // only act on a visible feed

    const mid = window.innerHeight / 2;
    const sized = (el) => {
      const r = el.getBoundingClientRect();
      return r.height > 100 && r.width > 100;
    };
    const dist = (el) => {
      const r = el.getBoundingClientRect();
      return Math.abs(r.top + r.height / 2 - mid);
    };
    const closest = (els) => els.reduce((b, el) => (!b || dist(el) < dist(b) ? el : b), null);

    if (cmd === "toggle") {
      const v = closest([...document.querySelectorAll("video")].filter(sized));
      if (v) v.paused ? v.play() : v.pause();
      return;
    }

    const dir = cmd === "next" ? 1 : -1;

    // 1) YouTube Shorts: use the native navigation buttons
    const ytBtn = document.querySelector(
      dir > 0 ? "#navigation-button-down button" : "#navigation-button-up button"
    );
    if (ytBtn) { ytBtn.click(); return; }

    // 2) Find the feed's scroll container and scroll it by one video
    //    (on TikTok it is overflow:hidden + scroll-snap, but still scrollable from JS)
    const item = closest(
      [...document.querySelectorAll('article, [data-e2e="recommend-list-item-container"], ytd-reel-video-renderer, video')].filter(sized)
    );
    if (item) {
      let box = item.parentElement;
      while (box && box !== document.documentElement) {
        if (box.scrollHeight > box.clientHeight + 10) break;
        box = box.parentElement;
      }
      if (box && box !== document.documentElement && box !== document.body) {
        box.scrollBy({ top: dir * box.clientHeight, behavior: "smooth" });
        return;
      }
    }

    // 3) Fallback: synthetic arrow key + scroll the page
    const key = dir > 0 ? "ArrowDown" : "ArrowUp";
    const opts = { key, code: key, keyCode: dir > 0 ? 40 : 38, which: dir > 0 ? 40 : 38, bubbles: true };
    document.dispatchEvent(new KeyboardEvent("keydown", opts));
    document.dispatchEvent(new KeyboardEvent("keyup", opts));
    window.scrollBy({ top: dir * window.innerHeight, behavior: "smooth" });
  }

  report(true);
  poll();
})();
