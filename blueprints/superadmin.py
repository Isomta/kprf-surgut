import os
from datetime import datetime

from flask import (Blueprint, current_app, flash, jsonify, redirect,
                   render_template, request, url_for)
from flask_login import current_user, login_required
from werkzeug.security import generate_password_hash
from werkzeug.utils import secure_filename

# === Добавлены CampaignPoint и Appeal ===
from models import (AddressBoundary, Appeal, CampaignPoint, Deputat,
                    TopicStats, db)

superadmin_bp = Blueprint('superadmin', __name__)

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def is_super_admin(user):
    return user and user.user_id == 100


@superadmin_bp.route('/super-admin')
@login_required
def super_admin_panel():
    if not is_super_admin(current_user):
        flash('Доступ только у главного администратора')
        return redirect(url_for('admin.admin_panel'))

    deputats = Deputat.query.all()
    addresses = AddressBoundary.query.all()
    topics = TopicStats.query.all()
    # === Добавлена загрузка новых таблиц ===
    appeals = Appeal.query.all()
    campaigns = CampaignPoint.query.all()
    
    return render_template('admin_db.html', 
                           deputats=deputats, 
                           addresses=addresses, 
                           topics=topics, 
                           appeals=appeals, 
                           campaigns=campaigns)

# ========== ДЕПУТАТЫ ==========

@superadmin_bp.route('/super-admin/deputat', methods=['POST'])
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
            fio=data['fio'], birth_date=data.get('birth_date', ''),
            education=data.get('education', ''), experience=data.get('experience', ''),
            reception_address=data.get('reception_address', ''),
            phone=data.get('phone', ''), email=data.get('email', ''),
            uchastok=data['uchastok'],
            biography=data.get('biography', '')  # === Добавлено поле биографии ===
        )
        db.session.add(deputat)
        db.session.commit()
        return jsonify({'success': True, 'id': deputat.id})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/deputat/<int:deputat_id>', methods=['PUT'])
