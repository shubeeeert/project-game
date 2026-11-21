# -*- coding: utf-8 -*-
"""Generate slide images and the worksheet for the new lesson."""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r'E:\ill-try'
ASSETS = os.path.join(BASE, 'assets')
OUT = os.path.join(BASE, 'output')
SLIDES = os.path.join(OUT, 'slides')
os.makedirs(SLIDES, exist_ok=True)

FONT_REG = r'C:\Windows\Fonts\arial.ttf'
FONT_BOLD = r'C:\Windows\Fonts\arialbd.ttf'

BG = Image.open(os.path.join(ASSETS, 'ppt_image1.png')).convert('RGB').resize((1280, 720))
MAP = Image.open(os.path.join(ASSETS, 'ppt_image6.png')).convert('RGB')


def font(size, bold=False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)


def wrap(text, fnt, max_width, draw):
    words = text.split()
    lines, cur = [], ''
    for w in words:
        test = (cur + ' ' + w).strip()
        if draw.textlength(test, font=fnt) <= max_width:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def center_text(draw, y, text, fnt, fill, width=1280, x0=0, gap=8):
    for line in wrap(text, fnt, width - 120, draw):
        w = draw.textlength(line, font=fnt)
        draw.text((x0 + (width - w) / 2, y), line, font=fnt, fill=fill)
        y += fnt.size + gap
    return y


def left_text(draw, x, y, text, fnt, fill, max_width=1020, gap=12):
    for line in wrap(text, fnt, max_width, draw):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + gap
    return y


