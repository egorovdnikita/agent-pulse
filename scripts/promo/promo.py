#!/usr/bin/env python3
"""Промо-ролик Agent Pulse для README: настоящие виды приложения, камера и клики.

    python3 scripts/promo/promo.py ПАПКА [--app путь/к/AgentPulse] [--only-compose]

1. Пишет ПАПКА/script.json — сценарий маскота (состояния, реакции, курсор).
2. Запускает приложение с `--promo-sheet ПАПКА`: настоящий аниматор на виртуальных часах рисует кадры
   маскота, облачка, капсулу и страницы Пульта (без окон на экране).
3. Монтирует ролик на фоне GitHub Dark: камера по кривой V4 (Telegram Motion Style),
   матовое кольцо клика, раскрытие Пульта как в приложении. Итог — ПАПКА/agent-pulse-demo.webp.

Нужны Pillow и imageio-ffmpeg. Никаких данных пользователя: рабочий стол нарисован, файлы и тексты вымышлены.
"""
import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

FPS = 60
W, H = 1280.0, 704.0            # экран в pt
OUT_W, OUT_H = 1600, 880        # кадр ролика
K = OUT_W / W                   # px на pt при общем плане
ASSET_SCALE = 4.0               # во сколько раз крупнее pt рисует приложение
DIAMETER = 48.0
BOX = DIAMETER * 2.2
OVERLAP = max(0.0, (BOX - DIAMETER) / 2 - 8)

MASCOT = (W - 16 - BOX / 2 + 8, H - 58.0)     # центр тела
CAPSULE_LEFT = 16.0
GAP = 8.0
MENU_HEIGHT = 0.0
PROMPTER_TOP = 16.0
PANEL_W, PANEL_H = 640.0, None                # высота — по картинке

# ---------- кривые ----------

def cubic_in_out(t):
    t = min(max(t, 0.0), 1.0)
    return 4 * t * t * t if t < .5 else 1 - (-2 * t + 2) ** 3 / 2


def cubic_out(t):
    t = min(max(t, 0.0), 1.0)
    return 1 - (1 - t) ** 3


def ease_out(t):
    t = min(max(t, 0.0), 1.0)
    return 1 - (1 - t) ** 2


def camera_progress(elapsed, duration=.75):
    """Одобренная камера V4: основной ход ~0.4 s, один перелёт ~1.3%, покой к 0.75 s."""
    if elapsed <= 0:
        return 0.0
    if elapsed >= duration:
        return 1.0
    t = elapsed / duration * .75
    value = 1 - math.exp(-11 * t) * (math.cos(8 * t) + (11 / 8) * math.sin(8 * t))
    blend = cubic_in_out((t - .60) / .15)
    return value * (1 - blend) + blend


def tap_state(rel):
    """Кольцо касания V4: радиус / максимум, прозрачность, отверстие / радиус."""
    hole = .58
    if rel < -.37 or rel > .28:
        return 0.0, 0.0, hole
    if rel < -.17:
        p = (rel + .37) / .20
        return .45 + .55 * cubic_out(p), cubic_in_out(p / .6), hole
    if rel < 0:
        p = (rel + .17) / .17
        return 1 - .5 * cubic_in_out(p), 1.0, hole
    p = rel / .28
    return .5 + .24 * cubic_out(p), 1 - cubic_in_out(p), hole + .2 * cubic_in_out(p)


def spring(t, response, damping):
    """SwiftUI .spring(response:dampingFraction:) из покоя к 1."""
    if t <= 0:
        return 0.0
    w0 = 2 * math.pi / response
    if damping >= 1:
        return 1 - (1 + w0 * t) * math.exp(-w0 * t)
    wd = w0 * math.sqrt(1 - damping ** 2)
    return 1 - math.exp(-damping * w0 * t) * (math.cos(wd * t) + damping * w0 / wd * math.sin(wd * t))

# ---------- сценарий ----------

BUBBLES = [
    {"id": "think", "category": "claude", "title": "Claude Code", "text": "Думаю…"},
    {"id": "edit", "category": "claude", "title": "Claude Code", "text": "Пишу…"},
    {"id": "permission", "category": "claude", "title": "Claude Code", "text": "Можно?"},
    {"id": "done", "category": "claude", "title": "Claude Code", "text": "Готово, проверь"},
]

# Позы камеры: видимая область экрана (левый верхний угол и ширина, pt).
def view_wide():
    return (0.0, 0.0, W)


def view_corner(width, right=None, left=None, bottom_margin=0.0):
    h = width * H / W
    x = (W - width) if right is not None else 0.0
    return (x, H - h + bottom_margin, width)


CAM_WIDE = view_wide()
CAM_MASCOT = view_corner(500, right=True)
CAM_CONSOLE = view_corner(720, left=True, bottom_margin=14)


class Timeline:
    def __init__(self):
        self.states = []          # (t, имя)
        self.reactions = []       # (t, имя)
        self.bubbles = []         # (t_in, t_out, id)
        self.camera = [(0.0, CAM_WIDE)]   # (t начала хода, поза)
        self.cursor = []          # (t, x, y) опорные точки, между ними — плавный ход
        self.clicks = []          # t касания
        self.hover = []
        self.panel = []           # (t, событие, аргумент)
        self.duration = 0.0
        self.prompter = (31.05, 39.05)
        self.pause = (36.0, 37.0)


SPEECH = "Привет! Сегодня покажу Пульт.\n\nЛимиты нейросетей всегда под рукой. Файлы можно сохранить на полке, а текст — быстро перевести.\n\nВсё работает прямо на этом Mac."
SOURCE = "Маскот показывает, что агент ждёт тебя."


