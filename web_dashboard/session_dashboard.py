"""Register after Firebase initialization: add_session_dashboard(app, db)."""
from datetime import datetime, timezone
from flask import Blueprint, abort, redirect, render_template, session, url_for
from firebase_admin import auth
from markupsafe import Markup, escape


def add_session_dashboard(app, db):
    pages = Blueprint('recordings', __name__, template_folder='templates')

    def owner():
        # Admin SDK bypasses Firestore rules: derive the path ONLY from login.
        uid = session.get('user_id')
        if not isinstance(uid, str) or not uid or '/' in uid:
            return None
        return uid

    def display_name(uid):
        try:
            user = auth.get_user(uid)
            if user.disabled:
                abort(403)
            return user.display_name or user.email or uid
        except auth.UserNotFoundError:
            abort(403)

    @pages.app_template_filter('recording_date')
    def recording_date(value):
        if not isinstance(value, datetime):
            return '—'
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    @pages.app_template_filter('recording_time')
    def recording_time(value):
        if not isinstance(value, datetime):
            return '—'
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return Markup('<time datetime="{}">{}</time>').format(
            escape(value.isoformat()), escape(recording_date(value)))

    @pages.route('/sessions')
    def listing():
        uid = owner()
        if not uid:
            return redirect('/login')
        name = display_name(uid)
        # Bounded reads; refresh is manual. Only the newest 100 are displayed.
        docs = (db.collection('users').document(uid).collection('sessions')
                .order_by('startedAt', direction='DESCENDING').limit(100).stream())
        rows = [dict(doc.to_dict() or {}, documentID=doc.id) for doc in docs]
        return render_template('recording_sessions.html', rows=rows, name=name)

    @pages.route('/sessions/<recording_id>')
    def detail(recording_id):
        uid = owner()
        if not uid:
            return redirect('/login')
        name = display_name(uid)
        ref = db.collection('users').document(uid).collection('sessions').document(recording_id)
        doc = ref.get()
        if not doc.exists:
            abort(404)
        info = doc.to_dict() or {}
        events = [e.to_dict() or {} for e in
                  ref.collection('events').order_by('lineIndex').limit(401).stream()]
        return render_template('recording_session.html', info=info, name=name,
                               events=events[:400], truncated=len(events) > 400)

    @pages.route('/visualize')
    def visualize():
        uid = owner()
        if not uid:
            return redirect('/login')
        return render_template('visualize.html', name=display_name(uid))

    app.register_blueprint(pages)
