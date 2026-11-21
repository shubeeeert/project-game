# -*- coding: utf-8 -*-
"""Build the new PPTX and the lesson-plan DOCX."""
import os
from docx import Document
from docx.shared import Pt, Inches, Mm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_ORIENT, WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from pptx import Presentation
from pptx.util import Inches as PInches

BASE = r'E:\ill-try'
OUT = os.path.join(BASE, 'output')
SLIDES = os.path.join(OUT, 'slides')
WS = os.path.join(OUT, 'рабочий_лист_равнины_и_горы.png')

# ---------------- PPTX ----------------
prs = Presentation()
prs.slide_width = PInches(13.333)
prs.slide_height = PInches(7.5)
blank = prs.slide_layouts[6]
for i in range(1, 17):
    slide = prs.slides.add_slide(blank)
    slide.shapes.add_picture(os.path.join(SLIDES, f'slide{i:02d}.png'), 0, 0,
                             width=prs.slide_width, height=prs.slide_height)
pptx_path = os.path.join(OUT, 'Презентация_Равнины_и_горы_России_4б.pptx')
prs.save(pptx_path)
print('pptx saved:', pptx_path, len(prs.slides), 'slides')

# ---------------- DOCX ----------------
doc = Document()
sec = doc.sections[0]
sec.page_width = Mm(297)
sec.page_height = Mm(210)
sec.left_margin = sec.right_margin = Mm(12)
sec.top_margin = sec.bottom_margin = Mm(12)

normal = doc.styles['Normal']
normal.font.name = 'Times New Roman'
normal.font.size = Pt(12)
normal._element.rPr.rFonts.set(qn('w:eastAsia'), 'Times New Roman')
normal.paragraph_format.space_after = Pt(2)
normal.paragraph_format.space_before = Pt(0)

def add_line(text='', bold=False, size=12, align=None, italic=False, space_after=2):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    p.paragraph_format.space_after = Pt(space_after)
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.name = 'Times New Roman'
    r.font.size = Pt(size)
    return p

def add_bullet(text):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_after = Pt(1)
    r = p.add_run(text)
    r.font.name = 'Times New Roman'
    r.font.size = Pt(12)
    return p

add_line('Технологическая карта урока окружающего мира', bold=True, size=14,
         align=WD_ALIGN_PARAGRAPH.CENTER, space_after=8)
add_line('ФИО студента-практиканта/учителя базовой школы: Ануфриева Полина Игоревна/'
         'Чулкова Екатерина Юрьевна')
add_line('Класс: 4 «Б»')
add_line('Дата: 21.10.2026')
add_line('Тема урока: Равнины и горы России')
add_line('Тип урока: открытие новых знаний.')
add_line('Цель урока: организация деятельности обучающихся по изучению и первичному '
         'закреплению знаний об основных формах земной поверхности России, '
         'формирование умения находить и показывать равнины и горы на физической карте.')
add_line('Задачи урока:', bold=True)
add_line('Дидактическая: содействовать формированию у младших школьников знаний о '
         'равнинах и горах России, их особенностях; содействовать формированию умений '
         'работать с физической картой.')
add_line('Развивающая: содействовать развитию интереса к предмету «Окружающий мир», '
         'пространственного мышления посредством работы с картой.')
add_line('Воспитательная: содействовать воспитанию любознательности и уважения к '
         'природе родной страны посредством выполнения заданий.')
add_line('Планируемые результаты:', bold=True)
add_line('Предметные:', bold=True)
add_bullet('Знать понятия «рельеф», «равнина», «горы».')
add_bullet('Уметь находить и показывать на физической карте главнейшие равнины и горы России.')
add_bullet('Знать особенности Восточно-Европейской, Западно-Сибирской равнин, '
           'Среднесибирского плоскогорья, Уральских и Кавказских гор, Алтая, Саян.')
add_line('Метапредметные УУД:', bold=True)
add_line('Познавательные: находить согласно заданному алгоритму в предложенном источнике '
         'информацию, представленную в явном виде; формулировать (с помощью учителя) цель.')
add_line('Регулятивные: планировать действия по решению учебной задачи для получения '
         'результата; устанавливать причины успеха/неудач учебной деятельности.')
add_line('Коммуникативные: проявлять уважительное отношение к собеседнику; '
         'соблюдать правила ведения диалога и работы в парах.')