def build_timeline(assets, geometry):
    tl = Timeline()
    tl.states = [(0, "idle"), (1.8, "think"), (3.5, "edit"), (5.1, "permission"), (7.1, "edit"), (8.5, "idle")]
    tl.bubbles = [(1.9, 3.4, "think"), (3.6, 5, "edit"), (5.2, 7, "permission"), (8.5, 10.4, "done")]
    tl.reactions = [(8.5, "done")]
    tl.camera += [(0.6, CAM_MASCOT), (10.3, CAM_WIDE), (11.3, CAM_CONSOLE)]
    tl.cursor = [(0, 800, 400)]
    capsule, panel = geometry
    px, py = panel[:2]

    def click(t, xy, label, rect=None):
        if rect:
            x, y, w, h = rect
            assert x <= xy[0] <= x+w and y <= xy[1] <= y+h, label
        tl.clicks.append({"t": t, "x": xy[0], "y": xy[1], "target": label, "rect": rect})
        tl.cursor.extend([(t - .25, *xy), (t + .25, *xy)])
    def hit(t, state, target):
        rect = assets.target(state, target)
        rect = [px + rect[0], py + rect[1], *rect[2:]]
        click(t, (rect[0]+rect[2]/2, rect[1]+rect[3]/2), target, rect)
    def top_hit(t, target):
        rect = assets.target("prompter/0000", target)
        rect = [(W-560)/2 + rect[0], PROMPTER_TOP + rect[1], *rect[2:]]
        click(t, (rect[0]+rect[2]/2, rect[1]+rect[3]/2), target, rect)
    def capsule_hit(t):
        variant="empty" if t<14.1 else "claude" if t<15.3 else "filled"
        x,y,w,h=assets.target("capsule-"+variant,"capsule")
        rect=[capsule[0]+x,capsule[1]+y,w,h]
        click(t,(rect[0]+w/2,rect[1]+h/2),"capsule",rect)
    def page(t, name): tl.panel.append((t, "tab", name))
    def tab(t, old, name, state):
        hit(t, old, "tab-"+name); page(t + .02, state)
    def type_text(start, duration, text, prefix):
        for i in range(1, len(text)+1): page(start + duration*i/len(text), f"{prefix}-type-{i}")

    click(6.8, MASCOT, "mascot")
    capsule_hit(12.2); tl.panel.append((12.22, "open", "limits-empty"))
    hit(13.8, "limits-empty", "connect-claude"); page(14.1, "limits-claude")
    hit(15.0, "limits-claude", "connect-codex"); page(15.3, "limits")
    tab(17, "limits", "shelf", "shelf-empty")
    page(18.7, "shelf-drop")
    tl.drag = (18.2, 19.52, (px+730,py-40), (px+310,py+130))
    page(19.52, "shelf-one")
    hit(20.8, "shelf-one", "shelf-Добавить"); page(21.25, "shelf")
    hit(22.3, "shelf", "file-Доклад.pdf"); page(22.32, "shelf-selected-one")
    hit(23.1, "shelf-selected-one", "file-Заметки.md"); page(23.12, "shelf-selected")
    hit(24.0, "shelf-selected", "shelf-Убрать"); page(24.02, "shelf-remaining")
    hit(25.0, "shelf-remaining", "shelf-Очистить"); page(25.02, "shelf-cleared")
    tab(26.2, "shelf-cleared", "prompter", "prompter-empty")
    hit(26.85, "prompter-empty", "prompter-editor")
    type_text(27.1, 2.0, SPEECH, "prompter"); page(29.15, "prompter")
    hit(30.0, "prompter", "prompter-+"); page(30.02, "prompter-speed")
    hit(31.0, "prompter-speed", "prompter-Старт")
    tl.panel.append((31.02, "close", None))
    tl.camera += [(31.1, CAM_WIDE), (33, ((W-720)/2, 0, 720))]
    top_hit(36, "top-pause"); top_hit(37, "top-pause"); top_hit(39, "top-stop")
    tl.camera += [(39.5, CAM_CONSOLE)]
    capsule_hit(41.3); tl.panel.append((41.32, "open", "prompter-speed"))
    tab(42.2, "prompter-speed", "translate", "translate-empty")
    hit(42.9, "translate-empty", "translate-editor")
    type_text(43.1, 1.1, SOURCE, "translate")
    page(44.5, "translate-working"); page(45.2, "translate")
    hit(47, "translate", "translate-Скопировать"); page(47.02, "translate-copied")
    hit(48.7, "translate-copied", "translate-Очистить"); page(48.72, "translate-cleared")
    hit(49.2, "translate-cleared", "translate-swap"); page(49.22, "translate-reversed-empty")
    click(50, (830, 170), "outside"); tl.panel.append((50.02, "close", None))
    tl.camera.append((50.6, CAM_WIDE)); tl.duration = 52.5
    return tl


def prompter_frame(tl, t):
    start,end = tl.prompter
    a,b = tl.pause
    return {"elapsed": max(0,t-start-max(0,min(t,b)-a)), "paused": a <= t < b}


def cursor_at(tl, t):
    pts = tl.cursor
    if t <= pts[0][0]:
        return pts[0][1:]
    for (t0, x0, y0), (t1, x1, y1) in zip(pts, pts[1:]):
        if t0 <= t <= t1:
            p = cubic_in_out((t - t0) / max(t1 - t0, 1e-6))
            # Лёгкая дуга, как у руки: курсор не ходит по линейке.
            bow = math.sin(math.pi * p) * min(40.0, math.hypot(x1 - x0, y1 - y0) * .08)
            nx, ny = -(y1 - y0), (x1 - x0)
            n = math.hypot(nx, ny) or 1
            return x0 + (x1 - x0) * p + nx / n * bow, y0 + (y1 - y0) * p + ny / n * bow
    return pts[-1][1:]


def write_script(folder, tl, assets_only=False):
    frames = int(round(tl.duration * FPS))
    cursor = []
    for i in range(frames):
        x, y = cursor_at(tl, i / FPS)
        cursor.append([x - MASCOT[0], y - MASCOT[1]])
    script = {
        "assetsOnly": assets_only,
        "fps": FPS, "duration": tl.duration, "diameter": DIAMETER, "scale": ASSET_SCALE,
        "states": [{"t": t, "state": n} for t, n in tl.states],
        "reactions": [{"t": t, "name": n} for t, n in tl.reactions],
        "hover": [list(h) for h in tl.hover],
        "cursor": cursor,
        "bubbles": BUBBLES,
        "prompterFrames": [prompter_frame(tl, tl.prompter[0] + i/FPS)
                           for i in range(round((tl.prompter[1]-tl.prompter[0])*FPS))],
    }
    (folder / "script.json").write_text(json.dumps(script, ensure_ascii=False))

# ---------- монтаж ----------

def wallpaper(width, height):
    """GitHub Dark: --bgColor-default, измерено на странице профиля."""
    return Image.new("RGB", (width, height), "#0d1117")


class PanelAssets:
    def __init__(self, folder):
        self.folder = folder
        self.cache = {}

    def __getitem__(self, name):
        if name not in self.cache:
            if len(self.cache) >= 6:
                self.cache.pop(next(iter(self.cache)))
            self.cache[name] = Image.open(self.folder / f"panel-{name}.png").convert("RGBA")
        return self.cache[name]


