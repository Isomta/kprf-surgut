from app import app
from models import db, Deputat
import hashlib


def init_database():
    with app.app_context():
        print("🔄 Создание таблиц базы данных...")
        db.create_all()
        print("✅ Таблицы созданы")

        # Создаем суперадмина (ID 100)
        super_admin = Deputat.query.filter_by(user_id=100).first()
        if not super_admin:
            admin = Deputat(
                user_id=100,
                password_hash=hashlib.md5('admin123'.encode()).hexdigest(),
                fio='Системный администратор',
                birth_date='01.01.1980',
                education='Высшее',
                experience='15 лет',
                reception_address='г. Москва, Кремль',
                phone='+7 (495) 111-11-11',
                email='admin@deputat.ru',
                uchastok=0
            )
            db.session.add(admin)
            db.session.commit()
            print("✅ Создан супер-администратор (ID: 100, пароль: admin123)")
        else:
            print("✅ Супер-администратор уже существует")

        print("\n📊 Текущее состояние БД:")
        print(f"  - Депутатов: {Deputat.query.count()}")


if __name__ == '__main__':
    init_database()
