// The site's own script: the menu that folds behind a button on a narrow screen, and the
// search. Neither is needed to read the pages: without the script the links of the menu
// stay in the bar and the search button never shows.
(function () {
  "use strict";

  // ---- the menu ----
  var bar = document.querySelector(".top");
  var menu = document.getElementById("menu");
  var burger = document.getElementById("menu-button");

  function setMenu(open) {
    menu.classList.toggle("open", open);
    burger.setAttribute("aria-expanded", open ? "true" : "false");
    burger.setAttribute("aria-label", open ? "Close the menu" : "Menu");
  }

  if (bar && menu && burger) {
    burger.hidden = false;
    burger.addEventListener("click", function () {
      setMenu(!menu.classList.contains("open"));
    });
    // A link was chosen: the page changes, or its section opens, so the menu is done.
    menu.addEventListener("click", function (e) {
      if (e.target.closest("a")) setMenu(false);
    });
    document.addEventListener("click", function (e) {
      if (menu.classList.contains("open") && !bar.contains(e.target)) setMenu(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && menu.classList.contains("open")) {
        setMenu(false);
        burger.focus();
      }
    });
    // Back to a wide screen the menu is the bar again.
    var wide = matchMedia("(min-width: 901px)");
    var leave = function (q) { if (q.matches) setMenu(false); };
    if (wide.addEventListener) wide.addEventListener("change", leave);
    else if (wide.addListener) wide.addListener(leave);
  }

  // ---- the search ----
  var panel = document.getElementById("search");
  var opener = document.getElementById("search-open");
  var input = document.getElementById("search-input");
  var list = document.getElementById("search-results");
  var status = document.getElementById("search-status");
  var closer = document.getElementById("search-close");
  if (!panel || !opener || !input || !list || !status) return;
  opener.hidden = false;

  var docs = null;
  var loading = null;
  var shown = [];
  var active = -1;
  var LIMIT = 12;
  // Where a page is told apart when two match alike: the pages that teach come first.
  var BOOST = { reference: 3, guides: 2, examples: 2, messages: 1, faq: 1, tools: 1 };

  function prepare(d) {
    return {
      t: d.t, u: d.u, s: d.s, d: d.d, c: d.c, h: !!d.h,
      tl: d.t.toLowerCase(), dl: (d.d || "").toLowerCase(), cl: (d.c || "").toLowerCase(),
      boost: (BOOST[d.s] || 0) - (d.h ? 1 : 0)
    };
  }

  function load() {
    if (docs) return Promise.resolve(docs);
    if (!loading) {
      loading = fetch(panel.dataset.index)
        .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
        .then(function (list) { docs = list.map(prepare); return docs; })
        .catch(function (e) { loading = null; throw e; });
    }
    return loading;
  }

  // True when `term` begins a word of `text`.
  function startsWord(text, term) {
    var i = text.indexOf(term);
    while (i > 0) {
      if (/[^a-z0-9]/.test(text.charAt(i - 1))) return true;
      i = text.indexOf(term, i + 1);
    }
    return i === 0;
  }

  // How well a page answers the words asked for; 0 when one of the words is nowhere in it.
  function score(doc, terms) {
    var total = 0;
    for (var i = 0; i < terms.length; i++) {
      var term = terms[i];
      var s = 0;
      if (doc.tl === term) s = 40;
      else if (doc.tl.indexOf(term) === 0) s = 24;
      else if (startsWord(doc.tl, term)) s = 14;
      else if (doc.tl.indexOf(term) > -1) s = 8;
      if (doc.dl.indexOf(term) > -1) s += 4;
      if (doc.cl.indexOf(term) > -1) s += 1;
      if (s === 0) return 0;
      total += s;
    }
    return total + doc.boost;
  }

  function search(query) {
    var terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) return [];
    var found = [];
    for (var i = 0; i < docs.length; i++) {
      var s = score(docs[i], terms);
      if (s > 0) found.push({ doc: docs[i], score: s });
    }
    found.sort(function (a, b) { return b.score - a.score || a.doc.t.length - b.doc.t.length; });
    return found.slice(0, LIMIT).map(function (f) { return f.doc; });
  }

  // The text with the words searched for set in <mark>, built from nodes so nothing in a page's
  // text is ever read as markup.
  function marked(text, terms) {
    var frag = document.createDocumentFragment();
    var lower = text.toLowerCase();
    var at = 0;
    while (at < text.length) {
      var best = -1, bestLength = 0;
      for (var i = 0; i < terms.length; i++) {
        var j = lower.indexOf(terms[i], at);
        if (j > -1 && (best === -1 || j < best)) { best = j; bestLength = terms[i].length; }
      }
      if (best === -1) break;
      frag.appendChild(document.createTextNode(text.slice(at, best)));
      var m = document.createElement("mark");
      m.textContent = text.slice(best, best + bestLength);
      frag.appendChild(m);
      at = best + bestLength;
    }
    frag.appendChild(document.createTextNode(text.slice(at)));
    return frag;
  }

  // A few words of the page round the first of the words searched for, when its summary has none.
  function snippet(doc, terms) {
    var text = doc.d.replace(/`/g, "");
    var lower = text.toLowerCase();
    var hit = terms.some(function (t) { return lower.indexOf(t) > -1; });
    if (hit || !doc.c) return text;
    var from = -1;
    for (var i = 0; i < terms.length; i++) {
      var j = doc.cl.indexOf(terms[i]);
      if (j > -1 && (from === -1 || j < from)) from = j;
    }
    if (from === -1) return text;
    var start = Math.max(0, from - 40);
    var piece = doc.c.slice(start, start + 140).trim();
    return (start > 0 ? "… " : "") + piece + (start + 140 < doc.c.length ? " …" : "");
  }

  function setActive(i) {
    var items = list.children;
    if (active > -1 && items[active]) {
      items[active].removeAttribute("aria-selected");
      items[active].classList.remove("active");
    }
    active = i;
    if (i > -1 && items[i]) {
      items[i].setAttribute("aria-selected", "true");
      items[i].classList.add("active");
      input.setAttribute("aria-activedescendant", items[i].id);
      items[i].scrollIntoView({ block: "nearest" });
    } else {
      input.removeAttribute("aria-activedescendant");
    }
  }

  function render() {
    var query = input.value.trim();
    var terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    list.textContent = "";
    shown = [];
    active = -1;
    input.removeAttribute("aria-activedescendant");
    if (!terms.length) {
      input.setAttribute("aria-expanded", "false");
      status.textContent = "Type a word, a verb or a message to look for.";
      return;
    }
    if (!docs) {
      status.textContent = "Loading the search…";
      return;
    }
    shown = search(query);
    shown.forEach(function (doc, i) {
      var li = document.createElement("li");
      li.id = "search-result-" + i;
      li.setAttribute("role", "option");
      var a = document.createElement("a");
      a.href = doc.u;
      var title = document.createElement("span");
      title.className = "r-title";
      title.appendChild(marked(doc.t, terms));
      var where = document.createElement("span");
      where.className = "r-section";
      where.textContent = doc.s;
      a.appendChild(title);
      a.appendChild(where);
      var text = snippet(doc, terms);
      if (text) {
        var p = document.createElement("span");
        p.className = "r-text";
        p.appendChild(marked(text, terms));
        a.appendChild(p);
      }
      li.appendChild(a);
      li.addEventListener("mousemove", function () { if (active !== i) setActive(i); });
      list.appendChild(li);
    });
    input.setAttribute("aria-expanded", shown.length ? "true" : "false");
    status.textContent = shown.length
      ? shown.length + (shown.length === 1 ? " result" : " results") + " for “" + query + "”"
      : "Nothing found for “" + query + "”. Try a shorter word, or the name of a verb.";
    if (shown.length) setActive(0);
  }

  function isOpen() { return !panel.hidden; }

  function open() {
    if (isOpen()) { input.focus(); input.select(); return; }
    panel.hidden = false;
    opener.setAttribute("aria-expanded", "true");
    if (menu) setMenu(false);
    input.focus();
    input.select();
    render();
    load().then(render, function () {
      status.textContent = "The search could not be loaded. Check the connection and open it again.";
    });
  }

  function close(back) {
    if (!isOpen()) return;
    panel.hidden = true;
    opener.setAttribute("aria-expanded", "false");
    if (back) opener.focus();
  }

  opener.addEventListener("click", function () { if (isOpen()) close(true); else open(); });
  if (closer) closer.addEventListener("click", function () { close(true); });
  input.addEventListener("input", render);
  input.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      if (shown.length) setActive((active + 1) % shown.length);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      if (shown.length) setActive((active - 1 + shown.length) % shown.length);
    } else if (e.key === "Enter") {
      e.preventDefault();
      var item = list.children[active > -1 ? active : 0];
      var link = item && item.querySelector("a");
      if (link) location.href = link.href;
    } else if (e.key === "Escape") {
      e.preventDefault();
      if (input.value) { input.value = ""; render(); } else close(true);
    }
  });
  // A link of the results was followed (or the page went elsewhere): the panel is done.
  list.addEventListener("click", function (e) { if (e.target.closest("a")) close(false); });
  document.addEventListener("click", function (e) {
    if (isOpen() && !panel.contains(e.target) && !opener.contains(e.target)) close(false);
  });
  document.addEventListener("keydown", function (e) {
    if (e.defaultPrevented) return;
    var typing = /^(input|textarea|select)$/i.test(e.target.tagName) || e.target.isContentEditable;
    if ((e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) ||
        (e.key.toLowerCase() === "k" && (e.ctrlKey || e.metaKey) && !e.altKey)) {
      e.preventDefault();
      open();
    } else if (e.key === "Escape" && isOpen()) {
      close(true);
    }
  });
})();
