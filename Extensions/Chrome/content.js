// Agent Pulse: следит, генерирует ли Claude (или Figma Make) ответ, и сообщает только смену состояния.
// Текст переписки не читается и никуда не уходит — только состояние и id разговора.
"use strict";

const APP = location.hostname === "claude.ai" ? "claude" : "figmaMake";

// Признаки генерации. DOM меняется — поэтому несколько независимых признаков.
const GENERATING = {
  claude: ['button[aria-label="Stop response"]', 'button[aria-label="Остановить ответ"]', '[data-is-streaming="true"]'],
  figmaMake: ['button[aria-label*="Stop generat" i]', 'button[aria-label="Stop"]', 'button[aria-label*="Остановить" i]'],
}[APP];

// Кнопки одобрения инструмента в диалоге.
const APPROVAL_TEXT = /^(allow once|allow always|always allow|allow for this chat|разрешить)/i;

function sessionId() {
  const match = location.pathname.match(/\/(chat|make)\/([^/?#]+)/);
  return match ? `${APP}-${match[2]}` : `${APP}-tab`;
}

function approvalVisible() {
  for (const button of document.querySelectorAll('[role="dialog"] button, [role="alertdialog"] button, button')) {
    const text = (button.textContent || "").trim();
    if (text.length < 40 && APPROVAL_TEXT.test(text)) return true;
  }
  return false;
}

function currentState() {
  if (approvalVisible()) return "approval";
  return GENERATING.some((selector) => document.querySelector(selector)) ? "generating" : "idle";
}

let state = "idle";
let session = sessionId();
let scheduled = false;

function send(next, from) {
  try {
    chrome.runtime.sendMessage({ v: 1, app: APP, session, state: next, from });
  } catch {
    // Расширение перезагружено — страница доживает со старым контекстом. Молчим.
  }
}

function check() {
  scheduled = false;
  const id = sessionId();
  if (id !== session) {
    if (state !== "idle") send("idle", state);
    session = id;
    state = "idle";
  }
  const next = currentState();
  if (next === state) return;
  send(next, state);
  state = next;
}

// Мутаций во время стрима — сотни в секунду; проверяем не чаще раза в 100 ms.
new MutationObserver(() => {
  if (scheduled) return;
  scheduled = true;
  setTimeout(check, 100);
}).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["aria-label", "data-is-streaming"] });

// Подстраховка: в фоновой вкладке Chrome редко будит наблюдатель.
setInterval(check, 1000);

addEventListener("pagehide", () => send("closed", state));
check();