class Assets:
    def __init__(self, folder):
        self.folder = folder
        self.bubbles = {b["id"]: Image.open(folder / f"bubble-{b['id']}.png").convert("RGBA") for b in BUBBLES}
        self.capsule = Image.open(folder / "capsule.png").convert("RGBA")
        self.panels = PanelAssets(folder)
        self.target_cache = {}
        self.menu = Image.open(folder / "menu-bar.png").convert("RGBA") if (folder / "menu-bar.png").exists() else None

        self.mascot_dir = folder / "mascot"
        self.dock = Image.open(folder / "dock.png").convert("RGBA") if (folder / "dock.png").exists() else None
        dock_spec = json.loads((folder / "dock.json").read_text()) if self.dock else {}
        self.dock_screen_width = dock_spec.get("screen_width")
        if self.dock and dock_spec.get("remove_ranges"):
            # Монтаж Dock: исходные пиксели остаются без изменений, исключается только лишняя секция.
            segments, last = [], 0
            for left,right in dock_spec["remove_ranges"]:
                assert 0 <= last <= left < right <= self.dock.width
                segments.append(self.dock.crop((last,0,left,self.dock.height))); last=right
            segments.append(self.dock.crop((last,0,self.dock.width,self.dock.height)))
            dock = Image.new("RGBA", (sum(p.width for p in segments), self.dock.height))
            x=0
            for part in segments: dock.paste(part,(x,0)); x+=part.width
            self.dock = dock
        # Запас по краям: на перелёте камеры видно чуть больше экрана.
        self.margin = 80.0
        self.wall = wallpaper(int((W + 2 * self.margin) * 2), int((H + 2 * self.margin) * 2))

    def target(self, state, name):
        key = state if "/" in state or state.startswith("capsule-") else "panel-"+state
        if key not in self.target_cache:
            self.target_cache[key] = json.loads((self.folder / (key+".targets.json")).read_text())
        if name not in self.target_cache[key]:
            raise ValueError(f"Нет измеренной кнопки {name} в {key}")
        return self.target_cache[key][name]

    def mascot(self, index):
        path = self.mascot_dir / f"{index:04d}.png"
        return Image.open(path).convert("RGBA")


def configure_stage(assets):
    global MASCOT, CAM_CONSOLE, MENU_HEIGHT, PROMPTER_TOP
    CAM_CONSOLE=(CAPSULE_LEFT + PANEL_W/2 - 720/2, CAM_CONSOLE[1],720)
    if assets.menu:
        MENU_HEIGHT=assets.menu.height*W/assets.menu.width
        PROMPTER_TOP=MENU_HEIGHT+6
    if assets.dock:
        x=assets.dock.width//2
        rows=[y for y in range(assets.dock.height) if assets.dock.getpixel((x,y))[3]>220]
        scale=W/(2*assets.dock_screen_width)
        center=H-assets.dock.height*scale+(min(rows)+max(rows))/2*scale
        MASCOT=(MASCOT[0],center)
        # Облачко и Dock не пересекаются даже у самой длинной реплики.
        right=(W+assets.dock.width*scale)/2
        bubble_left=min(MASCOT[0]-BOX/2+OVERLAP+12-b.width/ASSET_SCALE for b in assets.bubbles.values())
        assert right+12 <= bubble_left, (right,bubble_left)


def capsule_geometry(assets):
    """Капсула и панель в pt. Картинки отрисованы с полем 8 pt."""
    cw = assets.capsule.width / ASSET_SCALE - 16
    ch = assets.capsule.height / ASSET_SCALE - 16
    cy = MASCOT[1]
    capsule = (CAPSULE_LEFT, cy - ch / 2, cw, ch)
    ph = assets.panels["limits"].height / ASSET_SCALE - 16
    gap = GAP
    if assets.dock:
        dock_top = H - assets.dock.height * W / (2 * assets.dock_screen_width)
        gap = max(gap, capsule[1] - dock_top + 16)
    panel = (CAPSULE_LEFT, capsule[1] - gap - ph, PANEL_W, ph)
    return capsule, panel


def camera_at(tl, t):
    current = tl.camera[0][1]
    for start, pose in tl.camera[1:]:
        if t < start:
            break
        p = camera_progress(t - start)
        current = tuple(a + (b - a) * p for a, b in zip(current, pose))
    return current


class Frame:
    """Холст кадра и перевод pt → px по текущей камере."""

    def __init__(self, view):
        self.x0, self.y0, width = view
        self.k = OUT_W / width
        self.img = Image.new("RGBA", (OUT_W, OUT_H))

    def px(self, x, y):
        return (x - self.x0) * self.k, (y - self.y0) * self.k

    def paste(self, sprite, x, y, scale_pt=1.0, alpha=1.0, anchor=(0, 0)):
        """Положить картинку, нарисованную с ASSET_SCALE, левым верхним углом (с учётом anchor) в pt."""
        if sprite is None or alpha <= 0.003:
            return
        w = sprite.width / ASSET_SCALE * scale_pt
        h = sprite.height / ASSET_SCALE * scale_pt
        left, top = x - anchor[0] * w, y - anchor[1] * h
        pl, pt_ = self.px(left, top)
        pw, ph = max(1, round(w * self.k)), max(1, round(h * self.k))
        if pl > OUT_W or pt_ > OUT_H or pl + pw < 0 or pt_ + ph < 0:
            return
        img = sprite.resize((pw, ph), Image.LANCZOS)
        if alpha < 1:
            a = img.getchannel("A").point(lambda v: int(v * alpha))
            img.putalpha(a)
        self.img.alpha_composite(img, (round(pl), round(pt_))) if pl >= 0 and pt_ >= 0 else self._paste_clipped(img, round(pl), round(pt_))

    def _paste_clipped(self, img, x, y):
        cx, cy = max(0, -x), max(0, -y)
        if cx >= img.width or cy >= img.height or x >= OUT_W or y >= OUT_H:
            return
        img = img.crop((cx, cy, img.width, img.height))
        self.img.alpha_composite(img, (x + cx, y + cy))


def draw_background(frame, assets):
    frame.img.paste((13,17,23,255), (0,0,OUT_W,OUT_H))
    if assets.menu:
        frame.paste(assets.menu,0,0,scale_pt=ASSET_SCALE*W/assets.menu.width)


def draw_dock(frame, assets):
    if assets.dock:
        # Захват Dock с Retina 2x, размер относительно реального экрана сохраняется.
        frame.paste(assets.dock, W / 2, H, scale_pt=ASSET_SCALE * W / (2 * assets.dock_screen_width), anchor=(.5, 1))


def bubble_state(tl, t):
    for t_in, t_out, name in tl.bubbles:
        if t_in <= t < t_out + 0.2:
            if t < t_out:
                p = spring(t - t_in, .18, 1.0)
                return name, .6 + .4 * p, min(1.0, p * 1.4)
            return name, 1.0, 1 - ease_out((t - t_out) / .2)
    return None


