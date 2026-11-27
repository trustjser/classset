/* 课集 ClassSet 官网 · 交互
   - 移动端菜单开关
   - 滚动揭示动画（IntersectionObserver）
   - 页脚年份自动填充
   - 通知表单（前端校验，无后端，仅本地反馈）
   纯原生 JS，无外部依赖。 */
(function () {
  "use strict";

  /* ---- PWA Service Worker 注册与安装引导 ---- */
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker
        .register("./classsetapp/sw.js", { scope: "./classsetapp/" })
        .catch(function () {});
    });
  }

  var deferredInstallPrompt = null;
  var installButtons = [
    document.getElementById("pwaInstallHero"),
    document.getElementById("pwaInstallCard")
  ].filter(Boolean);

  function setInstallButtonsVisible(visible) {
    installButtons.forEach(function (btn) {
      btn.hidden = !visible;
    });
  }

  window.addEventListener("beforeinstallprompt", function (e) {
    e.preventDefault();
    deferredInstallPrompt = e;
    setInstallButtonsVisible(true);
  });

  window.addEventListener("appinstalled", function () {
    deferredInstallPrompt = null;
    setInstallButtonsVisible(false);
  });

  installButtons.forEach(function (btn) {
    btn.addEventListener("click", function (event) {
      if (!deferredInstallPrompt || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      var prompt = deferredInstallPrompt;
      deferredInstallPrompt = null;
      prompt.prompt().catch(function () {});
    });
  });

  /* ---- 移动端菜单 ---- */
  var toggle = document.getElementById("navToggle");
  var menu = document.getElementById("mobileMenu");
  if (toggle && menu) {
    toggle.addEventListener("click", function () {
      var open = menu.classList.toggle("is-open");
      menu.hidden = !open;
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "关闭菜单" : "打开菜单");
    });
    // 点击菜单内链接后自动收起
    menu.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        menu.classList.remove("is-open");
        menu.hidden = true;
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* ---- 滚动揭示动画 ---- */
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && reveals.length) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    // 不支持时直接显示
    reveals.forEach(function (el) { el.classList.add("is-visible"); });
  }

  /* ---- 页脚年份 ---- */
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  /* ---- 桌面端下载：探测当前系统并前置对应下载入口 ----
     所有入口默认指向 GitHub Releases 最新页（无网络/接口失败时仍可下载）；
     页面加载后尝试用 GitHub API 把按钮换成最新版的真实安装包直链。 */
  var GITHUB_REPO = "trustjser/classset";
  var RELEASES_PAGE = "https://github.com/" + GITHUB_REPO + "/releases/latest";
  var RELEASES_API = "https://api.github.com/repos/" + GITHUB_REPO + "/releases/latest";
  var LINK_CACHE_KEY = "classset-download-links-v1";
  var LINK_CACHE_TTL = 6 * 60 * 60 * 1000; // 6 小时

  function detectOS() {
    var uaData = navigator.userAgentData;
    var platform = (uaData && uaData.platform) || navigator.platform || "";
    var ua = navigator.userAgent || "";
    if (/mac/i.test(platform) || /Macintosh|Mac OS X/i.test(ua)) return "macos";
    if (/win/i.test(platform) || /Windows/i.test(ua)) return "windows";
    if (/linux/i.test(platform) || /Linux/i.test(ua)) return "linux";
    return "";
  }

  function detectMacArch() {
    var uaData = navigator.userAgentData;
    var arch = uaData && uaData.architecture;
    if (arch) return /arm|aarch64/i.test(arch) ? "arm" : "x64";
    // Safari 等不暴露架构信息时默认 Apple Silicon；Intel 版本始终可从下方链接下载
    return "arm";
  }

  function highlightCurrentOS(os) {
    var grid = document.getElementById("platformGrid");
    if (!grid || !os) return;
    var cards = grid.querySelectorAll("[data-os]");
    Array.prototype.forEach.call(cards, function (card) {
      if (card.getAttribute("data-os") !== os) return;
      grid.insertBefore(card, grid.firstChild);
      card.classList.add("platform--current");
      var badge = card.querySelector("[data-os-current]");
      if (badge) badge.hidden = false;
      var btn = card.querySelector(".platform__btn");
      if (btn) {
        btn.classList.remove("btn--ghost");
        btn.classList.add("btn--primary");
      }
    });
  }

  function pickUrl(assets, pattern) {
    for (var i = 0; i < assets.length; i++) {
      if (pattern.test(assets[i].name || "") && assets[i].browser_download_url) {
        return assets[i].browser_download_url;
      }
    }
    return null;
  }

  function buildDownloadLinks(release) {
    var assets = (release && release.assets) || [];
    var dmg = assets.filter(function (a) { return /\.dmg$/i.test(a.name || ""); });
    var macArm = pickUrl(dmg, /aarch64|arm64/i) || pickUrl(dmg, /\.dmg$/i);
    var macX64 = pickUrl(dmg, /x64|x86_64|intel/i) || pickUrl(dmg, /\.dmg$/i);
    return {
      "macos-arm": macArm,
      "macos-x64": macX64,
      "windows": pickUrl(assets, /\.msi$/i) || pickUrl(assets, /\.exe$/i),
      "linux-appimage": pickUrl(assets, /appimage$/i),
      "linux-deb": pickUrl(assets, /\.deb$/i)
    };
  }

  function readLinkCache() {
    try {
      var raw = localStorage.getItem(LINK_CACHE_KEY);
      if (!raw) return null;
      var cached = JSON.parse(raw);
      if (!cached || !cached.links || !cached.time || Date.now() - cached.time > LINK_CACHE_TTL) return null;
      return cached.links;
    } catch (e) {
      return null;
    }
  }

  function writeLinkCache(links) {
    try {
      localStorage.setItem(LINK_CACHE_KEY, JSON.stringify({ time: Date.now(), links: links }));
    } catch (e) { /* 隐私模式下忽略 */ }
  }

  function applyDownloadLinks(links) {
    var nodes = document.querySelectorAll("[data-download]");
    Array.prototype.forEach.call(nodes, function (node) {
      var url = links[node.getAttribute("data-download")];
      if (url) node.href = url;
    });
    var macBtn = document.querySelector('[data-download="macos"]');
    if (macBtn) {
      var arch = detectMacArch();
      var archLabel = arch === "arm" ? "Apple Silicon" : "Intel";
      macBtn.href = links[arch === "arm" ? "macos-arm" : "macos-x64"] || RELEASES_PAGE;
      macBtn.textContent = "下载 macOS 版（" + archLabel + "）";
    }
    var linuxBtn = document.querySelector('[data-download="linux"]');
    if (linuxBtn) linuxBtn.href = links["linux-appimage"] || links["linux-deb"] || RELEASES_PAGE;
  }

  function loadDownloadLinks() {
    var cached = readLinkCache();
    if (cached) {
      applyDownloadLinks(cached);
      return;
    }
    if (typeof fetch !== "function" || !document.querySelector("[data-download]")) return;
    fetch(RELEASES_API, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (res) {
        if (!res.ok) throw new Error("GitHub Releases API unavailable");
        return res.json();
      })
      .then(function (release) {
        var links = buildDownloadLinks(release);
        writeLinkCache(links);
        applyDownloadLinks(links);
      })
      .catch(function () { /* 保留 Releases 最新页作为回退入口 */ });
  }

  highlightCurrentOS(detectOS());
  loadDownloadLinks();

  /* ---- 通知表单（前端校验，占位提交） ---- */
  var form = document.getElementById("notifyForm");
  var hint = document.getElementById("notifyHint");
  if (form && hint) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var input = document.getElementById("email");
      var val = (input.value || "").trim();
      var ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val);
      if (!ok) {
        hint.style.color = "var(--danger)";
        hint.textContent = "请输入有效的邮箱地址。";
        input.focus();
        return;
      }
      hint.style.color = "var(--success)";
      hint.textContent = "已记下，" + val + " 会在首个正式版发布时收到通知。";
      form.reset();
    });
  }

  /* ---- 示例课表科目配色：复刻 lib/core/theme/subject_colors.dart ----
     10 色板 + FNV-1a 散列；文字=饱和主色，格底=该色 13% 叠白（浅色模式）。 */
  var SUBJECT_PALETTE = [
    "#A1396D", "#9B521E", "#806314", "#4F7029", "#1F7457",
    "#117783", "#326CAB", "#5C56AC", "#8253A3", "#9C477D"
  ];
  function subjectIndex(id) {
    // 复刻 Dart：乘法用 BigInt 保持低 32 位精确；^ 后用 >>>0 强制无符号，避免 JS 有符号运算得到负数
    var hash = 0x811c9dc5;
    for (var i = 0; i < id.length; i++) {
      hash ^= id.charCodeAt(i);
      hash = Number((BigInt(hash) * 0x01000193n) & 0xFFFFFFFFn);
    }
    hash = (hash ^ (hash >>> 15)) >>> 0;
    hash = Number((BigInt(hash) * 0x2545f491n) & 0xFFFFFFFFn);
    hash = (hash ^ (hash >>> 13)) >>> 0;
    return hash % SUBJECT_PALETTE.length;
  }
  function tint(fg, alpha) {
    var h = fg.replace("#", "");
    var c = [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
    var mix = function (x) { return Math.round(x * alpha + 255 * (1 - alpha)); };
    return "rgb(" + mix(c[0]) + "," + mix(c[1]) + "," + mix(c[2]) + ")";
  }
  var subjCells = document.querySelectorAll(".cell[data-subject]");
  // 真实应用按「科目唯一 ID」散列得到稳定配色；示例课表用科目名作键会导致短名碰撞，
  // 故此处给各科目固定分配调色板槽位，保证不同科目颜色不同，且全部取自同一 10 色板 + 13% 浅底。
  var SUBJECT_SLOT = { "语文": 0, "数学": 1, "英语": 2, "体育": 3, "美术": 4, "物理": 5 };
  for (var s = 0; s < subjCells.length; s++) {
    var el = subjCells[s];
    var key = el.getAttribute("data-subject");
    var slot = SUBJECT_SLOT.hasOwnProperty(key) ? SUBJECT_SLOT[key] : subjectIndex(key);
    var fg = SUBJECT_PALETTE[slot];
    el.style.color = fg;
    el.style.backgroundColor = tint(fg, 0.13);
    el.style.border = "1px solid " + tint(fg, 0.3);
  }
})();