add_line('Личностный результат: формировать любознательность и самостоятельность '
         'в познании, интерес к природе Родины.')
add_line('Форма работы: фронтальная, индивидуальная, парная.')
add_line('Дидактические средства: учебник «Окружающий мир. 4 класс» А. А. Плешаков, '
         'Е. А. Крючкова, с. 44–47; компьютер, презентация, рабочий лист, физическая карта России.')
add_line('Оформление доски: тема урока, физическая карта России, ключевые понятия '
         '(рельеф, равнина, горы).')
add_line('')
add_line('СОДЕРЖАНИЕ ЭТАПОВ УРОКА', bold=True, size=13, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6)

stages = [
    dict(stage='Организационный момент', time='1 мин',
         teacher=['- Здравствуйте, ребята! Меня зовут Полина Игоревна, сегодня я проведу у вас урок.',
                  '- Проверьте свою готовность к уроку.'],
         student=['Приветствуют учителя.', 'Проверяют готовность к уроку.',
                  'Соблюдают правила посадки.'], slides=[1]),
    dict(stage='Этап мотивации (самоопределения) к учебной деятельности', time='1 мин',
         teacher=['- Начать наш урок я хочу с пословицы. Кто желает её прочитать?',
                  '- Как вы понимаете её смысл?', '- Спасибо.'],
         student=['Обучающиеся читают пословицу:',
                  '«Гора с горой не сходится, а человек с человеком сходится».',
                  'Объясняют её смысл (важно работать вместе, в парах).'], slides=[2]),
    dict(stage='Этап актуализации и фиксирование индивидуального затруднения в пробном действии',
         time='5 мин',
         teacher=['- Прежде чем приступить к изучению нового материала, давайте вспомним, '
                  'какие формы земной поверхности вы знаете.',
                  '- Назовите части холма и горы.'],
         student=['Слушают учителя.', 'Вспоминают формы рельефа: холм, гора, равнина, '
                  'овраг, долина.', 'Называют части холма и горы: подошва, склон, вершина.'],
         slides=[3]),
    dict(stage='Этап выявления места и причины затруднения', time='2 мин',
         teacher=['- Обратите внимание на слайд. Прочитайте, как называется эта карта?',
                  '- Верно, «Физическая карта России». Что на ней обозначено?',
                  '- Сможете ли вы назвать и показать равнины и горы?' ],
         student=['Читают название карты.', 'Отвечают, что на карте обозначены равнины '
                  'и горы.', 'Испытывают затруднение: не знают всех названий и особенностей.'],
         slides=[4]),
    dict(stage='Этап построения проекта выхода из затруднения', time='2 мин',
         teacher=['- Чтобы узнать тему урока, давайте посмотрим на слайд. Прочитайте её.',
                  '- Какую цель мы перед собой поставим?', '- Составим план работы.'],
         student=['Тема урока: «Равнины и горы России».',
                  'Цель: узнать об основных формах земной поверхности России и научиться '
                  'показывать их на карте.', 'Составляют план урока.'], slides=[5, 6]),
    dict(stage='Этап реализации построенного проекта / Физкультминутка', time='15 мин / 2 мин',
         teacher=['- Итак, что такое рельеф? Прочитайте на слайде.',
                  '- Чем равнина отличается от гор? Рассмотрим физическую карту.',
                  '- Какие равнины и горы России вы узнали?', '- Физкультминутка.'],
         student=['Читают со слайда, дополняют определения.',
                  'Рассматривают карту, называют Восточно-Европейскую и Западно-Сибирскую '
                  'равнины, Среднесибирское плоскогорье, Уральские и Кавказские горы, '
                  'Алтай, Саяны.', 'Выполняют физкультминутку.'], slides=[7, 8, 9, 10]),
    dict(stage='Этап первичного закрепления с проговариванием во внешней речи', time='5 мин',
         teacher=['- Мы с вами узнали, что равнины бывают плоскими и холмистыми, '
                  'а горы различаются по высоте.',
                  '- Работаем в парах. Вспомним правила работы.', '- Проверьте себя.'],
         student=['Называют признаки равнин и гор.', 'Работают в парах по правилам.',
                  'Отвечают на вопросы, обосновывают ответы.'], slides=[11, 12]),
    dict(stage='Этап самостоятельной работы с самопроверкой по эталону', time='5 мин',
         teacher=['- Откройте рабочий лист (Приложение 1).',
                  '1. Исправьте ошибки в тексте. 2. Заполните таблицу «Рельеф России». '
                  '3. Пройдите тест.', '- Проверьте работу соседа по парте.'],
         student=['Выполняют задания рабочего листа.',
                  'Меняются работами, проверяют соседа по парте, сверяют ответы с эталоном.'],
         slides=[13]),
    dict(stage='Этап включения в систему знаний и повторения', time='3 мин',
         teacher=['- Ребята, наш урок подходит к концу.',
                  '- Давайте вспомним тему и цель урока.',
                  '- Назовите главные равнины и горы России.'],
         student=['Тема: «Равнины и горы России».',
                  'Цель: узнать о равнинах и горах, научиться показывать их на карте.',
                  'Называют объекты и их особенности.'], slides=[16]),
    dict(stage='Домашнее задание', time='2 мин',
         teacher=['- Открываем дневники и записываем домашнее задание.',
                  '1. Учебник: с. 44–47, пересказ по вопросам рубрики «Проверь себя».',
                  '2. Рабочий лист: задания на выбор.'],
         student=['Записывают домашнее задание.', 'Задают вопросы.'], slides=[14]),
    dict(stage='Этап рефлексии учебной деятельности на уроке', time='1 мин',
         teacher=['- Наш урок подходит к концу. В пункте 5 рабочего листа нарисуйте '
                  'смайлик, который отражает ваше настроение на уроке.',
                  '- До свидания!'],
         student=['Оценивают работу на уроке.', 'Прощаются с учителем.'], slides=[15]),
]

