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
    btn.addEventListener("click", function () {
      if (!deferredInstallPrompt) return;
      deferredInstallPrompt.prompt();
      deferredInstallPrompt.userChoice
        .then(function (choice) {
          if (choice && choice.outcome === "accepted") {
            deferredInstallPrompt = null;
            setInstallButtonsVisible(false);
          }
        })
        .catch(function () {});
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
    "#DB2777", "#EA580C", "#CA8A04", "#65A30D", "#16A34A",
    "#0D9488", "#0284C7", "#4F46E5", "#7C3AED", "#C026D3"
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
  }
})();
