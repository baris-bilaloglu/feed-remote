const PATTERNS = [
  "*://*.tiktok.com/*",
  "*://*.youtube.com/shorts/*",
  "*://*.instagram.com/*"
];

// Briefly show a badge on the toolbar icon (✓ = worked, ? = no tab, ! = problem)
function flash(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 1200);
}

chrome.commands.onCommand.addListener(async (command) => {
  console.log("Command received:", command);
  const tab = await pickTab();
  if (!tab) {
    console.warn("No TikTok / Shorts / Reels tab found");
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
});

// Prefer the tab that is active in its window and playing audio
async function pickTab() {
  const tabs = await chrome.tabs.query({ url: PATTERNS });
  if (!tabs.length) return null;
  const score = (t) => (t.active ? 2 : 0) + (t.audible ? 1 : 0);
  tabs.sort((a, b) => score(b) - score(a) || (b.lastAccessed || 0) - (a.lastAccessed || 0));
  return tabs[0];
}

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
