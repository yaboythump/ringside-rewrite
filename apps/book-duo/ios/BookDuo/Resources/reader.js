// Book Duo page engine. Runs inside each chapter page of the book.
//
// The chapter is laid out in CSS columns exactly one pane wide, so every
// column is one page. Turning the page slides the body sideways by one pane.
// Swift talks to it through BookDuo.start / configure / goTo / pageOf, and it
// answers through the "bookduo" message handler.
(function () {
  "use strict";
  if (window.BookDuo) return;

  var XHTML = "http://www.w3.org/1999/xhtml";
  var state = { settings: null, page: 0, pages: 1, width: 0, height: 0, started: false, layoutTimer: 0 };

  function post(message) {
    try {
      window.webkit.messageHandlers.bookduo.postMessage(message);
    } catch (e) {
      (window.__bookduoMessages = window.__bookduoMessages || []).push(message);
    }
  }

  function make(tag) {
    return document.createElementNS(XHTML, tag);
  }

  function head() {
    var h = document.head || document.getElementsByTagName("head")[0];
    if (!h) {
      h = make("head");
      document.documentElement.insertBefore(h, document.documentElement.firstChild);
    }
    return h;
  }

  function ensureViewport() {
    if (document.querySelector('meta[name="viewport"]')) return;
    var meta = make("meta");
    meta.setAttribute("name", "viewport");
    meta.setAttribute("content", "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no");
    head().appendChild(meta);
  }

  var FONTS = {
    serif: '"New York", "Iowan Old Style", Georgia, "Times New Roman", serif',
    sans: '-apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
    rounded: '"SF Pro Rounded", ui-rounded, -apple-system, sans-serif',
    mono: 'ui-monospace, Menlo, monospace'
  };

  function css(s, w, h) {
    var mx = Math.round(s.marginX), my = Math.round(s.marginY);
    var size = (18 * s.scale).toFixed(2);
    var rules = [];
    rules.push("html{margin:0!important;padding:0!important;width:" + w + "px!important;height:" + h + "px!important;" +
      "max-width:none!important;overflow:hidden!important;background:" + s.background + "!important;" +
      "font-size:" + size + "px!important;-webkit-text-size-adjust:none!important;text-size-adjust:none!important}");
    rules.push("body{margin:0!important;padding:" + my + "px " + mx + "px!important;box-sizing:border-box!important;" +
      "width:" + w + "px!important;height:" + h + "px!important;max-width:none!important;min-height:0!important;" +
      "column-width:" + (w - 2 * mx) + "px!important;column-gap:" + (2 * mx) + "px!important;column-fill:auto!important;" +
      "column-count:auto!important;overflow:visible!important;font-size:1rem!important;line-height:" + s.lineHeight + "!important;" +
      "background:transparent!important;color:" + s.text + "!important;-webkit-user-select:text;" +
      "transition:none;will-change:transform}");
    rules.push("body.bookduo-animate{transition:transform 0.28s cubic-bezier(0.25,0.8,0.25,1)!important}");
    if (s.font !== "publisher" && FONTS[s.font]) {
      rules.push("body{font-family:" + FONTS[s.font] + "!important}");
      rules.push("body :not(pre):not(code):not(kbd):not(samp):not(tt){font-family:inherit!important}");
    }
    rules.push("p,li,blockquote,dd,dt,td,th,div{line-height:inherit!important}");
    if (s.justify) {
      rules.push("p{text-align:justify!important;-webkit-hyphens:auto!important;hyphens:auto!important}");
    }
    if (s.themeColors) {
      rules.push("body *{color:inherit!important;background-color:transparent!important;border-color:" + s.rule + "!important}");
    }
    rules.push("a,a *{color:" + s.link + "!important}");
    rules.push("img,svg,video,canvas,object,embed{max-width:100%!important;max-height:" + Math.floor((h - 2 * my) * 0.9) +
      "px!important;object-fit:contain;box-sizing:border-box}");
    rules.push("img{height:auto!important;margin-top:0!important;margin-bottom:0!important}");
    rules.push("figure{margin-top:0.4em!important;margin-bottom:0.4em!important}");
    rules.push("figure,img,svg,table,pre,blockquote{break-inside:avoid;-webkit-column-break-inside:avoid}");
    rules.push("h1,h2,h3,h4,h5,h6,hgroup{break-after:avoid;-webkit-column-break-after:avoid}");
    // Forced page breaks would leave blank pages at the start and end of chapters.
    rules.push("*{break-before:auto!important;break-after:auto!important;page-break-before:auto!important;page-break-after:auto!important}");
    rules.push("pre{white-space:pre-wrap!important}");
    rules.push("table{max-width:100%!important}");
    rules.push("::selection{background:" + s.selection + "}");
    if (s.dimImages) rules.push("img,svg image{filter:brightness(0.82) contrast(1.05)}");
    rules.push("#bookduo-end{display:block!important;width:1px!important;height:0!important;margin:0!important;padding:0!important;border:0!important}");
    return rules.join("\n");
  }

  function applyStyle() {
    var el = document.getElementById("bookduo-style");
    if (!el) {
      el = make("style");
      el.setAttribute("id", "bookduo-style");
      head().appendChild(el);
    } else if (el.parentNode.lastChild !== el) {
      el.parentNode.appendChild(el);
    }
    el.textContent = css(state.settings, state.width, state.height);
  }

  function sentinel() {
    var end = document.getElementById("bookduo-end");
    if (!end) {
      end = make("span");
      end.setAttribute("id", "bookduo-end");
      end.setAttribute("aria-hidden", "true");
      document.body.appendChild(end);
    } else if (document.body.lastChild !== end) {
      document.body.appendChild(end);
    }
    return end;
  }

  function offsetLeft(el) {
    // Position in the unshifted layout, whatever page is showing.
    var rect = el.getBoundingClientRect();
    return rect.left + state.page * state.width;
  }

  function measure() {
    if (!document.body) return 1;
    var pages = Math.floor(offsetLeft(sentinel()) / state.width) + 1;
    if (hasContentPast(pages)) pages += 1;
    return Math.max(1, pages);
  }

  function hasContentPast(pages) {
    // A floated or absolutely placed element can poke into one more column than the sentinel.
    var limit = pages * state.width;
    var nodes = document.body.querySelectorAll("img,svg,figure,table");
    for (var i = 0; i < nodes.length; i++) {
      if (offsetLeft(nodes[i]) >= limit) return true;
    }
    return false;
  }

  function show(page, animated) {
    state.page = page;
    var body = document.body;
    if (!body) return;
    if (animated) {
      body.classList.add("bookduo-animate");
    } else {
      body.classList.remove("bookduo-animate");
    }
    body.style.setProperty("transform", "translate3d(" + (-page * state.width) + "px,0,0)", "important");
    document.documentElement.style.setProperty("visibility", page >= state.pages ? "hidden" : "visible", "important");
    if (!animated) void body.offsetWidth;
  }

  function layout(reason) {
    if (!state.started || !document.body) return;
    var w = window.innerWidth, h = window.innerHeight;
    if (w < 40 || h < 40) return;
    state.width = w;
    state.height = h;
    applyStyle();
    var keep = state.page;
    show(0, false);
    var pages = measure();
    state.pages = pages;
    show(keep, false);
    post({ type: "layout", pages: pages, width: w, height: h, reason: reason || "" });
  }

  function scheduleLayout(reason) {
    clearTimeout(state.layoutTimer);
    state.layoutTimer = setTimeout(function () { layout(reason); }, 60);
  }

  function whenSettled(callback) {
    var done = false;
    function go() {
      if (done) return;
      done = true;
      requestAnimationFrame(function () { requestAnimationFrame(callback); });
    }
    var waits = [];
    if (document.fonts && document.fonts.ready) waits.push(document.fonts.ready);
    var images = Array.prototype.slice.call(document.images || []);
    images.forEach(function (img) {
      if (!img.complete) {
        waits.push(new Promise(function (resolve) {
          img.addEventListener("load", resolve, { once: true });
          img.addEventListener("error", resolve, { once: true });
        }));
      }
    });
    Promise.all(waits).then(go, go);
    setTimeout(go, 1500);
  }

  // Taps and swipes. Links and text selection keep working normally.
  var touch = null;
  document.addEventListener("touchstart", function (e) {
    if (e.touches.length !== 1) { touch = null; return; }
    touch = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now() };
  }, { passive: true });
  document.addEventListener("touchend", function (e) {
    if (!touch || !e.changedTouches.length) return;
    var dx = e.changedTouches[0].clientX - touch.x;
    var dy = e.changedTouches[0].clientY - touch.y;
    var quick = Date.now() - touch.t < 700;
    touch = null;
    var selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    if (quick && Math.abs(dx) > 44 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      post({ type: "swipe", forward: dx < 0 });
    }
  }, { passive: true });
  document.addEventListener("click", function (e) {
    if (e.target && e.target.closest && e.target.closest("a[href]")) return;
    var selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    post({ type: "tap", x: e.clientX / state.width, y: e.clientY / state.height });
  }, false);
  window.addEventListener("resize", function () { scheduleLayout("resize"); });

  window.BookDuo = {
    start: function (settings, page) {
      state.settings = settings;
      state.page = Math.max(0, page | 0);
      state.started = true;
      ensureViewport();
      if (document.body) sentinel();
      whenSettled(function () { layout("start"); });
    },
    configure: function (settings) {
      state.settings = settings;
      if (state.started) layout("settings");
    },
    goTo: function (page, animated) {
      show(Math.max(0, page | 0), !!animated && Math.abs(page - state.page) <= 2);
      return state.page;
    },
    pageOf: function (id) {
      var el = id ? document.getElementById(id) : null;
      if (!el) {
        var named = document.getElementsByName(id);
        el = named && named.length ? named[0] : null;
      }
      if (!el) return -1;
      return Math.max(0, Math.min(state.pages - 1, Math.floor((offsetLeft(el) + 1) / state.width)));
    },
    state: function () { return { page: state.page, pages: state.pages, width: state.width, height: state.height }; }
  };
})();
