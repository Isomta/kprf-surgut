FROM python:3.11-slim

WORKDIR /app

# Копируем зависимости и устанавливаем их (кешируется Docker'ом)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копируем весь код
COPY . .

# Создаем папки для статики и БД (если их нет в репозитории)
RUN mkdir -p /app/instance /app/static/photos

EXPOSE 8080

# Запускаем через Gunicorn (производственный WSGI-сервер)
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "120", "app:app"]