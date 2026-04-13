from datetime import datetime

from flask import Blueprint, jsonify, render_template, request
from flask_login import current_user, login_required

from models import Appeal, db

admin_bp = Blueprint('admin', __name__)


@admin_bp.route('/admin')
@login_required
def admin_panel():
    page = request.args.get('page', 1, type=int)
    per_page = 10

    # Пагинация обращений только текущего участка
    pagination = Appeal.query.filter_by(uchastok=current_user.uchastok)\
        .order_by(Appeal.created_at.desc())\
        .paginate(page=page, per_page=per_page, error_out=False)

    return render_template(
        'admin.html',
        appeals=pagination.items,
        deputat=current_user,
        pagination=pagination,
        page=page,
        per_page=per_page
    )


@admin_bp.route('/admin/update_appeal/<int:appeal_id>', methods=['POST'])
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
