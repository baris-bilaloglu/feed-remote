const PATTERNS = [
  "*://*.tiktok.com/*",
  "*://*.youtube.com/shorts/*",
  "*://*.instagram.com/*"
];

// Only the TikTok home feed, YouTube Shorts and Instagram Reels count as a feed
const FEED_URLS = [
  /^https?:\/\/([a-z]+\.)?tiktok\.com\/(\?|#|$|foryou|following)/,
  /^https?:\/\/([a-z]+\.)?youtube\.com\/shorts\//,
  /^https?:\/\/([a-z]+\.)?instagram\.com\/(reels|reel\/)/
];
const isFeedUrl = (url) => !!url && FEED_URLS.some((r) => r.test(url));

// Briefly show a badge on the toolbar icon (✓ = worked, ? = no feed tab, ! = problem)
function flash(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 1200);
}

chrome.commands.onCommand.addListener((command) => runCommand(command));

async function runCommand(command) {
  console.log("Command received:", command);
  const tab = await pickTab();
  if (!tab) {
    console.warn("No TikTok / Shorts / Reels feed tab found");
    flash("?", "#d33");
    return;
  }
  try {
    const [res] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: controlFeed,
      args: [command]
    });
    console.log("Tab:", tab.url, "→ result:", res && res.result);
    flash(res && res.result === "none" ? "!" : "✓", res && res.result === "none" ? "#d33" : "#2a2");
  } catch (e) {
    console.error("Feed Remote error:", e);
    flash("!", "#d33");
  }
}

// Prefer the feed tab that is active in its window and playing audio
async function pickTab() {
  const tabs = (await chrome.tabs.query({ url: PATTERNS })).filter((t) => isFeedUrl(t.url));
  if (!tabs.length) return null;
  const score = (t) => (t.active ? 2 : 0) + (t.audible ? 1 : 0);
  tabs.sort((a, b) => score(b) - score(a) || (b.lastAccessed || 0) - (a.lastAccessed || 0));
  return tabs[0];
}

// ---------------------------------------------------------------------------
// Optional mouse side buttons through the native helper (see /native).
// The helper takes over the side buttons only while we tell it a feed is open.
// ---------------------------------------------------------------------------
const HOST = "com.feedremote.host";
const HOST_COMMANDS = { next: "next-video", prev: "prev-video", toggle: "toggle-play" };
let port = null;
let lastFeed = null;

function connectHost() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    port = null;
    return;
  }
  lastFeed = null;
  port.onMessage.addListener((msg) => {
    if (msg.hello) {
      console.log("Mouse helper connected, hook:", msg.hook);
      updateFeed(true);
    }
    if (msg.cmd && HOST_COMMANDS[msg.cmd]) runCommand(HOST_COMMANDS[msg.cmd]);
  });
  port.onDisconnect.addListener(() => {
    // Not installed, or it crashed. Try again later.
    console.log("Mouse helper not connected:", chrome.runtime.lastError && chrome.runtime.lastError.message);
    port = null;
    setTimeout(connectHost, 30000);
  });
}

// A feed is "open" if it is the selected tab of a window that isn't minimized
async function feedOpen() {
  const wins = await chrome.windows.getAll({ populate: true });
  return wins.some(
    (w) => w.state !== "minimized" && w.tabs.some((t) => t.active && isFeedUrl(t.url))
  );
}

async function updateFeed(force) {
  if (!port) return;
  const f = await feedOpen();
  if (f !== lastFeed || force) {
    lastFeed = f;
    port.postMessage({ feed: f });
  }
}

chrome.tabs.onActivated.addListener(() => updateFeed());
chrome.tabs.onUpdated.addListener((id, info) => { if (info.url) updateFeed(); });
chrome.tabs.onRemoved.addListener(() => updateFeed());
chrome.windows.onFocusChanged.addListener(() => updateFeed());
setInterval(updateFeed, 1000);   // catches minimize / restore
chrome.runtime.onStartup.addListener(connectHost);
chrome.runtime.onInstalled.addListener(connectHost);
connectHost();

// Injected into the page; must be fully self-contained
function controlFeed(cmd) {
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

  if (cmd === "toggle-play") {
    const v = closest([...document.querySelectorAll("video")].filter(sized));
    if (!v) return "none";
    v.paused ? v.play() : v.pause();
    return "toggle";
  }

  const dir = cmd === "next-video" ? 1 : -1;

  // 1) YouTube Shorts: use the native navigation buttons
  const ytBtn = document.querySelector(
    dir > 0 ? "#navigation-button-down button" : "#navigation-button-up button"
  );
  if (ytBtn) {
    ytBtn.click();
    return "yt-button";
  }

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
      return "container";
    }
  }

  // 3) Fallback: synthetic arrow key + scroll the page
  const key = dir > 0 ? "ArrowDown" : "ArrowUp";
  const opts = { key, code: key, keyCode: dir > 0 ? 40 : 38, which: dir > 0 ? 40 : 38, bubbles: true };
  document.dispatchEvent(new KeyboardEvent("keydown", opts));
  document.dispatchEvent(new KeyboardEvent("keyup", opts));
  const se = document.scrollingElement;
  if (se.scrollHeight > se.clientHeight + 10) {
    se.scrollBy({ top: dir * window.innerHeight, behavior: "smooth" });
    return "page";
  }
  return "none";
}