def draw_mascot(frame, assets, tl, t, index):
    sprite = assets.mascot(index)
    reset = ease_out((t - (tl.duration - .4)) / .35)
    if reset > 0: sprite = Image.blend(sprite, assets.mascot(0), reset)
    frame.paste(sprite, MASCOT[0], MASCOT[1], anchor=(.5, .5))
    state = bubble_state(tl, t)
    if state:
        name, scale, alpha = state
        bubble = assets.bubbles[name]
        # Хвостик облачка заходит на холст маскота (как в PillView); картинка облачка — с полем 12 pt.
        tail = MASCOT[0] - BOX / 2 + OVERLAP
        bw, bh = bubble.width / ASSET_SCALE, bubble.height / ASSET_SCALE
        # Появление от хвостика: правый край и середина высоты на месте.
        right = tail + 12 * scale
        frame.paste(bubble, right - bw * scale, MASCOT[1] - bh * scale / 2, scale_pt=scale, alpha=alpha)


def panel_state(tl, t):
    """(открытость 0…1 по пружине, видимость содержимого, текущая вкладка, прошлая вкладка, время смены)."""
    open_t = close_t = None
    tab, prev, change = "limits", None, -10.0
    for when, kind, arg in tl.panel:
        if when > t:
            break
        if kind == "open":
            open_t, close_t, tab = when, None, arg
            prev, change = None, -10
        elif kind == "tab":
            prev, tab, change = tab, arg, when
        elif kind == "close":
            close_t = when
    if open_t is None:
        return 0.0, 0.0, tab, prev, change
    if close_t is None:
        openness = spring(t - open_t, .42, .8)
        content = ease_out((t - open_t - .06) / .22)
    else:
        openness = 1 - spring(t - close_t, .45, 1.0)
        content = 1 - min(1.0, (t - close_t) / .1) ** 2
    return openness, content, tab, prev, change


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def capsule_surface(content):
    """Единственный контур: родной фон/обводка не участвуют в монтаже."""
    width,height=content.size
    body=Image.new("RGBA",content.size,(10,10,10,255))
    body.alpha_composite(capsule_content(content))
    mask=rounded_mask(body.size,height/2)
    body.putalpha(mask)
    edge=Image.new("RGBA",body.size)
    ImageDraw.Draw(edge).rounded_rectangle((0,0,width-1,height-1),radius=(height-1)/2,
                                          outline=(255,255,255,18),width=round(ASSET_SCALE))
    body.alpha_composite(edge)
    return body


def capsule_content(img):
    out = img.copy()
    mask = Image.new("L",out.size)
    inset = round(2.5*ASSET_SCALE)
    ImageDraw.Draw(mask).rounded_rectangle((inset,inset,out.width-inset-1,out.height-inset-1), radius=out.height/2-inset,fill=255)
    out.putalpha(ImageChops.multiply(out.getchannel("A"),mask))
    return out


def capsule_image(assets, tl, t):
    if t >= tl.duration - .45:
        old = crop_panel(Image.open(assets.folder / "capsule-filled.png").convert("RGBA"))
        new = crop_panel(Image.open(assets.folder / "capsule-empty.png").convert("RGBA"))
        dt = t - (tl.duration - .45)
        if dt >= .4:
            return Image.open(assets.folder / "capsule-empty.png").convert("RGBA")
        p = cubic_in_out(dt / .4)
        width = round(old.width + (new.width - old.width) * p)
        height = old.height
        body = Image.new("RGBA", (width, height), (10,10,10,255))
        for src, alpha in [(capsule_content(old), 1-ease_out(dt/.16)), (capsule_content(new), ease_out((dt-.18)/.18))]:
            src.putalpha(src.getchannel("A").point(lambda v: round(v*alpha)))
            body.alpha_composite(src, (0,0))
        body=capsule_surface(body)
        pad=round(8*ASSET_SCALE)
        out=Image.new("RGBA",(width+2*pad,height+2*pad));out.alpha_composite(body,(pad,pad))
        return out
    start,end=tl.prompter
    if start <= t < end:
        index=min(round((end-start)*FPS)-1, max(0,int((t-start)*FPS)))
        return Image.open(assets.folder / "prompter" / f"capsule-{index//FPS:02d}.png").convert("RGBA")
    for service,start,previous in [("claude",14.1,"empty"),("codex",15.3,"claude")]:
        dt=t-start
        if 0<=dt<1:
            current=Image.open(assets.folder/f"capsule-reveal-{service}-{min(60,round(dt*FPS))}.png").convert("RGBA")
            if dt>=.6:return current
            old=Image.open(assets.folder/f"capsule-{previous}.png").convert("RGBA")
            a,b=capsule_content(crop_panel(old)),capsule_content(crop_panel(current))
            p=spring(dt,.42,.8)
            width=max(1,round(a.width+(b.width-a.width)*p));height=b.height
            body=Image.new("RGBA",(width,height),(10,10,10,255))
            a.putalpha(a.getchannel("A").point(lambda v:round(v*(1-ease_out(dt/.12)))))
            b.putalpha(b.getchannel("A").point(lambda v:round(v*ease_out(dt/.18))))
            body.alpha_composite(a,(0,0));body.alpha_composite(b,(0,0))
            body=capsule_surface(body)
            pad=round(8*ASSET_SCALE);out=Image.new("RGBA",(width+2*pad,height+2*pad))
            out.alpha_composite(body,(pad,pad));return out
    name="empty" if t<14.1 else "claude" if t<15.3 else "filled"
    return Image.open(assets.folder / f"capsule-{name}.png").convert("RGBA")


