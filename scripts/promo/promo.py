#!/usr/bin/env python3
"""Промо-ролик Agent Pulse для README: настоящие виды приложения, камера, курсор и клики.

    python3 scripts/promo/promo.py ПАПКА [--app путь/к/AgentPulse] [--only-compose]

1. Пишет ПАПКА/script.json — сценарий маскота (состояния, реакции, курсор).
2. Запускает приложение с `--promo-sheet ПАПКА`: настоящий аниматор на виртуальных часах рисует кадры
   маскота, облачка, капсулу и страницы Пульта (без окон на экране).
3. Монтирует ролик на нейтральном рабочем столе: камера по кривой V4 (Telegram Motion Style),
   матовое кольцо клика, раскрытие Пульта как в приложении. Итог — ПАПКА/agent-pulse-demo.webp.

Нужен только Pillow. Никаких данных пользователя: рабочий стол нарисован, файлы и тексты вымышлены.
"""
import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

FPS = 30
W, H = 1280.0, 800.0            # экран в pt
OUT_W, OUT_H = 1280, 800        # кадр ролика
K = OUT_W / W                   # px на pt при общем плане
ASSET_SCALE = 4.0               # во сколько раз крупнее pt рисует приложение
DIAMETER = 48.0
BOX = DIAMETER * 2.2
OVERLAP = max(0.0, (BOX - DIAMETER) / 2 - 8)

MASCOT = (W - 16 - BOX / 2 + 8, H - 58.0)     # центр тела
CAPSULE_LEFT = 16.0
GAP = 8.0
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
CAM_CONSOLE = view_corner(720, left=True)


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


def build_timeline(tabs):
    tl = Timeline()
    s = tl.states
    s.append((0.0, "idle"))
    tl.cursor += [(0.0, 680, 380), (1.3, 730, 420)]
    # Камера к маскоту.
    tl.camera.append((1.4, CAM_MASCOT))
    s.append((2.3, "think")); tl.bubbles.append((2.4, 3.95, "think"))
    s.append((4.0, "edit")); tl.bubbles.append((4.1, 5.65, "edit"))
    s.append((5.7, "permission")); tl.bubbles.append((5.8, 8.45, "permission"))
    # Курсор к маскоту: глаза следят, клик — переход к агенту.
    tl.cursor += [(6.4, 980, 640), (7.6, MASCOT[0] - 4, MASCOT[1] - 2), (8.6, MASCOT[0] - 4, MASCOT[1] - 2)]
    tl.hover.append((7.3, 8.7))
    tl.clicks.append(8.3)
    s.append((8.6, "edit")); tl.bubbles.append((8.7, 9.75, "edit"))
    tl.cursor += [(9.6, 1060, 690)]
    tl.reactions.append((9.8, "done")); s.append((9.8, "idle")); tl.bubbles.append((9.85, 12.2, "done"))
    # Общий план, затем Пульт.
    tl.camera.append((12.0, CAM_WIDE))
    tl.camera.append((13.3, CAM_CONSOLE))
    cap = tabs["capsule_center"]
    tl.cursor += [(12.2, 900, 620), (13.4, 380, 560), (14.3, cap[0], cap[1]), (14.75, cap[0], cap[1])]
    tl.clicks.append(14.6); tl.panel.append((14.62, "open", "limits"))
    t = 14.62 + 0.45 + 1.6
    for name in ("shelf", "translate", "prompter"):
        x, y = tabs[name]
        tl.cursor += [(t - 0.9, x, y), (t + 0.2, x, y)]
        tl.clicks.append(t); tl.panel.append((t + 0.02, "tab", name))
        t += 1.9
    # Клик мимо — Пульт сворачивается.
    tl.cursor += [(t - 0.8, 900, 300), (t + 0.2, 900, 300)]
    tl.clicks.append(t); tl.panel.append((t + 0.02, "close", None))
    tl.camera.append((t + 0.5, CAM_WIDE))
    tl.cursor += [(t + 1.6, 680, 380)]
    tl.duration = t + 0.5 + 0.75 + 1.6
    return tl


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