def make_slide(idx, title, blocks, picture=None, subtitle=None):
    img = BG.copy()
    d = ImageDraw.Draw(img)
    # Title
    center_text(d, 62, title, font(46, True), (35, 70, 45))
    d.line((340, 132, 940, 132), fill=(255, 150, 40), width=5)
    y = 172
    if subtitle:
        y = center_text(d, y, subtitle, font(30, True), (40, 90, 70), gap=10) + 16
    for block in blocks:
        y = left_text(d, 135, y, block, font(29), (45, 55, 60), gap=12) + 14
    if picture is not None:
        pic = picture.copy()
        maxw, maxh = 860, 400
        scale = min(maxw / pic.width, maxh / pic.height)
        pic = pic.resize((int(pic.width * scale), int(pic.height * scale)))
        img.paste(pic, ((1280 - pic.width) // 2, min(720 - pic.height - 30, y + 8)))
    path = os.path.join(SLIDES, f'slide{idx:02d}.png')
    img.save(path)
    return path


slides = []
slides.append(make_slide(1, 'Урок окружающего мира',
                         ['4 класс'], subtitle='Равнины и горы России'))
slides.append(make_slide(2, 'Русская народная пословица',
                         ['«Гора с горой не сходится,', 'а человек с человеком сходится».'],
                         subtitle='Объясни её смысл'))
slides.append(make_slide(3, 'Вспомним!',
                         ['Какие формы земной поверхности ты знаешь?',
                          'Холм, гора, равнина, овраг, долина.',
                          'Части холма и горы: подошва, склон, вершина.']))
slides.append(make_slide(4, 'Физическая карта России',
                         ['Найдите на карте равнины и горы нашей страны.'],
                         picture=MAP))
slides.append(make_slide(5, 'Тема и цель урока',
                         ['Тема урока: «Равнины и горы России».',
                          'Цель: узнать об основных формах земной поверхности России '
                          'и научиться находить их на карте.']))
slides.append(make_slide(6, 'План урока',
                         ['1. Вспомним формы рельефа.',
                          '2. Узнаем о равнинах России.',
                          '3. Узнаем о горах России.',
                          '4. Закрепим знания на рабочем листе.']))
slides.append(make_slide(7, 'Что такое рельеф?',
                         ['Рельеф — это неровности земной поверхности.',
                          'Основные формы рельефа — равнины и горы.',
                          'Равнина — ровная или холмистая поверхность небольшой высоты.',
                          'Горы — возвышенности с крутыми склонами и вершинами.']))
slides.append(make_slide(8, 'Равнины России',
                         ['Восточно-Европейская (Русская) равнина — холмистая, '
                          'есть низменности и возвышенности.',
                          'Западно-Сибирская равнина — плоская, низкая, много болот.',
                          'Среднесибирское плоскогорье — возвышенная равнина.']))
slides.append(make_slide(9, 'Горы России',
                         ['Уральские горы — низкие (менее 2000 м), богаты минералами.',
                          'Кавказские горы — самые высокие; гора Эльбрус, 5642 м.',
                          'Алтай и Саяны — горы Сибири.']))
slides.append(make_slide(10, 'Физкультминутка',
                         ['Руки вверх — «горы», присели — «равнина».',
                          'Потянулись, глубоко вдохнули и улыбнулись!']))
slides.append(make_slide(11, 'Правила работы в парах',
                         ['1. Работают оба.',
                          '2. Один говорит, другой слушает.',
                          '3. Своё несогласие высказывай вежливо.',
                          '4. Работают тихо и не мешают другим.']))
slides.append(make_slide(12, 'Проверь себя',
                         ['1. Какая равнина самая плоская и низкая в России?',
                          '2. Какие горы разделяют европейскую и азиатскую части страны?',
                          '3. Как называется высочайшая вершина России?']))
slides.append(make_slide(13, 'Самостоятельная работа',
                         ['Выполни задания рабочего листа (Приложение 1):',
                          'исправь ошибки в тексте, заполни таблицу «Рельеф России», '
                          'пройди тест.']))
slides.append(make_slide(14, 'Домашнее задание',
                         ['1. Учебник: с. 44–47, пересказ по вопросам рубрики «Проверь себя».',
                          '2. Рабочий лист: задания на выбор.']))
slides.append(make_slide(15, 'Оцени свою работу',
                         [':) Всё понятно, трудностей не возникло.',
                          ':| Были небольшие затруднения.',
                          ':( Материал показался сложным.']))
slides.append(make_slide(16, 'Подведём итог',
                         ['Россия — страна огромных равнин и величественных гор.',
                          'Главные равнины: Восточно-Европейская, Западно-Сибирская, '
                          'Среднесибирское плоскогорье.',
                          'Главные горы: Уральские, Кавказские, Алтай, Саяны.']))
print('slides created:', len(slides))

# ---------------- Worksheet ----------------
W, H = 1102, 1800
ws = Image.new('RGB', (W, H), 'white')
d = ImageDraw.Draw(ws)

d.text((40, 28), 'Рабочий лист', font=font(32, True), fill=(20, 60, 40))
d.text((40, 72), 'ФИО: ____________________________   Класс: ______', font=font(20), fill='black')
d.text((40, 104), 'Тема: Равнины и горы России', font=font(22, True), fill='black')

def section(y, title, lines, step=30):
    d.text((40, y), title, font=font(21, True), fill=(20, 70, 45))
    y += 34
    for ln in lines:
        for piece in wrap(ln, font(18), W - 100, d):
            d.text((55, y), piece, font=font(18), fill='black')
            y += 25
        y += 5
    return y + 12

y = section(145, 'Пункт 1. Тема урока', [
    'Прочитай утверждение. Если есть ошибка, зачеркни её и напиши сверху правильное.',
    'Равнины и горы — это основные формы земной поверхности России.',
])
d.rectangle((40, y, W - 40, y + 78), outline=(120, 160, 140), width=2)
for i, t in enumerate(['Россия — страна огромных равнин и величественных гор.',
                       'Самая высокая гора России — Эльбрус.']):
    d.text((55, y + 10 + i * 32), t, font=font(18), fill='black')
y += 92

d.text((40, y), 'Пункт 2. Заполни таблицу «Рельеф России»', font=font(21, True), fill=(20, 70, 45))
y += 34
col_x = [40, 380, 650]
headers = ['Название объекта', 'Цвет на физ. карте', 'Особенности']
row_h = 52
for cx, htxt in zip(col_x, headers):
    d.rectangle((cx, y, cx + (col_x[1]-col_x[0] if cx == col_x[0] else (col_x[2]-col_x[1] if cx == col_x[1] else W-40-col_x[2])), y + row_h),
                outline='black', width=1)
    d.text((cx + 6, y + 14), htxt, font=font(16, True), fill='black')
y += row_h
rows = [
    'Восточно-Европейская (Русская) равнина',
    'Западно-Сибирская равнина',
    'Среднесибирское плоскогорье',
    'Уральские горы',
    'Кавказские горы',
]
for r in rows:
    d.rectangle((40, y, W - 40, y + row_h), outline='black', width=1)
    d.line((col_x[1], y, col_x[1], y + row_h), fill='black')
    d.line((col_x[2], y, col_x[2], y + row_h), fill='black')
    d.text((46, y + 15), r, font=font(15), fill='black')
    y += row_h
y += 14

y = section(y, 'Пункт 3. Найди и исправь ошибки в тексте', [
    'Самая высокая гора России — Эльбрус, её высота составляет всего 1000 метров.',
    'Уральские горы разделяют европейскую и азиатскую части России.',
])

d.text((40, y), 'Пункт 4. Тест. Отметь галочкой правильный ответ', font=font(21, True), fill=(20, 70, 45))
y += 34
questions = [
    ('1. Какая равнина является самой плоской и низкой в России?',
     ['Восточно-Европейская', 'Западно-Сибирская', 'Среднесибирское плоскогорье']),
    ('2. Какие горы разделяют европейскую и азиатскую части России?',
     ['Кавказские', 'Уральские', 'Алтай']),
    ('3. Как называется высочайшая вершина России?',
     ['Эльбрус', 'Белуха', 'Компьютерная вершина']),
    ('4. Что расположено на полуострове Камчатка?',
     ['Действующие вулканы', 'Бескрайние степи', 'Болота']),
]
for q, opts in questions:
    for piece in wrap(q, font(17, True), W - 90, d):
        d.text((48, y), piece, font=font(17, True), fill='black')
        y += 24
    for o in opts:
        d.text((70, y), '☐  ' + o, font=font(17), fill='black')
        y += 26
    y += 10

y = section(y + 4, 'Пункт 5. Рефлексия', [
    'Нарисуй в кружке смайлик, который отражает твоё настроение на уроке.',
])
for i, label in enumerate(['Мне было интересно', 'Было трудно, но я справился', 'Нужна помощь']):
    x = 60 + i * 340
    d.ellipse((x, y, x + 70, y + 70), outline=(40, 90, 60), width=3)
    d.text((x, y + 78), label, font=font(16), fill='black')

ws_path = os.path.join(OUT, 'рабочий_лист_равнины_и_горы.png')
ws.save(ws_path)
print('worksheet created:', ws_path, ws.size)