def draw_console(frame, assets, tl, t, geometry):
    capsule, panel = geometry
    cx, cy, cw, ch = capsule
    openness, content, tab, prev, change = panel_state(tl, t)
    cap = capsule_image(assets,tl,t)
    cw,ch = cap.width/ASSET_SCALE-16,cap.height/ASSET_SCALE-16
    if openness <= 0.001:
        frame.paste(cap, cx - 8, cy - 8)
        return
    px_, py_, pw, ph = panel
    # Форма сначала поднимается выше Dock, затем раскрывается в ширину; левый край фиксирован.
    o = openness
    width = cw + (pw - cw) * o
    height = ch + (ph - ch) * o
    radius = ch / 2 + (24 - ch / 2) * min(1.0, max(0.0, o))
    bottom = cy + ch + (py_ + ph - (cy + ch)) * ease_out(o / .1)
    left = px_
    top = bottom - height
    l, tp = frame.px(left, top)
    wpx, hpx = max(1, round(width * frame.k)), max(1, round(height * frame.k))
    shape = Image.new("RGBA", (wpx, hpx), (10, 10, 10, 255))
    mask = rounded_mask((wpx, hpx), radius * frame.k)
    # Содержимое стоит на месте, форма его обрезает.
    if content > 0:
        page = page_image(assets, tab, prev, change, t)
        full_w, full_h = round(pw * frame.k), round(ph * frame.k)
        page = page.resize((full_w, full_h), Image.LANCZOS)
        if content < 1:
            page.putalpha(page.getchannel("A").point(lambda v: int(v * content)))
        # Панель картинки прижата к низу формы при открытой панели.
        offset_y = round((py_ - top) * frame.k)
        shape.alpha_composite(page, (0, offset_y)) if offset_y >= 0 else shape.alpha_composite(page.crop((0, -offset_y, full_w, full_h)), (0, 0))
    shape.putalpha(ImageChops.multiply(shape.getchannel("A"), mask))
    if abs(openness-1)>.005:
        edge=Image.new("RGBA",shape.size)
        ImageDraw.Draw(edge).rounded_rectangle((.5,.5,wpx-1,hpx-1),radius=radius*frame.k,
            outline=(255,255,255,18),width=max(1,round(frame.k)))
        shape.alpha_composite(edge)
    closing = next((when for when,kind,arg in reversed(tl.panel) if when <= t and kind in ("open","close")), None)
    if closing is not None and any(when == closing and kind == "close" for when,kind,arg in tl.panel):
        opacity = 1-ease_out((t-closing)/.18)
        shape.putalpha(shape.getchannel("A").point(lambda v:round(v*opacity)))
    frame._paste_clipped(shape, round(l), round(tp)) if l < 0 or tp < 0 else frame.img.alpha_composite(shape, (round(l), round(tp)))
    # Капсула в приложении лежит поверх формы (VStack: панель, затем капсула).
    frame.paste(cap, cx - 8, cy - 8)


def crop_panel(img):
    m = round(8 * ASSET_SCALE)
    return img.crop((m, m, img.width - m, img.height - m))


def file_rectangles(assets, state):
    key="panel-"+state
    if key not in assets.target_cache:
        assets.target(state,"tab-shelf")
    return {k:v for k,v in assets.target_cache[key].items() if k.startswith("file-")}


def crop_rect(img, rect):
    x,y,w,h=rect
    return img.crop(tuple(round(v*ASSET_SCALE) for v in (x,y,x+w,y+h)))


def shelf_transition(assets, tab, prev, dt):
    current=crop_panel(assets.panels[tab]);old=crop_panel(assets.panels[prev])
    before,after=file_rectangles(assets,prev),file_rectangles(assets,tab)
    def base(img,rects):
        out=img.copy();draw=ImageDraw.Draw(out)
        for x,y,w,h in rects.values():
            draw.rectangle(tuple(round(v*ASSET_SCALE) for v in (x,y,x+w,y+h)),fill=(10,10,10,255))
        return out
    a,b=base(old,before),base(current,after)
    mix=ease_out(dt/.22)
    out=Image.blend(a,b,mix)
    # Подписи подвала меняются последовательно, без двойного текста.
    band = (round(10*ASSET_SCALE), round(192*ASSET_SCALE), round(630*ASSET_SCALE), round(234*ASSET_SCALE))
    ImageDraw.Draw(out).rectangle(band, fill=(10,10,10,255))
    footer = (a if dt < .1 else b).crop(band)
    opacity = 1-ease_out(dt/.1) if dt < .1 else ease_out((dt-.1)/.12)
    footer.putalpha(footer.getchannel("A").point(lambda v:round(v*opacity)))
    out.alpha_composite(footer, band[:2])
    incoming=sorted(set(after)-set(before),key=lambda k:after[k][0])
    outgoing=sorted(set(before)-set(after),key=lambda k:before[k][0])
    for name,rect in before.items():
        if name in after: continue
        rel=max(0,dt-outgoing.index(name)*.045)
        p=ease_out(rel/.24);tile=crop_rect(old,rect)
        size=1-.18*p; x,y,w,h=rect
        sw,sh=round(tile.width*size),round(tile.height*size)
        tile=tile.resize((max(1,sw),max(1,sh)),Image.LANCZOS)
        tile.putalpha(tile.getchannel("A").point(lambda v:round(v*(1-p))))
        out.alpha_composite(tile,(round((x+w/2)*ASSET_SCALE-sw/2),round((y-12*p)*ASSET_SCALE)))
    for name,rect in after.items():
        tile=crop_rect(current,rect);x,y,w,h=rect
        if name in before:
            ox,oy,ow,oh=before[name]
            p=spring(dt,.4,.85)
            x,y=ox+(x-ox)*p,oy+(y-oy)*p
            tile=Image.blend(crop_rect(old,before[name]).resize(tile.size,Image.LANCZOS),tile,ease_out(dt/.16))
            size,alpha=1,1
        else:
            rel=max(0,dt-(.16 if before else 0)-incoming.index(name)*.06)
            p=spring(rel,.38,.82);alpha=ease_out(rel/.18);size=.88+.12*p
            if name=="file-Доклад.pdf" and prev=="shelf-drop":
                alpha,size=1,1
                x=(310-w/2)+(x-(310-w/2))*p
                y=(130-h/2)+(y-(130-h/2))*p
            else: y+=16*(1-p)
        sw,sh=max(1,round(tile.width*size)),max(1,round(tile.height*size))
        tile=tile.resize((sw,sh),Image.LANCZOS)
        tile.putalpha(tile.getchannel("A").point(lambda v:round(v*alpha)))
        out.alpha_composite(tile,(round((x+w/2)*ASSET_SCALE-sw/2),round(y*ASSET_SCALE)))
    return out