def write_script(folder, tl):
    frames = int(round(tl.duration * FPS))
    cursor = []
    for i in range(frames):
        x, y = cursor_at(tl, i / FPS)
        cursor.append([x - MASCOT[0], y - MASCOT[1]])
    script = {
        "fps": FPS, "duration": tl.duration, "diameter": DIAMETER, "scale": ASSET_SCALE,
        "states": [{"t": t, "state": n} for t, n in tl.states],
        "reactions": [{"t": t, "name": n} for t, n in tl.reactions],
        "hover": [list(h) for h in tl.hover],
        "cursor": cursor,
        "bubbles": BUBBLES,
    }
    (folder / "script.json").write_text(json.dumps(script, ensure_ascii=False))

# ---------- монтаж ----------

def wallpaper(width, height):
    """Нейтральный рабочий стол: мягкий градиент с двумя размытыми пятнами света."""
    small = Image.new("RGB", (160, 100))
    px = small.load()
    for y in range(100):
        for x in range(160):
            u, v = x / 159, y / 99
            r = 52 + 40 * u + 18 * v
            g = 62 + 30 * u + 26 * (1 - v)
            b = 104 + 46 * (1 - u) + 20 * v
            for cx, cy, rad, (cr, cg, cb), amp in ((.22, .28, .38, (150, 170, 230), .55), (.82, .78, .42, (215, 160, 190), .45)):
                d = math.hypot(u - cx, (v - cy) * .62) / rad
                f = max(0.0, 1 - d) ** 2 * amp
                r, g, b = r + (cr - r) * f, g + (cg - g) * f, b + (cb - b) * f
            px[x, y] = (int(r), int(g), int(b))
    return small.resize((width, height), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6))


class Assets:
    def __init__(self, folder):
        self.folder = folder
        self.bubbles = {b["id"]: Image.open(folder / f"bubble-{b['id']}.png").convert("RGBA") for b in BUBBLES}
        self.capsule = Image.open(folder / "capsule.png").convert("RGBA")
        self.panels = {n: Image.open(folder / f"panel-{n}.png").convert("RGBA")
                       for n in ("limits", "shelf", "translate", "prompter")}
        self.cursor = Image.open(folder / "cursor.png").convert("RGBA")
        self.mascot_dir = folder / "mascot"
        # Запас по краям: на перелёте камеры видно чуть больше экрана.
        self.margin = 80.0
        self.wall = wallpaper(int((W + 2 * self.margin) * 2), int((H + 2 * self.margin) * 2))

    def mascot(self, index):
        path = self.mascot_dir / f"{index:04d}.png"
        return Image.open(path).convert("RGBA") if path.exists() else None


def capsule_geometry(assets):
    """Капсула и панель в pt. Картинки отрисованы с полем 8 pt."""
    cw = assets.capsule.width / ASSET_SCALE - 16
    ch = assets.capsule.height / ASSET_SCALE - 16
    cy = MASCOT[1]
    capsule = (CAPSULE_LEFT, cy - ch / 2, cw, ch)
    ph = assets.panels["limits"].height / ASSET_SCALE - 16
    panel = (CAPSULE_LEFT, capsule[1] - GAP - ph, PANEL_W, ph)
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
    s, m = 2.0, assets.margin
    box = ((frame.x0 + m) * s, (frame.y0 + m) * s, (frame.x0 + m + OUT_W / frame.k) * s, (frame.y0 + m + OUT_H / frame.k) * s)
    frame.img.paste(assets.wall.resize((OUT_W, OUT_H), Image.BICUBIC, box=box), (0, 0))


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


def draw_console(frame, assets, tl, t, geometry):
    capsule, panel = geometry
    cx, cy, cw, ch = capsule
    openness, content, tab, prev, change = panel_state(tl, t)
    if openness <= 0.001:
        frame.paste(assets.capsule, cx - 8, cy - 8)
        return
    px_, py_, pw, ph = panel
    # Форма растёт из капсулы: ширина, высота и радиус от капсулы к панели, низ и левый край на месте.
    o = openness
    width = cw + (pw - cw) * o
    height = ch + (ph - ch) * o
    radius = ch / 2 + (24 - ch / 2) * min(1.0, max(0.0, o))
    bottom = cy + ch + (py_ + ph - (cy + ch)) * o
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
    frame._paste_clipped(shape, round(l), round(tp)) if l < 0 or tp < 0 else frame.img.alpha_composite(shape, (round(l), round(tp)))
    # Капсула в приложении лежит поверх формы (VStack: панель, затем капсула).
    frame.paste(assets.capsule, cx - 8, cy - 8)


def crop_panel(img):
    m = round(8 * ASSET_SCALE)
    return img.crop((m, m, img.width - m, img.height - m))