@login_required
def update_deputat(deputat_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    deputat = Deputat.query.get_or_404(deputat_id)
    data = request.json
    try:
        if 'fio' in data: deputat.fio = data['fio']
        if 'birth_date' in data: deputat.birth_date = data['birth_date']
        if 'education' in data: deputat.education = data['education']
        if 'experience' in data: deputat.experience = data['experience']
        if 'reception_address' in data: deputat.reception_address = data['reception_address']
        if 'phone' in data: deputat.phone = data['phone']
        if 'email' in data: deputat.email = data['email']
        if 'uchastok' in data: deputat.uchastok = data['uchastok']
        if 'biography' in data: deputat.biography = data['biography']  # === Биография ===

        if 'password' in data and data['password'].strip():
            deputat.password_hash = generate_password_hash(data['password'])

        db.session.commit()
        return jsonify({'success': True})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/deputat/<int:deputat_id>', methods=['DELETE'])
@login_required
def delete_deputat(deputat_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    deputat = Deputat.query.get_or_404(deputat_id)
    if deputat.user_id == 100:  # Исправлено: 100 вместо 1
        return jsonify({'error': 'Нельзя удалить главного администратора'}), 400
    db.session.delete(deputat)
    db.session.commit()
    return jsonify({'success': True})


@superadmin_bp.route('/super-admin/deputat/<int:deputat_id>/photo', methods=['POST'])
@login_required
def upload_photo(deputat_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    deputat = Deputat.query.get_or_404(deputat_id)
    if 'photo' not in request.files:
        return jsonify({'error': 'Нет файла'}), 400
    file = request.files['photo']
    if file.filename == '':
        return jsonify({'error': 'Файл не выбран'}), 400
    if file and allowed_file(file.filename):
        filename = secure_filename(f"deputat_{deputat_id}_{file.filename}")
        upload_folder = os.path.join(current_app.root_path, 'static', 'photos')
        os.makedirs(upload_folder, exist_ok=True)
        filepath = os.path.join(upload_folder, filename)
        file.save(filepath)
        deputat.photo = f'/static/photos/{filename}'
        db.session.commit()
        return jsonify({'success': True, 'photo_url': deputat.photo})
    return jsonify({'error': 'Неподдерживаемый формат. Используйте PNG, JPG, JPEG, GIF'}), 400

# ========== АДРЕСА ==========

@superadmin_bp.route('/super-admin/address', methods=['POST'])
@login_required
def add_address():
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    data = request.json
    try:
        address = AddressBoundary(
            uchastok=data['uchastok'], street=data['street'], house_number=data['house_number'])
        db.session.add(address)
        db.session.commit()
        return jsonify({'success': True, 'id': address.id})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/address/<int:address_id>', methods=['PUT'])
@login_required
def update_address(address_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    address = AddressBoundary.query.get_or_404(address_id)
    data = request.json
    try:
        if 'uchastok' in data: address.uchastok = data['uchastok']
        if 'street' in data: address.street = data['street']
        if 'house_number' in data: address.house_number = data['house_number']
        db.session.commit()
        return jsonify({'success': True})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/address/<int:address_id>', methods=['DELETE'])
@login_required
def delete_address(address_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    address = AddressBoundary.query.get_or_404(address_id)
    db.session.delete(address)
    db.session.commit()
    return jsonify({'success': True})

# ========== ТЕМЫ ==========

@superadmin_bp.route('/super-admin/topic', methods=['POST'])
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
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/topic/<int:topic_id>', methods=['PUT'])
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
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/topic/<int:topic_id>', methods=['DELETE'])
@login_required
def delete_topic(topic_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    topic = TopicStats.query.get_or_404(topic_id)
    db.session.delete(topic)
    db.session.commit()
    return jsonify({'success': True})

# ========== ИНИЦИАТИВЫ (CampaignPoints) ==========

@superadmin_bp.route('/super-admin/campaign', methods=['POST'])
@login_required
def add_campaign():
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    data = request.json
    try:
        campaign = CampaignPoint(
            deputat_id=data['deputat_id'],
            text=data['text'],
            votes_for=data.get('votes_for', 0),
            votes_against=data.get('votes_against', 0)
        )
        db.session.add(campaign)
        db.session.commit()
        return jsonify({'success': True, 'id': campaign.id})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/campaign/<int:campaign_id>', methods=['PUT'])
@login_required
def update_campaign(campaign_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    campaign = CampaignPoint.query.get_or_404(campaign_id)
    data = request.json
    try:
        if 'deputat_id' in data: campaign.deputat_id = data['deputat_id']
        if 'text' in data: campaign.text = data['text']
        if 'votes_for' in data: campaign.votes_for = data['votes_for']
        if 'votes_against' in data: campaign.votes_against = data['votes_against']
        db.session.commit()
        return jsonify({'success': True})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/campaign/<int:campaign_id>', methods=['DELETE'])
@login_required
def delete_campaign(campaign_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    campaign = CampaignPoint.query.get_or_404(campaign_id)
    db.session.delete(campaign)
    db.session.commit()
    return jsonify({'success': True})

# ========== ОБРАЩЕНИЯ (Appeals) ==========

@superadmin_bp.route('/super-admin/appeal', methods=['POST'])
@login_required
def add_appeal():
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    data = request.json
    try:
        appeal = Appeal(
            uchastok=data['uchastok'],
            topic=data['topic'],
            text=data['text'],
            fio=data.get('fio'),
            phone=data.get('phone'),
            email=data.get('email'),
            need_visit=data.get('need_visit', False),
            status=data.get('status', 'Новое'),
            status_date=datetime.now()
        )
        db.session.add(appeal)
        db.session.commit()
        return jsonify({'success': True, 'id': appeal.id})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/appeal/<int:appeal_id>', methods=['PUT'])
@login_required
def update_appeal(appeal_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    appeal = Appeal.query.get_or_404(appeal_id)
    data = request.json
    try:
        if 'uchastok' in data: appeal.uchastok = data['uchastok']
        if 'topic' in data: appeal.topic = data['topic']
        if 'text' in data: appeal.text = data['text']
        if 'fio' in data: appeal.fio = data['fio']
        if 'phone' in data: appeal.phone = data['phone']
        if 'email' in data: appeal.email = data['email']
        if 'need_visit' in data: appeal.need_visit = data['need_visit']
        
        if 'status' in data:
            if appeal.status != data['status']:
                appeal.status_date = datetime.now()
            appeal.status = data['status']
            
        if 'result_text' in data: appeal.result_text = data['result_text']
        db.session.commit()
        return jsonify({'success': True})
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 400


@superadmin_bp.route('/super-admin/appeal/<int:appeal_id>', methods=['DELETE'])
@login_required
def delete_appeal(appeal_id):
    if not is_super_admin(current_user):
        return jsonify({'error': 'Доступ запрещен'}), 403
    appeal = Appeal.query.get_or_404(appeal_id)
    db.session.delete(appeal)
    db.session.commit()
    return jsonify({'success': True})