def page_image(assets, tab, prev, change, t):
    """Смена страницы: новая выходит с 24 pt и проявляется за 0.24 s, старая гаснет за 0.08 s."""
    dt = t - change
    if tab=="limits-claude" and 0<=t-14.1<1:
        return crop_panel(assets.panels[f"limits-reveal-claude-{min(60,round((t-14.1)*FPS))}"])
    if tab=="limits" and 0<=t-15.3<1:
        return crop_panel(assets.panels[f"limits-reveal-codex-{min(60,round((t-15.3)*FPS))}"])
    if prev and (tab.startswith("shelf-") or tab=="shelf"):
        if prev and prev.startswith("shelf") and 0<=dt<.65:
            return shelf_transition(assets,tab,prev,dt)
    current = crop_panel(assets.panels[tab])
    if prev is None or dt >= .24:
        return current
    order = ["limits", "prompter", "shelf", "translate"]
    direction = 1 if order.index(tab.split("-")[0]) > order.index(prev.split("-")[0]) else -1
    if tab.split("-")[0] == prev.split("-")[0]:
        if "-type-" in tab or "-type-" in prev:
            return current
        old = crop_panel(assets.panels[prev])
        return Image.blend(old, current, ease_out(dt/.18))
    old = crop_panel(assets.panels[prev])
    p = ease_out(dt / .24)
    out = Image.new("RGBA", current.size, (10, 10, 10, 255))
    # Вкладки сверху не двигаются: двигается только страница под ними.
    head = round(42 * ASSET_SCALE)
    out.alpha_composite(current.crop((0, 0, current.width, head)), (0, 0))
    fade_old = max(0.0, 1 - dt / .08)
    if fade_old > 0:
        body = old.crop((0, head, old.width, old.height))
        body.putalpha(body.getchannel("A").point(lambda v: int(v * fade_old)))
        out.alpha_composite(body, (0, head))
    body = current.crop((0, head, current.width, current.height))
    body.putalpha(body.getchannel("A").point(lambda v: int(v * p)))
    shift = round(direction * 24 * (1 - p) * ASSET_SCALE)
    canvas = Image.new("RGBA", body.size)
    canvas.alpha_composite(body, (max(0, shift), 0)) if shift >= 0 else canvas.alpha_composite(body.crop((-shift, 0, body.width, body.height)), (0, 0))
    out.alpha_composite(canvas, (0, head))
    return out


def draw_ring(frame, x, y, rel, radius_pt=18):
    radius_share, alpha, hole = tap_state(rel)
    if alpha <= 0.01:
        return
    r = radius_pt * frame.k * radius_share
    pad = int(r + 12)
    cx, cy = frame.px(x, y)
    box = (int(cx - pad), int(cy - pad), int(cx + pad), int(cy + pad))
    sample = frame.img.crop(box).filter(ImageFilter.GaussianBlur(max(2, r * .16)))
    light = sum(sample.convert("L").resize((1, 1), Image.BOX).getpixel((0, 0)) for _ in [0]) > 170
    tint = Image.new("RGBA", sample.size, (120, 126, 140, 255) if light else (234, 241, 250, 255))
    glass = Image.blend(sample, tint, .45 if light else .28)
    size = sample.size
    sup = 4
    mask = Image.new("L", (size[0] * sup, size[1] * sup), 0)
    d = ImageDraw.Draw(mask)
    ox, oy = (cx - box[0]) * sup, (cy - box[1]) * sup
    d.ellipse((ox - r * sup, oy - r * sup, ox + r * sup, oy + r * sup), fill=int(235 * alpha))
    ri = r * hole
    d.ellipse((ox - ri * sup, oy - ri * sup, ox + ri * sup, oy + ri * sup), fill=0)
    mask = mask.resize(size, Image.LANCZOS)
    # Мягкая тень держит кольцо на светлом.
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(r * .12 + 2)).point(lambda v: int(v * .3)))
    frame.img.alpha_composite(shadow, (box[0], box[1] + max(1, int(r * .05))))
    glass.putalpha(mask)
    frame.img.alpha_composite(glass, (box[0], box[1]))


def draw_drag(frame, assets, tl, t, geometry):
    start, end, source, target = tl.drag
    if not start <= t < end:
        return
    p = cubic_in_out((t - start) / (end - start))
    x, y = (a + (b - a) * p for a, b in zip(source, target))
    # Настоящая плитка PDF из Библиотеки, без выдуманного интерфейса.
    tile=crop_rect(crop_panel(assets.panels["shelf-one"]),assets.target("shelf-one","file-Доклад.pdf"))
    frame.paste(tile, x, y, anchor=(.5, .5), alpha=min(1, (t-start)/.15))


def draw_library(frame, assets, tl, t, geometry):
    openness,content,tab,prev,change=panel_state(tl,t)
    empty={"shelf-empty","shelf-drop","shelf-cleared"}
    alpha,shift=content,0
    state=tab
    dt=t-change
    if tab not in empty:
        if prev not in empty or dt>=.22: return
        state=prev;alpha*=1-ease_out(dt/.22)
    elif prev and not prev.startswith("shelf") and dt<.24:
        alpha*=ease_out(dt/.24);shift=24*(1-ease_out(dt/.24))
    elif prev and prev.startswith("shelf") and prev not in empty:
        alpha*=ease_out((dt-.1)/.22)
    if content<=0 or openness<.98 or alpha<=0: return
    x,y,w,h=assets.target(state,"library-character");px,py=geometry[1][:2]
    index=int(t*FPS)%(2*FPS)
    sprite=Image.open(assets.folder/"library"/f"{index:04d}.png").convert("RGBA")
    frame.paste(sprite,px+x+w/2+shift,py+y+h/2,anchor=(.5,.5),alpha=alpha)


def draw_prompter(frame, assets, tl, t):
    start,end=tl.prompter
    if not start <= t < end+.24: return
    index=min(round((end-start)*FPS)-1,max(0,int((t-start)*FPS)))
    sprite=Image.open(assets.folder/"prompter"/f"{index:04d}.png").convert("RGBA")
    # Поле 8 pt снято с настоящего вида; форма раскрывается сверху по центру.
    sprite=crop_panel(sprite)
    p=spring(t-start,.42,.8) if t<end else 1-ease_out((t-end)/.24)
    width=180+(560-180)*p; height=32+(148-32)*p
    w,h=max(1,round(width*ASSET_SCALE)),max(1,round(height*ASSET_SCALE))
    shape=Image.new("RGBA",(w,h),(0,0,0,255))
    content=ease_out((t-start-.06)/.22) if t<end else 1-ease_out((t-end)/.15)
    sprite.putalpha(sprite.getchannel("A").point(lambda a:round(a*content)))
    shape.alpha_composite(sprite,(round((w-sprite.width)/2),0))
    shape.putalpha(rounded_mask((w,h),20*ASSET_SCALE))
    if abs(p-1)>.005:
        edge=Image.new("RGBA",shape.size)
        ImageDraw.Draw(edge).rounded_rectangle((1,1,w-2,h-2),radius=20*ASSET_SCALE,outline=(255,255,255,18),width=4)
        shape.alpha_composite(edge)
    if t >= end:
        shape.putalpha(shape.getchannel("A").point(lambda a: round(a*(1-ease_out((t-end)/.18)))))
    frame.paste(shape,W/2,PROMPTER_TOP,anchor=(.5,0))