def page_image(assets, tab, prev, change, t):
    """Смена страницы: новая выходит с 24 pt и проявляется за 0.24 s, старая гаснет за 0.08 s."""
    current = crop_panel(assets.panels[tab])
    dt = t - change
    if prev is None or dt >= .24:
        return current
    order = ["limits", "prompter", "shelf", "translate"]
    direction = 1 if order.index(tab) > order.index(prev) else -1
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


def draw_ring(frame, x, y, rel):
    radius_share, alpha, hole = tap_state(rel)
    if alpha <= 0.01:
        return
    r = 26 * frame.k * radius_share
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


def draw_cursor(frame, assets, x, y, press):
    """Стрелка macOS (картинка 2x); острие — в точке (x, y). При нажатии чуть сжимается к острию."""
    c = assets.cursor
    scale = (1 - .1 * press) * frame.k / 2
    img = c.resize((max(1, round(c.width * scale)), max(1, round(c.height * scale))), Image.LANCZOS)
    hx, hy = frame.px(x, y)
    pos = (round(hx - 5 * scale), round(hy - 6 * scale))
    if pos[0] < 0 or pos[1] < 0:
        frame._paste_clipped(img, *pos)
    else:
        frame.img.alpha_composite(img, pos)


def compose(folder, tl, geometry, out):
    assets = Assets(folder)
    frames = int(round(tl.duration * FPS))
    images = []
    # Кадры для проверки глазами: `keys.json` — список секунд.
    keys_file = folder / "keys.json"
    keys = {int(round(k * FPS)) for k in json.loads(keys_file.read_text())} if keys_file.exists() else set()
    for i in range(frames):
        t = i / FPS
        frame = Frame(camera_at(tl, t))
        draw_background(frame, assets)
        draw_console(frame, assets, tl, t, geometry)
        draw_mascot(frame, assets, tl, t, i)
        x, y = cursor_at(tl, t)
        press = 0.0
        for c in tl.clicks:
            rel = t - c
            draw_ring(frame, x, y, rel)
            if -.12 <= rel <= .12:
                press = max(press, 1 - abs(rel) / .12)
        draw_cursor(frame, assets, x, y, press)
        images.append(frame.img.convert("RGB"))
        if i in keys:
            frame.img.convert("RGB").save(folder / f"key-{t:05.2f}.png")
    images[0].save(out, save_all=True, append_images=images[1:], duration=round(1000 / FPS), loop=0, quality=80, method=4)
    return out


def tab_targets(assets, geometry):
    """Где на экране вкладки Пульта (pt). Отступы — по картинке панели."""
    _, panel = geometry
    px_, py_, _, _ = panel
    spec = json.loads((assets.folder / "tabs.json").read_text()) if (assets.folder / "tabs.json").exists() else None
    names = {"limits": 0, "prompter": 1, "shelf": 2, "translate": 3}
    if spec:
        return {n: (px_ + spec[n][0], py_ + spec[n][1]) for n in names}
    return {n: (px_ + 60 + 92 * i, py_ + 23) for n, i in names.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("--app", default="/Applications/Agent Pulse.app/Contents/MacOS/AgentPulse")
    parser.add_argument("--only-compose", action="store_true")
    parser.add_argument("--out")
    args = parser.parse_args()
    folder = Path(args.folder).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    # Геометрия вкладок и капсулы нужна до сценария, а картинки — после: первый проход рисует их с черновым сценарием.
    if not args.only_compose:
        draft = build_timeline({"capsule_center": (60, MASCOT[1]), "limits": (0, 0), "prompter": (0, 0), "shelf": (0, 0), "translate": (0, 0)})
        write_script(folder, draft)
        subprocess.run([args.app, "--promo-sheet", str(folder)], check=True)
    assets = Assets(folder)
    geometry = capsule_geometry(assets)
    capsule, _ = geometry
    targets = tab_targets(assets, geometry)
    targets["capsule_center"] = (capsule[0] + capsule[2] / 2, capsule[1] + capsule[3] / 2)
    tl = build_timeline(targets)
    if not args.only_compose:
        write_script(folder, tl)
        subprocess.run([args.app, "--promo-sheet", str(folder)], check=True)
    out = Path(args.out) if args.out else folder / "agent-pulse-demo.webp"
    compose(folder, tl, geometry, out)
    print(out)


if __name__ == "__main__":
    main()
