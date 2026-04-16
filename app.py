import os

from dotenv import load_dotenv
from flask import Flask
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_wtf import CSRFProtect

from blueprints.admin import admin_bp
from blueprints.auth import auth_bp
from blueprints.public import public_bp
from blueprints.superadmin import superadmin_bp
# Импорт конфигурации темы
from config import (BACKGROUND_ATTACHMENT, BACKGROUND_IMAGE,
                    BACKGROUND_OVERLAY, BACKGROUND_POSITION, BACKGROUND_REPEAT,
                    BACKGROUND_SIZE, COLOR_ACCENT, COLOR_LINK,
                    COLOR_LINK_HOVER, COLOR_PRIMARY, COLOR_PRIMARY_HOVER,
                    COLOR_PRIMARY_LIGHT, COLOR_TEXT_ON_PRIMARY)
from models import Deputat, db

load_dotenv()


def create_app():
    app = Flask(__name__)

    # === Конфигурация из переменных окружения ===
    app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'fallback-key')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['WTF_CSRF_CHECK_DEFAULT'] = False

    # === Умная конфигурация БД: SQLite локально, PostgreSQL на сервере ===
    database_url = os.environ.get('DATABASE_URL', 'sqlite:///deputat.db')

    if database_url.startswith('sqlite'):
        app.config['SQLALCHEMY_DATABASE_URI'] = database_url
    else:
        if 'postgresql' in database_url and 'postgresql+psycopg2' not in database_url:
            database_url = database_url.replace(
                'postgresql://', 'postgresql+psycopg2://', 1)
        app.config['SQLALCHEMY_DATABASE_URI'] = database_url

    # === Инициализация расширений ===
    db.init_app(app)
    migrate = Migrate(app, db)

    login_manager = LoginManager()
    login_manager.init_app(app)
    login_manager.login_view = 'auth.admin_login'

    csrf = CSRFProtect(app)

    # === Загрузка пользователя ===
    @login_manager.user_loader
    def load_user(user_id):
        return Deputat.query.get(int(user_id))

    # === Контекст-процессор: передача темы во ВСЕ шаблоны автоматически ===
    @app.context_processor
    def inject_theme():
        return {
            'theme': {
                'color_primary': COLOR_PRIMARY,
                'color_primary_hover': COLOR_PRIMARY_HOVER,
                'color_primary_light': COLOR_PRIMARY_LIGHT,
                'color_text_on_primary': COLOR_TEXT_ON_PRIMARY,
                'color_link': COLOR_LINK,
                'color_link_hover': COLOR_LINK_HOVER,
                'color_accent': COLOR_ACCENT,
                'bg_image': BACKGROUND_IMAGE,
                'bg_size': BACKGROUND_SIZE,
                'bg_position': BACKGROUND_POSITION,
                'bg_repeat': BACKGROUND_REPEAT,
                'bg_attachment': BACKGROUND_ATTACHMENT,
                'bg_overlay': BACKGROUND_OVERLAY
            }
        }

    # === Регистрация маршрутов ===
    app.register_blueprint(public_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(superadmin_bp)

    return app


# Создаём экземпляр приложения
app = create_app()

if __name__ == '__main__':
    print("\n🚀 Запуск сервера на http://localhost:8080")
    app.run(debug=True, port=8080, host='0.0.0.0')
