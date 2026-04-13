from flask import (Blueprint, flash, get_flashed_messages, redirect, request,
                   url_for)
from flask_login import login_user, logout_user
from flask_wtf.csrf import generate_csrf, validate_csrf
from werkzeug.security import check_password_hash

from models import Deputat

auth_bp = Blueprint('auth', __name__)


def render_login_form():
    csrf_token = generate_csrf()
    messages = get_flashed_messages()
    flash_html = "".join(
        f'<p style="color:#e74c3c;text-align:center;margin:10px 0;font-size:13px;">{m}</p>'
        for m in messages
    ) if messages else ""

    return f'''
    <!DOCTYPE html>
    <html>
    <head><title>Вход для депутата</title>
    <style>
        body{{font-family:Arial;display:flex;justify-content:center;align-items:center;height:100vh;background:#f0f0f0;}}
        .login-form{{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:300px;}}
        input{{width:100%;padding:8px;margin:5px 0;border:1px solid #ddd;border-radius:4px;box-sizing:border-box;}}
        button{{width:100%;padding:10px;background:#3498db;color:white;border:none;border-radius:4px;cursor:pointer;margin-top:10px;}}
        button:hover{{background:#2980b9;}}
    </style>
    </head>
    <body>
        <div class="login-form">
            <h3 style="text-align:center;">Вход в систему</h3>
            {flash_html}
            <form method="post">
                <input type="hidden" name="csrf_token" value="{csrf_token}">
                <input type="text" name="user_id" placeholder="ID депутата" required>
                <input type="password" name="password" placeholder="Пароль" required>
                <button type="submit">Войти</button>
            </form>
            <p style="margin-top:15px;font-size:12px;color:#666;text-align:center;">Демо-пароль: pass123</p>
        </div>
    </body>
    </html>
    '''


@auth_bp.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    if request.method == 'POST':
        try:
            validate_csrf(request.form.get('csrf_token'))
        except Exception:
            flash('Ошибка безопасности. Обновите страницу и попробуйте снова.')
            return render_login_form()

        user_id = request.form.get('user_id')
        password = request.form.get('password')
        deputat = Deputat.query.filter_by(user_id=user_id).first()

        if deputat and check_password_hash(deputat.password_hash, password):
            login_user(deputat)
            return redirect(url_for('admin.admin_panel'))
        else:
            flash('Неверный ID или пароль')

    return render_login_form()


@auth_bp.route('/admin/logout')
def admin_logout():
    logout_user()
    return redirect(url_for('public.index'))
