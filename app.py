from routes import init_routes
from models import db, Deputat
from flask_login import LoginManager
from flask import Flask
import warnings
warnings.filterwarnings('ignore')


app = Flask(__name__)
app.config['SECRET_KEY'] = 'your-secret-key-change-it'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///deputat.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'admin_login'


@login_manager.user_loader
def load_user(user_id):
    return Deputat.query.get(int(user_id))


# Регистрируем все маршруты
init_routes(app)

if __name__ == '__main__':
    print("\n🚀 Запуск сервера на http://localhost:8080")
    app.run(debug=True, port=8080, host='0.0.0.0')
