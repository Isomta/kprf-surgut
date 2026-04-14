"""
Конфигурация визуальной темы проекта
Изменяйте значения ниже — стили обновятся автоматически после перезагрузки страницы
"""

# === ЦВЕТОВАЯ ТЕМА ===
# Основной цвет (кнопки, ссылки, акценты)
COLOR_PRIMARY = '#C41E3A'          # Коммунистический красный
COLOR_PRIMARY_HOVER = '#A01830'    # Темнее при наведении
COLOR_PRIMARY_LIGHT = '#E84E66'    # Светлый вариант для фонов

# Текст на основном фоне
COLOR_TEXT_ON_PRIMARY = '#FFFFFF'  # Белый

# Ссылки
COLOR_LINK = '#C41E3A'
COLOR_LINK_HOVER = '#8B0000'

# Вторичные акценты (иконки, рамки)
COLOR_ACCENT = '#FFD700'           # Золотой (опционально)

# === ФОН ===
# Имя файла фона в папке static/
# Положите изображение в static/ и укажите его имя здесь
# Поддерживаются: .jpg, .jpeg, .png, .webp, .svg
BACKGROUND_IMAGE = 'bg-main.jpg'

# Настройки отображения фона
BACKGROUND_SIZE = 'cover'          # cover / contain / auto
BACKGROUND_POSITION = 'center'     # center / top / left / right
BACKGROUND_REPEAT = 'no-repeat'    # no-repeat / repeat / repeat-x / repeat-y
BACKGROUND_ATTACHMENT = 'fixed'    # fixed / scroll

# Затемнение фона для читаемости текста (0.0 = нет, 1.0 = чёрный)
BACKGROUND_OVERLAY = 'rgba(0, 0, 0, 0.3)'

# === ДОПОЛНИТЕЛЬНО ===
# Тёмная тема (экспериментально)
DARK_MODE_ENABLED = False
