// Agent Pulse — плагин-компаньон Figma.
// 1. Замечает генерацию ИИ: всплеск созданных объектов, которого руками не сделать.
// 2. Зеркало: когда Agent Pulse говорит, что агент рисует в Figma, экспортирует изменённый фрейм в PNG.
// Плагин ничего не меняет в документе. Сеть — только localhost через скрытый UI.

const BURST_NODES = 12; // столько созданных объектов…
const BURST_WINDOW_MS = 1500; // …за такое время — это генерация
const QUIET_MS = 2500; // тишина после всплеска — генерация закончилась
const CHANGE_PING_MS = 1000; // спрашиваем про зеркало не чаще
const FRAME_DEBOUNCE_MS = 800; // кадр — после затихания изменений
const FRAME_MAX_WIDTH = 320;

figma.showUI(__html__, { visible: false });

const file = figma.root.name;
let createdAt = [];
let generating = false;
let quietTimer = null;
let frameTimer = null;
let lastPing = 0;
let mirrorWanted = false;
let lastTouched = null;

function send(payload) {
  figma.ui.postMessage(Object.assign({ v: 1, file }, payload));
}

function topFrame(node) {
  let current = node;
  while (current && current.parent && current.parent.type !== "PAGE") current = current.parent;
  return current && current.parent && current.parent.type === "PAGE" ? current : null;
}

function onNodeChange(event) {
  const now = Date.now();
  for (const change of event.nodeChanges) {
    if (change.type === "CREATE") createdAt.push(now);
    const node = change.node;
    if (node && !node.removed) {
      const top = topFrame(node);
      if (top) lastTouched = top.id;
    }
  }
  createdAt = createdAt.filter((t) => now - t < BURST_WINDOW_MS);

  if (!generating && createdAt.length >= BURST_NODES) {
    generating = true;
    send({ kind: "activity", state: "generating" });
  }
  if (generating) {
    clearTimeout(quietTimer);
    quietTimer = setTimeout(() => {
      generating = false;
      send({ kind: "activity", state: "idle" });
    }, QUIET_MS);
  }

  if (now - lastPing >= CHANGE_PING_MS) {
    lastPing = now;
    send({ kind: "change" });
  }
  if (mirrorWanted || generating) {
    clearTimeout(frameTimer);
    frameTimer = setTimeout(exportFrame, FRAME_DEBOUNCE_MS);
  }
}

async function exportFrame() {
  if (!lastTouched) return;
  const node = await figma.getNodeByIdAsync(lastTouched);
  if (!node || node.removed || !("exportAsync" in node)) return;
  const scale = Math.min(1, FRAME_MAX_WIDTH / Math.max(node.width, 1));
  try {
    const bytes = await node.exportAsync({ format: "PNG", constraint: { type: "SCALE", value: scale } });
    send({ kind: "frame", node: node.name, png: figma.base64Encode(bytes) });
  } catch (error) {
    // Экспорт не удался (например, пустой фрейм) — следующий кадр будет при следующем изменении.
  }
}

let watchedPage = null;
function watchCurrentPage() {
  if (watchedPage) watchedPage.off("nodechange", onNodeChange);
  watchedPage = figma.currentPage;
  watchedPage.on("nodechange", onNodeChange);
}

figma.ui.onmessage = (message) => {
  if (message && message.type === "mirror") mirrorWanted = Boolean(message.value);
};
figma.on("currentpagechange", watchCurrentPage);
figma.on("close", () => send({ kind: "closed" }));
watchCurrentPage();
figma.notify("Agent Pulse следит за макетом. Закройте плагин, чтобы остановить.", { timeout: 2500 });
