from datetime import datetime

from flask import Blueprint, jsonify, render_template, request

from models import AddressBoundary, Appeal, Deputat, TopicStats, db, CampaignPoint
from flask import session
public_bp = Blueprint('public', __name__)


@public_bp.route('/')
def index():
    return render_template('index.html')


@public_bp.route('/api/deputat_by_address', methods=['POST'])
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
            'id': deputat.user_id, 'fio': deputat.fio, 'birth_date': deputat.birth_date,
            'education': deputat.education, 'experience': deputat.experience,
            'reception_address': deputat.reception_address, 'phone': deputat.phone,
            'email': deputat.email, 'uchastok': deputat.uchastok,
            'photo': deputat.photo if hasattr(deputat, 'photo') else '/static/photos/default.png'
        },
        'stats': stats,
        'topics_stats': topics_stats,
        'address': f"{street}, {house}"
    })


@public_bp.route('/api/deputat/<int:deputat_id>')
def get_deputat_by_id(deputat_id):
    deputat = Deputat.query.filter_by(user_id=deputat_id).first()
    if not deputat:
        return jsonify({'error': 'Депутат не найден'}), 404

    appeals = Appeal.query.filter_by(uchastok=deputat.uchastok).all()
    stats = {
        'total': len(appeals), 'new': len([a for a in appeals if a.status == 'Новое']),
        'in_work': len([a for a in appeals if a.status == 'В работе']),
        'completed': len([a for a in appeals if a.status == 'Выполнено']),
        'rejected': len([a for a in appeals if a.status == 'Отказано'])
    }
    topics_stats = {}
    for appeal in appeals:
        topics_stats[appeal.topic] = topics_stats.get(appeal.topic, 0) + 1

    return jsonify({
        'deputat': {
            'id': deputat.user_id, 'fio': deputat.fio, 'birth_date': deputat.birth_date,
            'education': deputat.education, 'experience': deputat.experience,
            'reception_address': deputat.reception_address, 'phone': deputat.phone,
            'email': deputat.email, 'uchastok': deputat.uchastok,
            'photo': deputat.photo or '/static/photos/default.png'
        },
        'stats': stats,
        'topics_stats': topics_stats
    })


@public_bp.route('/api/create_appeal', methods=['POST'])
def create_appeal():
    data = request.json
    street = data.get('street')
    house = data.get('house')
    boundary = AddressBoundary.query.filter_by(
        street=street, house_number=house).first()
    if not boundary:
        return jsonify({'error': 'Адрес не найден'}), 400
    appeal = Appeal(
        uchastok=boundary.uchastok, topic=data.get('topic'), text=data.get('text'),
        fio=data.get('fio', ''), phone=data.get('phone', ''), email=data.get('email', ''),
        need_visit=data.get('need_visit', False), status='Новое', status_date=datetime.now()
    )
    db.session.add(appeal)
    db.session.commit()
    return jsonify({'success': True, 'appeal_id': appeal.id})


@public_bp.route('/api/topics')
def get_topics():
    topics = TopicStats.query.all()
    return jsonify([t.topic_name for t in topics])


@public_bp.route('/api/streets')
def get_streets():
    streets = db.session.query(AddressBoundary.street).distinct().all()
    return jsonify([s[0] for s in streets])


@public_bp.route('/api/houses/<street>')
def get_houses(street):
    houses = db.session.query(
        AddressBoundary.house_number).filter_by(street=street).all()
    return jsonify([h[0] for h in houses])


@public_bp.route('/deputats')
def public_deputats():
    deputats = Deputat.query.order_by(Deputat.uchastok).all()
    return render_template('deputats.html', deputats=deputats)


@public_bp.route('/api/deputats_all')
def get_all_deputats_public():
    deputats = Deputat.query.all()
    return jsonify([{
        'user_id': d.user_id, 'fio': d.fio, 'uchastok': d.uchastok,
        'photo': d.photo or '/static/photos/default.png', 'birth_date': d.birth_date,
        'education': d.education, 'experience': d.experience,
        'reception_address': d.reception_address, 'phone': d.phone, 'email': d.email
    } for d in deputats])


@public_bp.route('/api/deputat/<int:user_id>/details')
def get_deputat_details(user_id):
    deputat = Deputat.query.filter_by(user_id=user_id).first_or_404()
    points = CampaignPoint.query.filter_by(deputat_id=deputat.id).all()
    return jsonify({
        'biography': deputat.biography or 'Биография скоро будет добавлена.',
        'points': [{'id': p.id, 'text': p.text, 'for': p.votes_for, 'against': p.votes_against} for p in points]
    })


@public_bp.route('/api/campaign/vote', methods=['POST'])
def vote_campaign():
    data = request.json
    point_id = data.get('point_id')
    vote_type = data.get('type')  # 'for' или 'against'

    point = CampaignPoint.query.get_or_404(point_id)

    # Защита от повторного голосования в текущей сессии
    voted = session.get('voted_points', [])
    if str(point_id) in voted:
        return jsonify({'error': 'Вы уже голосовали за этот пункт'}), 400

    if vote_type == 'for':
        point.votes_for += 1
    elif vote_type == 'against':
        point.votes_against += 1

    voted.append(str(point_id))
    session['voted_points'] = voted
    db.session.commit()
    return jsonify({'success': True, 'for': point.votes_for, 'against': point.votes_against})
