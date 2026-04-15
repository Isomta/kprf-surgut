from datetime import datetime

from flask_login import UserMixin
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Deputat(UserMixin, db.Model):
    __tablename__ = 'deputats'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, unique=True, nullable=False)
    password_hash = db.Column(db.String(200), nullable=False)
    fio = db.Column(db.String(200), nullable=False)
    birth_date = db.Column(db.String(100))
    education = db.Column(db.String(200))
    experience = db.Column(db.String(100))
    reception_address = db.Column(db.String(300))
    phone = db.Column(db.String(50))
    email = db.Column(db.String(100))
    uchastok = db.Column(db.Integer, unique=True, nullable=False)
    biography = db.Column(db.Text, default="")
    photo = db.Column(db.String(300), default='/static/photos/default.png')


class AddressBoundary(db.Model):
    __tablename__ = 'address_boundaries'
    id = db.Column(db.Integer, primary_key=True)
    uchastok = db.Column(db.Integer, nullable=False)
    street = db.Column(db.String(100), nullable=False)
    house_number = db.Column(db.String(20), nullable=False)


class Appeal(db.Model):
    __tablename__ = 'appeals'
    id = db.Column(db.Integer, primary_key=True)
    uchastok = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.now)
    topic = db.Column(db.String(200), nullable=False)
    text = db.Column(db.Text, nullable=False)
    fio = db.Column(db.String(200))
    phone = db.Column(db.String(50))
    email = db.Column(db.String(100))
    need_visit = db.Column(db.Boolean, default=False)
    status = db.Column(db.String(50), default='Новое')
    status_date = db.Column(db.DateTime)
    result_text = db.Column(db.Text)


class TopicStats(db.Model):
    __tablename__ = 'topics'
    id = db.Column(db.Integer, primary_key=True)
    topic_name = db.Column(db.String(200), unique=True, nullable=False)


class CampaignPoint(db.Model):
    __tablename__ = 'campaign_points'
    id = db.Column(db.Integer, primary_key=True)
    deputat_id = db.Column(db.Integer, db.ForeignKey(
        'deputats.id'), nullable=False)
    text = db.Column(db.String(500), nullable=False)
    votes_for = db.Column(db.Integer, default=0)
    votes_against = db.Column(db.Integer, default=0)
