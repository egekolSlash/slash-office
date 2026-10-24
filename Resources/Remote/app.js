"use strict";

// Metinler: telefonun dili Türkçeyse Türkçe, değilse İngilizce.
const STRINGS = {
  en: {
    pairWarning: "A paired phone can make Claude run anything on your Mac. Pair only your own phone.",
    code: "Code from Slash Office Settings", name: "Name for this phone", pair: "Pair",
    wrongCode: "Wrong or expired code. Create a new one in Settings.", offline: "Reconnecting…",
    empty: "No sessions. Start one in Slash Office.", back: "‹ Sessions", send: "Send", stop: "Stop",
    todos: "Todo list", placeholder: "Write to Claude…",
    not_running: "This session is not running in Slash Office on your Mac.", invalid_text: "The message is empty or too long.",
    bad_message: "The Mac did not understand that.", failed: "Could not load.",
    status: { starting: "Starting", idle: "Idle", working: "Working", permission: "Needs permission", question: "Asking", exited: "Stopped" },
    finished: "Done",
    background: (n) => `${n} in background`,
  },
  tr: {
    pairWarning: "Eşleşmiş bir telefon Mac'inde Claude'a her şeyi yaptırabilir. Yalnızca kendi telefonunu eşleştir.",
    code: "Slash Office Ayarlar'daki kod", name: "Bu telefonun adı", pair: "Eşleştir",
    wrongCode: "Kod yanlış ya da süresi dolmuş. Ayarlar'dan yeni kod oluştur.", offline: "Yeniden bağlanıyor…",
    empty: "Oturum yok. Slash Office'te bir oturum başlat.", back: "‹ Oturumlar", send: "Gönder", stop: "Durdur",
    todos: "Yapılacaklar", placeholder: "Claude'a yaz…",
    not_running: "Bu oturum Mac'teki Slash Office'te çalışmıyor.", invalid_text: "Mesaj boş ya da çok uzun.",
    bad_message: "Mac bunu anlamadı.", failed: "Yüklenemedi.",
    status: { starting: "Başlıyor", idle: "Boşta", working: "Çalışıyor", permission: "İzin bekliyor", question: "Soru soruyor", exited: "Durdu" },
    finished: "Bitti",
    background: (n) => `${n} arka planda`,
  },
};
const T = STRINGS[(navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en"];
const TOKEN_KEY = "slashoffice.token";
const $ = (id) => document.getElementById(id);

const state = {
  token: null, socket: null, connected: false, retry: 1000,
  sessions: [], current: null, cursor: null, seen: new Set(),
  loading: null, loadingId: null, pending: false, ticket: 0,  // loading: uçuştaki isteğin bileti
};

function readToken() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }
function writeToken(value) {
  try { value ? localStorage.setItem(TOKEN_KEY, value) : localStorage.removeItem(TOKEN_KEY); } catch {}
}

function show(view) {
  for (const id of ["pair", "list", "chat"]) $(id).hidden = id !== view;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

async function api(path) {
  const response = await fetch(path, { headers: { Authorization: `Bearer ${state.token}` }, cache: "no-store" });
  if (response.status === 401) { forget(); throw new Error("unauthorized"); }
  if (!response.ok) throw new Error(String(response.status));
  return response.json();
}

// Eşleştirme

function setupPairing(code) {
  $("pair-warning").textContent = T.pairWarning;
  $("pair-code-label").textContent = T.code;
  $("pair-name-label").textContent = T.name;
  $("pair-button").textContent = T.pair;
  $("pair-code").value = code || "";
  $("pair-name").value = /iPhone/.test(navigator.userAgent) ? "iPhone" : /Android/.test(navigator.userAgent) ? "Android" : "Phone";
  $("pair-error").textContent = "";
  show("pair");
}

$("pair-button").addEventListener("click", async () => {
  $("pair-error").textContent = "";
  const response = await fetch("/api/pair", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code: $("pair-code").value.trim(), deviceName: $("pair-name").value }),
  }).catch(() => null);
  if (!response || !response.ok) { $("pair-error").textContent = T.wrongCode; return; }
  state.token = (await response.json()).token;
  writeToken(state.token);
  history.replaceState(null, "", location.pathname);
  start();
});

function forget() {
  writeToken(null);
  state.token = null;
  state.connected = false;
  const socket = state.socket;
  state.socket = null;  // önce boşalt: onclose yeniden bağlanmasın
  if (socket) socket.close();
  setupPairing("");
}

// Canlı bağlantı

function connect() {
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  const socket = new WebSocket(`${scheme}://${location.host}/api/stream`);
  state.socket = socket;
  socket.onopen = () => socket.send(JSON.stringify({ type: "auth", token: state.token }));
  socket.onmessage = (event) => receive(JSON.parse(event.data));
  socket.onclose = (event) => {
    if (state.socket !== socket) return;
    state.connected = false;
    renderBar();
    if (event.code === 4401) { forget(); return; }
    setTimeout(() => { if (state.socket === socket && state.token) connect(); }, state.retry);
    state.retry = Math.min(state.retry * 2, 10000);
  };
}

