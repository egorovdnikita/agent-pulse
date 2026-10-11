// Пересылает смену состояния в Agent Pulse через native messaging (pulse-hook → unix-сокет).
"use strict";

const HOST = "io.github.egorovdnikita.agentpulse";

chrome.runtime.onMessage.addListener((message) => {
  if (!message || message.v !== 1) return;
  chrome.runtime.sendNativeMessage(HOST, message, () => {
    // Приложение не запущено или мост не установлен — не мешаем странице.
    void chrome.runtime.lastError;
  });
});
