from app import app
from models import db, Deputat, AddressBoundary, TopicStats, Appeal
from openpyxl import load_workbook
import hashlib
from datetime import datetime


def load_excel_data():
    with app.app_context():
        print("🔄 Загрузка данных из Excel...")

        try:
            wb = load_workbook('data.xlsx', data_only=True)
        except FileNotFoundError:
            print("❌ Файл data.xlsx не найден!")
            return
        except Exception as e:
            print(f"❌ Ошибка загрузки файла: {e}")
            return

        # ========== 1. Загрузка депутатов ==========
        print("\n📋 Загрузка депутатов...")
        sheet_dep = wb['Депутаты']
        deputats_count = 0

        for row in range(5, sheet_dep.max_row + 1):
            id_val = sheet_dep.cell(row=row, column=3).value  # id
            if not id_val:
                continue

            try:
                user_id = int(id_val)
                # Пропускаем суперадмина (100)
                if user_id == 100:
                    continue

                uchastok = int(sheet_dep.cell(
                    row=row, column=4).value)  # Участок
                fio = str(sheet_dep.cell(row=row, column=5).value) if sheet_dep.cell(
                    row=row, column=5).value else ''
                birth_date = str(sheet_dep.cell(row=row, column=6).value) if sheet_dep.cell(
                    row=row, column=6).value else ''
                education = str(sheet_dep.cell(row=row, column=7).value) if sheet_dep.cell(
                    row=row, column=7).value else ''
                experience = str(sheet_dep.cell(row=row, column=8).value) if sheet_dep.cell(
                    row=row, column=8).value else ''
                reception_address = str(sheet_dep.cell(
                    row=row, column=9).value) if sheet_dep.cell(row=row, column=9).value else ''
                phone = str(sheet_dep.cell(row=row, column=10).value) if sheet_dep.cell(
                    row=row, column=10).value else ''
                email = str(sheet_dep.cell(row=row, column=11).value) if sheet_dep.cell(
                    row=row, column=11).value else ''

                # Проверяем, существует ли уже депутат
                existing = Deputat.query.filter_by(user_id=user_id).first()
                if existing:
                    # Обновляем существующего
                    existing.fio = fio
                    existing.birth_date = birth_date
                    existing.education = education
                    existing.experience = experience
                    existing.reception_address = reception_address
                    existing.phone = phone
                    existing.email = email
                    existing.uchastok = uchastok
                    print(f"  ✏️ Обновлен депутат ID {user_id}: {fio}")
                else:
                    # Создаем нового
                    deputat = Deputat(
                        user_id=user_id,
                        password_hash=hashlib.md5(
                            'pass123'.encode()).hexdigest(),
                        fio=fio,
                        birth_date=birth_date,
                        education=education,
                        experience=experience,
                        reception_address=reception_address,
                        phone=phone,
                        email=email,
                        uchastok=uchastok
                    )
                    db.session.add(deputat)
                    print(f"  ✅ Добавлен депутат ID {user_id}: {fio}")
                deputats_count += 1

            except Exception as e:
                print(f"  ❌ Ошибка в строке {row}: {e}")

        db.session.commit()
        print(f"📊 Загружено/обновлено депутатов: {deputats_count}")

        # ========== 2. Загрузка границ участков ==========
        print("\n📍 Загрузка адресов...")
        sheet_bound = wb['Границы ИУ']
        boundaries_count = 0

        for row in range(5, sheet_bound.max_row + 1):
            id_val = sheet_bound.cell(row=row, column=3).value
            if not id_val:
                continue

            try:
                uchastok = int(sheet_bound.cell(row=row, column=4).value)
                street = str(sheet_bound.cell(row=row, column=5).value).strip()
                house_number = str(sheet_bound.cell(
                    row=row, column=6).value).split('.')[0].strip()

                # Проверяем, существует ли уже такой адрес
                existing = AddressBoundary.query.filter_by(
                    street=street, house_number=house_number).first()
                if existing:
                    existing.uchastok = uchastok
                    print(
                        f"  ✏️ Обновлен адрес: {street} {house_number} -> уч. {uchastok}")
                else:
                    boundary = AddressBoundary(
                        uchastok=uchastok,
                        street=street,
                        house_number=house_number
                    )
                    db.session.add(boundary)
                    print(
                        f"  ✅ Добавлен адрес: {street} {house_number} -> уч. {uchastok}")
                boundaries_count += 1

            except Exception as e:
                print(f"  ❌ Ошибка в строке {row}: {e}")

        db.session.commit()
        print(f"📊 Загружено/обновлено адресов: {boundaries_count}")

        # ========== 3. Загрузка тем обращений ==========
        print("\n📝 Загрузка тем обращений...")
        sheet_topics = wb['Обр1']
        topics_count = 0

        # Начинаем с 8 строки (где начинаются темы)
        for row in range(8, sheet_topics.max_row + 1):
            topic_name = sheet_topics.cell(
                row=row, column=5).value  # колонка E
            if not topic_name:
                continue

            try:
                topic_name = str(topic_name).strip()
                existing = TopicStats.query.filter_by(
                    topic_name=topic_name).first()
                if not existing:
                    topic = TopicStats(topic_name=topic_name)
                    db.session.add(topic)
                    print(f"  ✅ Добавлена тема: {topic_name}")
                    topics_count += 1
                else:
                    print(f"  ⏭ Тема уже существует: {topic_name}")

            except Exception as e:
                print(f"  ❌ Ошибка в строке {row}: {e}")

        db.session.commit()
        print(f"📊 Добавлено новых тем: {topics_count}")

        # ========== 4. Загрузка обращений ==========
        print("\n📨 Загрузка обращений...")
        sheet_appeals = wb['Обращения']
        appeals_count = 0

        for row in range(5, sheet_appeals.max_row + 1):
            id_val = sheet_appeals.cell(row=row, column=3).value
            if not id_val:
                continue

            try:
                uchastok = int(sheet_appeals.cell(row=row, column=4).value)
                date_val = sheet_appeals.cell(row=row, column=5).value
                time_val = sheet_appeals.cell(row=row, column=6).value
                topic = str(sheet_appeals.cell(row=row, column=7).value) if sheet_appeals.cell(
                    row=row, column=7).value else ''
                text = str(sheet_appeals.cell(row=row, column=8).value) if sheet_appeals.cell(
                    row=row, column=8).value else ''
                fio = str(sheet_appeals.cell(row=row, column=9).value) if sheet_appeals.cell(
                    row=row, column=9).value else ''
                phone = str(sheet_appeals.cell(row=row, column=10).value) if sheet_appeals.cell(
                    row=row, column=10).value else ''
                email = str(sheet_appeals.cell(row=row, column=11).value) if sheet_appeals.cell(
                    row=row, column=11).value else ''
                need_visit = sheet_appeals.cell(
                    row=row, column=12).value == 'Да'
                status = str(sheet_appeals.cell(row=row, column=13).value) if sheet_appeals.cell(
                    row=row, column=13).value else 'Новое'
                status_date = sheet_appeals.cell(row=row, column=14).value
                result_text = str(sheet_appeals.cell(row=row, column=15).value) if sheet_appeals.cell(
                    row=row, column=15).value else ''

                if not topic or not text:
                    continue

                # Преобразуем дату
                if isinstance(date_val, datetime):
                    created_at = date_val
                elif date_val:
                    try:
                        created_at = datetime.strptime(
                            str(date_val), '%Y-%m-%d %H:%M:%S')
                    except:
                        created_at = datetime.now()
                else:
                    created_at = datetime.now()

                # Преобразуем дату статуса
                if isinstance(status_date, datetime):
                    status_date_obj = status_date
                elif status_date:
                    try:
                        status_date_obj = datetime.strptime(
                            str(status_date), '%Y-%m-%d')
                    except:
                        status_date_obj = datetime.now()
                else:
                    status_date_obj = datetime.now()

                # Проверяем, существует ли обращение
                existing = Appeal.query.filter_by(id=id_val).first()
                if existing:
                    existing.uchastok = uchastok
                    existing.topic = topic
                    existing.text = text
                    existing.fio = fio
                    existing.phone = phone
                    existing.email = email
                    existing.need_visit = need_visit
                    existing.status = status
                    existing.status_date = status_date_obj
                    existing.result_text = result_text
                    print(f"  ✏️ Обновлено обращение #{id_val}")
                else:
                    appeal = Appeal(
                        id=id_val,
                        uchastok=uchastok,
                        created_at=created_at,
                        topic=topic,
                        text=text,
                        fio=fio,
                        phone=phone,
                        email=email,
                        need_visit=need_visit,
                        status=status,
                        status_date=status_date_obj,
                        result_text=result_text
                    )
                    db.session.add(appeal)
                    print(
                        f"  ✅ Добавлено обращение #{id_val} от {fio or 'анонима'}")
                appeals_count += 1

            except Exception as e:
                print(f"  ❌ Ошибка в строке {row}: {e}")

        db.session.commit()
        print(f"📊 Загружено/обновлено обращений: {appeals_count}")

        # ========== ИТОГИ ==========
        print("\n" + "="*50)
        print("✅ ЗАГРУЗКА ДАННЫХ ЗАВЕРШЕНА!")
        print("="*50)
        print(f"📊 Депутатов: {Deputat.query.count()}")
        print(f"📊 Адресов: {AddressBoundary.query.count()}")
        print(f"📊 Тем: {TopicStats.query.count()}")
        print(f"📊 Обращений: {Appeal.query.count()}")
        print("="*50)


if __name__ == '__main__':
    load_excel_data()