def compose(folder, tl, geometry, out, keys_only=False):
    import imageio_ffmpeg
    assets = Assets(folder)
    frames = int(round(tl.duration * FPS))
    keys_file = folder / "keys.json"
    keys = {int(round(k * FPS)) for k in json.loads(keys_file.read_text())} if keys_file.exists() else set()
    # Потоковая запись: не держим тысячи несжатых кадров в памяти.
    encoder = None if keys_only else subprocess.Popen([
        imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-v", "error", "-f", "rawvideo",
        "-pix_fmt", "rgba", "-s", f"{OUT_W}x{OUT_H}", "-r", str(FPS), "-i", "-",
        "-c:v", "libwebp_anim", "-lossless", "1", "-quality", "92", "-compression_level", "4",
        "-loop", "0", str(out)
    ], stdin=subprocess.PIPE)
    # Антиалиасинг внешнего радиуса и обводки; углы прозрачны на любой странице.
    sup = 3
    border = Image.new("RGBA", (OUT_W * sup, OUT_H * sup))
    ImageDraw.Draw(border).rounded_rectangle((sup/2, sup/2, OUT_W*sup-sup/2, OUT_H*sup-sup/2),
        radius=20*K*sup, outline="#3d444d", width=round(K*sup))
    border = border.resize((OUT_W, OUT_H), Image.LANCZOS)
    mask = rounded_mask((OUT_W*sup, OUT_H*sup), 20*K*sup).resize((OUT_W, OUT_H), Image.LANCZOS)
    try:
        for i in (sorted(keys) if keys_only else range(frames)):
            t = i / FPS
            frame = Frame(camera_at(tl, t))
            draw_background(frame, assets)
            draw_dock(frame, assets)
            draw_console(frame, assets, tl, t, geometry)
            draw_library(frame, assets, tl, t, geometry)
            draw_prompter(frame, assets, tl, t)
            draw_mascot(frame, assets, tl, t, i)
            draw_drag(frame, assets, tl, t, geometry)
            for c in tl.clicks:
                radius = 22 if c["target"].startswith("top-") else 26
                draw_ring(frame, c["x"], c["y"], t-c["t"],radius)
            frame.img.putalpha(mask)
            frame.img.alpha_composite(border)
            if encoder: encoder.stdin.write(frame.img.tobytes())
            if i in keys:
                frame.img.save(folder / f"key-{t:05.2f}.png")
            if i % (FPS * 5) == 0:
                print(f"Монтаж: {t:.0f}/{tl.duration:.0f} с", flush=True)
    finally:
        if encoder: encoder.stdin.close()
    if encoder and encoder.wait() != 0:
        raise RuntimeError("Не удалось записать WebP")
    return out


def outline_error(img):
    """Внешний пояс 2 pt обязан содержать ровно один эталонный контур."""
    body=crop_panel(img)
    expected=capsule_surface(Image.new("RGBA",body.size,(10,10,10,255)))
    def visible(image):
        bg=Image.new("RGBA",image.size,"#0d1117");bg.alpha_composite(image)
        return bg.convert("RGB")
    band=Image.new("L",body.size,255)
    inset=round(2*ASSET_SCALE)
    ImageDraw.Draw(band).rounded_rectangle((inset,inset,body.width-inset-1,body.height-inset-1),
                                          radius=body.height/2-inset,fill=0)
    difference=ImageChops.difference(visible(body),visible(expected))
    return ImageChops.multiply(difference,Image.merge("RGB",(band,band,band))).getbbox()