function receive(message) {
  switch (message.type) {
    case "ready":
      state.connected = true; state.retry = 1000; renderBar();
      if (state.current) loadMore();
      break;
    case "sessions":
      state.sessions = message.sessions; renderList(); renderChatHead();
      break;
    case "transcript.changed":
      if (message.sessionId === state.current) loadMore();
      break;
    case "error":
      $("chat-error").textContent = T[message.code] || message.code;
      break;
  }
}

function renderBar() {
  $("bar").hidden = state.connected || !state.token;
  $("bar").textContent = T.offline;
  const session = currentSession();
  $("send").disabled = !state.connected || !session || !session.canSend;
  $("stop").disabled = $("send").disabled;
}

// Oturum listesi

function renderList() {
  const list = $("sessions");
  list.replaceChildren();
  for (const session of state.sessions) {
    const item = el("li");
    item.append(el("span", `dot ${session.status}`));
    const text = el("div", "text");
    text.append(el("div", "name", session.title));
    const line = session.status === "permission" || session.status === "question" ? session.detail : session.summary;
    if (line) text.append(el("div", "summary", line));
    item.append(text);
    const badge = session.status === "idle" && session.background > 0 ? T.background(session.background)
      : session.finishedUnseen && session.status === "idle" ? T.finished : T.status[session.status];
    item.append(el("span", `badge ${session.status}`, badge));
    item.addEventListener("click", () => { location.hash = `s=${encodeURIComponent(session.id)}`; });
    list.append(item);
  }
  $("empty").hidden = state.sessions.length > 0;
  $("empty").textContent = T.empty;
}

// Sohbet

function currentSession() { return state.sessions.find((s) => s.id === state.current); }

function renderChatHead() {
  const session = currentSession();
  if (!session) return;
  $("chat-title").textContent = session.title;
  $("chat-status").textContent = session.detail ? `${T.status[session.status]} · ${session.detail}` : T.status[session.status];
  $("stop").hidden = session.status !== "working";
  const todos = session.todos || [];
  $("todos").hidden = todos.length === 0;
  $("todos-summary").textContent = `${T.todos} (${todos.filter((t) => t.status === "done").length}/${todos.length})`;
  $("todo-list").replaceChildren(...todos.map((t) => el("li", t.status === "done" ? "done" : "", t.title)));
  renderBar();
}

function openChat(id) {
  state.current = id; state.cursor = null; state.seen = new Set();
  state.loading = null; state.pending = false;  // önceki oturumun isteği yenisini engellemesin
  $("messages").replaceChildren();
  $("chat-error").textContent = "";
  $("back").textContent = T.back; $("send").textContent = T.send; $("stop").textContent = T.stop;
  $("text").placeholder = T.placeholder;
  show("chat");
  renderChatHead();
  loadMore();
}

async function loadMore() {
  if (!state.current) return;
  const id = state.current;
  if (state.loading !== null && state.loadingId === id) { state.pending = true; return; }  // bitince tekrar çek
  const ticket = ++state.ticket;
  state.loading = ticket; state.loadingId = id;
  try {
    const query = state.cursor === null ? "" : `?after=${state.cursor}`;
    const page = await api(`/api/sessions/${encodeURIComponent(id)}/transcript${query}`);
    if (state.loading !== ticket || id !== state.current) return;
    const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
    for (const message of page.messages) {
      if (state.seen.has(message.id)) continue;
      state.seen.add(message.id);
      $("messages").append(el("li", message.role, message.text));
    }
    state.cursor = page.cursor;
    if (nearBottom || query === "") window.scrollTo(0, document.body.scrollHeight);
  } catch (error) {
    if (String(error.message) !== "404") $("chat-error").textContent = T.failed;
  } finally {
    if (state.loading === ticket) {
      state.loading = null;
      const again = state.pending && state.current === id;
      state.pending = false;
      if (again) loadMore();
    }
  }
}

$("back").addEventListener("click", () => { location.hash = ""; });

$("composer").addEventListener("submit", (event) => {
  event.preventDefault();
  const text = $("text").value.trim();
  if (!text || !state.connected || !state.current) return;
  state.socket.send(JSON.stringify({ type: "send.text", sessionId: state.current, text }));
  $("text").value = "";
  $("chat-error").textContent = "";
});

$("stop").addEventListener("click", () => {
  if (state.connected && state.current) state.socket.send(JSON.stringify({ type: "interrupt", sessionId: state.current }));
});

$("text").addEventListener("input", () => {
  $("text").style.height = "auto";
  $("text").style.height = `${$("text").scrollHeight}px`;
});

// Yönlendirme

function route() {
  const hash = location.hash.slice(1);
  if (hash.startsWith("pair=")) { setupPairing(decodeURIComponent(hash.slice(5))); return; }
  if (!state.token) { setupPairing(""); return; }
  if (hash.startsWith("s=")) { openChat(decodeURIComponent(hash.slice(2))); return; }
  state.current = null;
  show("list");
  renderList();
}

function start() {
  state.token = readToken();
  route();
  if (state.token && !state.socket) connect();
}

window.addEventListener("hashchange", route);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && state.token && !state.connected) {
    const socket = state.socket;
    state.socket = null;  // eski bağlantının onclose'u yeniden bağlanmasın
    if (socket) socket.close();
    connect();
  }
});
start();