table = doc.add_table(rows=1, cols=4)
table.style = 'Table Grid'
table.alignment = WD_TABLE_ALIGNMENT.CENTER
widths = [Mm(48), Mm(16), Mm(120), Mm(83)]
hdr = table.rows[0].cells
for i, txt in enumerate(['Этапы урока', 'Время', 'Деятельность учителя', 'Деятельность учащихся']):
    hdr[i].text = ''
    p = hdr[i].paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(txt)
    r.bold = True
    r.font.size = Pt(11)
    r.font.name = 'Times New Roman'

def set_cell_borders(cell):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement('w:tcBorders')
    for edge in ('top', 'left', 'bottom', 'right'):
        el = OxmlElement('w:' + edge)
        el.set(qn('w:val'), 'single')
        el.set(qn('w:sz'), '4')
        borders.append(el)
    tcPr.append(borders)

def fill_cell(cell, lines, slides_nums=None, center=False):
    cell.text = ''
    for j, line in enumerate(lines):
        p = cell.paragraphs[0] if j == 0 else cell.add_paragraph()
        if center:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2)
        r = p.add_run(line)
        r.font.name = 'Times New Roman'
        r.font.size = Pt(10.5)
    if slides_nums:
        for sn in slides_nums:
            p = cell.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(3)
            p.paragraph_format.space_after = Pt(3)
            p.add_run().add_picture(os.path.join(SLIDES, f'slide{sn:02d}.png'), width=Inches(2.15))

for s in stages:
    cells = table.add_row().cells
    fill_cell(cells[0], [s['stage']])
    fill_cell(cells[1], [s['time']], center=True)
    fill_cell(cells[2], s['teacher'], s['slides'])
    fill_cell(cells[3], s['student'])

for row in table.rows:
    for i, cell in enumerate(row.cells):
        cell.width = widths[i]
        set_cell_borders(cell)

# Appendix on a new portrait page
new_sec = doc.add_section(WD_SECTION.NEW_PAGE)
new_sec.orientation = WD_ORIENT.PORTRAIT
new_sec.page_width, new_sec.page_height = Mm(210), Mm(297)
new_sec.left_margin = new_sec.right_margin = Mm(15)
new_sec.top_margin = new_sec.bottom_margin = Mm(15)
add_line('ПРИЛОЖЕНИЕ', bold=True, size=13, align=WD_ALIGN_PARAGRAPH.CENTER)
add_line('Приложение 1. Рабочий лист по теме «Равнины и горы России»', bold=True, size=12)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.add_run().add_picture(WS, width=Inches(6.3))

docx_path = os.path.join(OUT, 'Конспект_урока_Равнины_и_горы_России_4б.docx')
doc.save(docx_path)
print('docx saved:', docx_path)