def verify_assets(assets, tl, geometry):
    import hashlib
    def unique(directory, count):
        return len({hashlib.sha256((assets.folder/directory/f"{i:04d}.png").read_bytes()).digest()
                    for i in range(count)})
    for i in range(round(tl.duration*FPS)):
        if not (assets.mascot_dir/f"{i:04d}.png").is_file():
            raise ValueError(f"Нет кадра маскота {i}")
    library_unique=unique("library",2*FPS)
    assert library_unique>FPS, "Библиотека не анимируется"
    start,end=tl.prompter
    count=round((end-start)*FPS)
    prompter_unique=unique("prompter",count)
    assert prompter_unique>FPS, "Текст Докладчика не движется"
    pause_start=round((tl.pause[0]-start)*FPS)+2
    pause_end=round((tl.pause[1]-start)*FPS)-2
    paused={hashlib.sha256((assets.folder/"prompter"/f"{i:04d}.png").read_bytes()).digest()
            for i in range(pause_start,pause_end)}
    assert len(paused)==1,"Текст продолжает ехать на паузе"
    for c in tl.clicks:
        if c["rect"]:
            x,y,w,h=c["rect"]
            assert abs(c["x"]-(x+w/2))<.001 and abs(c["y"]-(y+h/2))<.001
    cap=geometry[0]
    panel=geometry[1]
    left=panel[0]-CAM_CONSOLE[0]
    right=CAM_CONSOLE[0]+CAM_CONSOLE[2]-panel[0]-panel[2]
    assert abs(left-right)<.001,"Пульт не по центру камеры"
    assert PROMPTER_TOP>=MENU_HEIGHT+6-.001
    word_boxes=set()
    for i in range(count):
        targets=json.loads((assets.folder/"prompter"/f"{i:04d}.targets.json").read_text())
        if "spoken-word" in targets:word_boxes.add(tuple(round(v,1) for v in targets["spoken-word"]))
    assert len(word_boxes)>10,"Нет движущейся подсветки слов"
    outline_checks=0
    for path in list(assets.folder.glob("capsule*.png"))+list((assets.folder/"prompter").glob("capsule*.png")):
        assert outline_error(Image.open(path).convert("RGBA")) is None, f"Двойной контур: {path}"
        outline_checks+=1
    for reveal_start,length in ((14.1,1),(15.3,1),(tl.duration-.45,.45)):
        for i in range(round(length*FPS)+1):
            assert outline_error(capsule_image(assets,tl,reveal_start+i/FPS)) is None, f"Двойной контур в переходе: {reveal_start+i/FPS}"
            outline_checks+=1
    status_checks=0
    for i in range(round((tl.pause[0]-start)*FPS), round((tl.pause[1]-start)*FPS)):
        targets=json.loads((assets.folder/"prompter"/f"{i:04d}.targets.json").read_text())
        assert "top-status" in targets, "Нет статуса паузы"
        x,y,w,h=targets["top-status"]
        image=Image.open(assets.folder/"prompter"/f"{i:04d}.png").convert("RGB")
        region=crop_rect(image,(x+8,y+4,w-16,h-8))
        assert max(max(pixel) for pixel in region.getdata())>=200, "Статус Пауза затемнён маской"
        status_checks+=1
    for i in range(count):
        targets=json.loads((assets.folder/"prompter"/f"{i:04d}.targets.json").read_text())
        if "spoken-word" in targets:
            x,y,w,h=targets["spoken-word"]
            assert y >= 8 and y+h <= 156, f"Текущее слово обрезано: {i}: {y}, {h}"
    for path in list(assets.folder.glob("capsule*.png"))+list(assets.folder.glob("panel*.png")):
        img=Image.open(path).convert("RGBA")
        radius=(img.height-16*ASSET_SCALE)/2 if path.name.startswith("capsule") else 24*ASSET_SCALE
        mask=Image.new("L",img.size)
        inset=round(8*ASSET_SCALE)
        ImageDraw.Draw(mask).rounded_rectangle((inset,inset,img.width-inset-1,img.height-inset-1),radius=radius,fill=255)
        assert ImageChops.subtract(img.getchannel("A"),mask).getbbox() is None, f"Пиксели вне контура: {path.name}"
    for service in ("claude","codex"):
        assert len({hashlib.sha256((assets.folder/f"panel-limits-reveal-{service}-{i}.png").read_bytes()).digest() for i in range(61)})>40
    assert abs(cap[1]+cap[3]/2-MASCOT[1])<.001
    capsule_counts={service:len({hashlib.sha256((assets.folder/f"capsule-reveal-{service}-{i}.png").read_bytes()).digest() for i in range(61)}) for service in ("claude","codex")}
    assert min(capsule_counts.values())>10,"Не анимируются проценты капсулы"
    report={"capsule_outline_checks":outline_checks,"pause_status_checks":status_checks,"clicks":len(tl.clicks),"capsule_unique_frames":capsule_counts,"library_unique_frames":library_unique,
            "prompter_unique_frames":prompter_unique,"pause_is_static":True,
            "capsule_center_y":cap[1]+cap[3]/2,"mascot_center_y":MASCOT[1],
            "console_side_padding":[left,right],"menu_height":MENU_HEIGHT,"prompter_top":PROMPTER_TOP,"word_highlight_positions":len(word_boxes)}
    (assets.folder/"verification.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print("Проверка исходников:",json.dumps(report,ensure_ascii=False),flush=True)


def clean_snapshot_edges(folder):
    """cacheDisplay оставляет пиксели вне SwiftUI clipShape: ограничиваем экспорт той же геометрией."""
    paths = list(folder.glob("capsule*.png")) + list(folder.glob("panel*.png")) + list((folder/"prompter").glob("*.png"))
    for path in paths:
        img = Image.open(path).convert("RGBA")
        inset = round(8*ASSET_SCALE)
        w,h = img.width-2*inset, img.height-2*inset
        radius = h/2 if path.name.startswith("capsule") else (20 if path.parent.name == "prompter" else 24)*ASSET_SCALE
        # Сохраняем родное сглаживание на контуре, убираем только внешние пиксели.
        mask = Image.new("L",img.size)
        ImageDraw.Draw(mask).rounded_rectangle((inset,inset,inset+w-1,inset+h-1),radius=radius,fill=255)
        img.putalpha(ImageChops.multiply(img.getchannel("A"),mask))
        if path.name.startswith("capsule"):
            # Заменяем весь внешний пояс, включая линии ВНУТРИ прежней маски.
            body=capsule_surface(crop_panel(img))
            img=Image.new("RGBA",img.size)
            img.alpha_composite(body,(inset,inset))
        img.save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("--app", default="/Applications/Agent Pulse.app/Contents/MacOS/AgentPulse")
    parser.add_argument("--only-compose", action="store_true")
    parser.add_argument("--only-assets", action="store_true", help="Обновить страницы без кадров маскота и монтажа")
    parser.add_argument("--only-prompter", action="store_true", help="Обновить Докладчик, сохранив остальные исходники, и смонтировать")
    parser.add_argument("--out")
    parser.add_argument("--keys-only", action="store_true", help="Только контрольные кадры, без кодирования")
    parser.add_argument("--menu-bar", help="Скриншот только системной строки меню")
    parser.add_argument("--menu-bar-height", type=int, help="Высота строки меню в пикселях исходника")
    parser.add_argument("--dock", help="Прозрачный PNG только окна Dock, обрезанный по альфа-каналу (Retina 2x)")
    parser.add_argument("--dock-cut", help="Убрать секцию исходного Dock: левая:правая координаты в px")
    parser.add_argument("--dock-screen-width", type=float, help="Ширина экрана, на котором снят Dock, в pt")
    args = parser.parse_args()
    folder = Path(args.folder).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if args.menu_bar:
        bar=Image.open(args.menu_bar).convert("RGBA")
        if args.menu_bar_height: bar=bar.crop((0,0,bar.width,args.menu_bar_height))
        bar.save(folder/"menu-bar.png")
    if args.dock:
        if not args.dock_screen_width or args.dock_screen_width <= 0:
            parser.error("Для --dock нужна --dock-screen-width в pt")
        import shutil
        if Path(args.dock).resolve() != folder / "dock.png":
            shutil.copyfile(args.dock, folder / "dock.png")
        dock_spec={"screen_width":args.dock_screen_width}
        if args.dock_cut: dock_spec["remove_ranges"]=[list(map(int,args.dock_cut.split(":")))]
        (folder / "dock.json").write_text(json.dumps(dock_spec))
    # Геометрия вкладок и капсулы нужна до сценария, а картинки — после: первый проход рисует их с черновым сценарием.
    if not args.only_compose and not args.only_prompter and not (args.only_assets and (folder/"capsule.png").exists()):
        draft = Timeline()
        draft.states=[(0,"idle")]; draft.cursor=[(0,0,0)]
        draft.duration = 1 / FPS
        write_script(folder, draft, assets_only=True)
        subprocess.run([args.app, "--promo-sheet", str(folder)], check=True)
    assets = Assets(folder)
    configure_stage(assets)
    geometry = capsule_geometry(assets)
    capsule, _ = geometry
    tl = build_timeline(assets, geometry)
    (folder/"clicks.json").write_text(json.dumps(tl.clicks,ensure_ascii=False,indent=2))
    if not args.only_compose:
        write_script(folder, tl, assets_only=args.only_assets)
        command = [args.app, "--promo-sheet", str(folder)]
        if args.only_prompter: command.append("--promo-prompter-only")
        subprocess.run(command, check=True)
    if not args.only_compose:
        clean_snapshot_edges(folder)
        assets = Assets(folder)
    if args.only_assets:
        return
    out = Path(args.out) if args.out else folder / "agent-pulse-demo.webp"
    verify_assets(assets,tl,geometry)
    compose(folder, tl, geometry, out, keys_only=args.keys_only)
    print(folder if args.keys_only else out)


if __name__ == "__main__":
    main()
