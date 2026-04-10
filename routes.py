from flask import render_template, request, jsonify, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from models import db, Deputat, AddressBoundary, Appeal, TopicStats
from datetime import datetime
import hashlib
from werkzeug.security import generate_password_hash

# ========== ПУБЛИЧНЫЕ МАРШРУТЫ ==========


def init_routes(app):

    @app.route('/')
    def index():
        return render_template('index.html')

    @app.route('/api/deputat_by_address', methods=['POST'])
    def get_deputat_by_address():
        data = request.json
        street = data.get('street', '').strip()
        house = data.get('house', '').strip()
        boundary = AddressBoundary.query.filter_by(
            street=street, house_number=house).first()
        if not boundary:
            return jsonify({'error': 'Адрес не найден в границах избирательных участков'}), 404
        deputat = Deputat.query.filter_by(uchastok=boundary.uchastok).first()
        if not deputat:
            return jsonify({'error': 'Депутат не назначен для этого участка'}), 404
        appeals = Appeal.query.filter_by(uchastok=deputat.uchastok).all()
        stats = {
            'total': len(appeals),
            'new': len([a for a in appeals if a.status == 'Новое']),
            'in_work': len([a for a in appeals if a.status == 'В работе']),
            'completed': len([a for a in appeals if a.status == 'Выполнено']),
            'rejected': len([a for a in appeals if a.status == 'Отказано'])
        }
        topics_stats = {}
        for appeal in appeals:
            topics_stats[appeal.topic] = topics_stats.get(appeal.topic, 0) + 1
        return jsonify({
            'deputat': {
                'id': deputat.user_id,
                'fio': deputat.fio,
                'birth_date': deputat.birth_date,
                'education': deputat.education,
                'experience': deputat.experience,
                'reception_address': deputat.reception_address,
                'phone': deputat.phone,
                'email': deputat.email,
                'uchastok': deputat.uchastok
            },
            'stats': stats,
            'topics_stats': topics_stats,
            'address': f"{street}, {house}"
        })

    @app.route('/api/create_appeal', methods=['POST'])
    def create_appeal():
        data = request.json
        street = data.get('street')
        house = data.get('house')
        boundary = AddressBoundary.query.filter_by(
            street=street, house_number=house).first()
        if not boundary:
            return jsonify({'error': 'Адрес не найден'}), 400
        appeal = Appeal(
            uchastok=boundary.uchastok,
            topic=data.get('topic'),
            text=data.get('text'),
            fio=data.get('fio', ''),
            phone=data.get('phone', ''),
            email=data.get('email', ''),
            need_visit=data.get('need_visit', False),
            status='Новое',
            status_date=datetime.now()
        )
        db.session.add(appeal)
        db.session.commit()
        return jsonify({'success': True, 'appeal_id': appeal.id})

    @app.route('/api/topics')
    def get_topics():
        topics = TopicStats.query.all()
        return jsonify([t.topic_name for t in topics])

    @app.route('/api/streets')
    def get_streets():
        streets = db.session.query(AddressBoundary.street).distinct().all()
        return jsonify([s[0] for s in streets])

    @app.route('/api/houses/<street>')
    def get_houses(street):
        houses = db.session.query(
            AddressBoundary.house_number).filter_by(street=street).all()
        return jsonify([h[0] for h in houses])

    # ========== АДМИН-ПАНЕЛЬ ДЕПУТАТА ==========

    @app.route('/admin/login', methods=['GET', 'POST'])
    def admin_login():
        if request.method == 'POST':
            user_id = request.form.get('user_id')
            password = request.form.get('password')
            deputat = Deputat.query.filter_by(user_id=user_id).first()
            if deputat and hashlib.md5(password.encode()).hexdigest() == deputat.password_hash:
                login_user(deputat)
                return redirect(url_for('admin_panel'))
            else:
                flash('Неверный ID или пароль')
        return '''
        <!DOCTYPE html>
        <html>
        <head><title>Вход для депутата</title>
        <style>
            body{font-family:Arial;display:flex;justify-content:center;align-items:center;height:100vh;background:#f0f0f0;}
            .login-form{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:300px;}
            input{width:100%;padding:8px;margin:10px 0;border:1px solid #ddd;border-radius:4px;}
            button{width:100%;padding:10px;background:#3498db;color:white;border:none;border-radius:4px;cursor:pointer;}
            button:hover{background:#2980b9;}
        </style>
        </head>
        <body>
            <div class="login-form">
                <h3>Вход в систему</h3>
                <form method="post">
                    <input type="text" name="user_id" placeholder="ID депутата (1-15)" required>
                    <input type="password" name="password" placeholder="Пароль" required>
                    <button type="submit">Войти</button>
                </form>
                <p style="margin-top:15px;font-size:12px;color:#666;">Демо-пароль: pass123</p>
            </div>
        </body>
        </html>
        '''

    @app.route('/admin/logout')
    @login_required
    def admin_logout():
        logout_user()
        return redirect(url_for('index'))

    @app.route('/admin')
    @login_required
    def admin_panel():
        appeals = Appeal.query.filter_by(uchastok=current_user.uchastok).order_by(
            Appeal.created_at.desc()).all()
        return render_template('admin.html', appeals=appeals, deputat=current_user)

    @app.route('/admin/update_appeal/<int:appeal_id>', methods=['POST'])
    @login_required
    def update_appeal(appeal_id):
        appeal = Appeal.query.get_or_404(appeal_id)
        if appeal.uchastok != current_user.uchastok:
            return jsonify({'error': 'Доступ запрещен'}), 403
        data = request.json
        appeal.status = data.get('status', appeal.status)
        appeal.status_date = datetime.now()
        appeal.result_text = data.get('result_text', appeal.result_text)
        db.session.commit()
        return jsonify({'success': True})

    # ========== СУПЕР-АДМИН (УПРАВЛЕНИЕ БД) ==========

    def is_super_admin(user):
        return user and user.user_id == 100

    @app.route('/super-admin')
    @login_required
    def super_admin_panel():
        if not is_super_admin(current_user):
            flash('Доступ только у главного администратора')
            return redirect(url_for('admin_panel'))

        deputats = Deputat.query.all()
        addresses = AddressBoundary.query.all()
        topics = TopicStats.query.all()
        return render_template('admin_db.html', deputats=deputats, addresses=addresses, topics=topics)

    # API для управления депутатами
    @app.route('/super-admin/deputat', methods=['POST'])
    @login_required
    def add_deputat():
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        data = request.json
        try:
            if Deputat.query.filter_by(uchastok=data['uchastok']).first():
                return jsonify({'error': 'Депутат с таким участком уже существует'}), 400

            deputat = Deputat(
                user_id=data['user_id'],
                password_hash=generate_password_hash(data['password']),
                fio=data['fio'],
                birth_date=data.get('birth_date', ''),
                education=data.get('education', ''),
                experience=data.get('experience', ''),
                reception_address=data.get('reception_address', ''),
                phone=data.get('phone', ''),
                email=data.get('email', ''),
                uchastok=data['uchastok']
            )
            db.session.add(deputat)
            db.session.commit()
            return jsonify({'success': True, 'id': deputat.id})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/deputat/<int:deputat_id>', methods=['PUT'])
    @login_required
    def update_deputat(deputat_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        deputat = Deputat.query.get_or_404(deputat_id)
        data = request.json
        try:
            if 'fio' in data:
                deputat.fio = data['fio']
            if 'birth_date' in data:
                deputat.birth_date = data['birth_date']
            if 'education' in data:
                deputat.education = data['education']
            if 'experience' in data:
                deputat.experience = data['experience']
            if 'reception_address' in data:
                deputat.reception_address = data['reception_address']
            if 'phone' in data:
                deputat.phone = data['phone']
            if 'email' in data:
                deputat.email = data['email']
            if 'uchastok' in data:
                deputat.uchastok = data['uchastok']
            if 'password' in data and data['password']:
                deputat.password_hash = generate_password_hash(
                    data['password'])
            db.session.commit()
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/deputat/<int:deputat_id>', methods=['DELETE'])
    @login_required
    def delete_deputat(deputat_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        deputat = Deputat.query.get_or_404(deputat_id)
        if deputat.user_id == 1:
            return jsonify({'error': 'Нельзя удалить главного администратора'}), 400

        db.session.delete(deputat)
        db.session.commit()
        return jsonify({'success': True})

    # API для управления адресами
    @app.route('/super-admin/address', methods=['POST'])
    @login_required
    def add_address():
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        data = request.json
        try:
            address = AddressBoundary(
                uchastok=data['uchastok'],
                street=data['street'],
                house_number=data['house_number']
            )
            db.session.add(address)
            db.session.commit()
            return jsonify({'success': True, 'id': address.id})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/address/<int:address_id>', methods=['PUT'])
    @login_required
    def update_address(address_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        address = AddressBoundary.query.get_or_404(address_id)
        data = request.json
        try:
            if 'uchastok' in data:
                address.uchastok = data['uchastok']
            if 'street' in data:
                address.street = data['street']
            if 'house_number' in data:
                address.house_number = data['house_number']
            db.session.commit()
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/address/<int:address_id>', methods=['DELETE'])
    @login_required
    def delete_address(address_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        address = AddressBoundary.query.get_or_404(address_id)
        db.session.delete(address)
        db.session.commit()
        return jsonify({'success': True})

    # API для управления темами
    @app.route('/super-admin/topic', methods=['POST'])
    @login_required
    def add_topic():
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        data = request.json
        try:
            topic = TopicStats(topic_name=data['topic_name'])
            db.session.add(topic)
            db.session.commit()
            return jsonify({'success': True, 'id': topic.id})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/topic/<int:topic_id>', methods=['PUT'])
    @login_required
    def update_topic(topic_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        topic = TopicStats.query.get_or_404(topic_id)
        data = request.json
        try:
            topic.topic_name = data['topic_name']
            db.session.commit()
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 400

    @app.route('/super-admin/topic/<int:topic_id>', methods=['DELETE'])
    @login_required
    def delete_topic(topic_id):
        if not is_super_admin(current_user):
            return jsonify({'error': 'Доступ запрещен'}), 403

        topic = TopicStats.query.get_or_404(topic_id)
        db.session.delete(topic)
        db.session.commit()
        return jsonify({'success': True})

    print("✅ Все маршруты зарегистрированы")
