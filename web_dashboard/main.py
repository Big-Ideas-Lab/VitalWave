from datetime import datetime, timedelta
from pathlib import Path
import os
import secrets
from flask import Flask, render_template, redirect, session, request, jsonify, abort
import firebase_admin
from firebase_admin import credentials, auth, firestore

key_path = Path.home() / 'Documents' / 'VitalWaveSecrets' / 'firebase-admin.json'
if not firebase_admin._apps:
    firebase_admin.initialize_app(credentials.Certificate(str(key_path)))

from session_dashboard import add_session_dashboard
from dash_app import add_dash
from firestore_query import get_devices

app = Flask(__name__, static_folder='static')
# Persist a private session-signing key outside the repository; never use a public placeholder.
secret_path = Path.home() / 'Documents' / 'VitalWaveSecrets' / 'dashboard-session.key'
if not os.environ.get('FLASK_SECRET_KEY'):
    secret_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(secret_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as output:
            output.write(secrets.token_hex(32))
    except FileExistsError:
        pass
app.secret_key = os.environ.get('FLASK_SECRET_KEY') or secret_path.read_text().strip()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Lax',
                  PERMANENT_SESSION_LIFETIME=timedelta(hours=8))
db = firestore.client()
add_session_dashboard(app, db)
add_dash(app)

@app.before_request
def protect_pages():
    public = {'login', 'register', 'try_login', 'static'}
    if request.endpoint not in public and 'user_id' not in session:
        return redirect('/login')

@app.route('/')
@app.route('/login')
def login():
    if session.get('user_id'):
        return redirect('/sessions')
    return render_template('auth.html', registering=False)

@app.route('/register')
def register():
    return render_template('auth.html', registering=True)

@app.route('/attempt-login', methods=['POST'])
def try_login():
    data = request.get_json(silent=True) or {}
    token = data.get('id_token')
    if not isinstance(token, str) or not token:
        return jsonify(message='Missing sign-in token'), 400
    try:
        decoded = auth.verify_id_token(token, check_revoked=True)
    except Exception:
        return jsonify(message='Sign in again'), 401
    session.clear()
    session.permanent = True
    session['user_id'] = decoded['uid']
    session['user_email'] = decoded.get('email', '')
    session['user_name'] = decoded.get('name', '')
    session['csrf'] = secrets.token_urlsafe(32)
    session['selected_date'] = datetime.today().strftime('%m-%d-%Y')
    # Legacy analytics devices are optional; new session syncing does not require them.
    try:
        devices = get_devices(decoded['uid']) or {}
    except Exception:
        devices = {}
    session['device_ids'] = devices if isinstance(devices, dict) else {}
    session['device_id'] = next(iter(session['device_ids']), None)
    return jsonify(status='success')

@app.route('/dashboard', methods=['GET', 'POST'])
def dashboard():
    return render_template('index.html', name=session.get('user_name') or session.get('user_email'),
                           device_ids=session.get('device_ids', {}))

@app.route('/update-session', methods=['POST'])
def update_session():
    data = request.get_json(silent=True) or {}
    device_id = data.get('device_id')
    if device_id not in session.get('device_ids', {}):
        abort(403)
    try:
        date = datetime.strptime(data['selected_date'], '%Y-%m-%d').strftime('%m-%d-%Y')
    except (KeyError, ValueError, TypeError):
        return jsonify(message='Invalid date'), 400
    session.update(device_id=device_id, selected_date=date)
    return jsonify(status='success', device_id=device_id)

@app.route('/settings', methods=['GET', 'POST'])
def settings():
    uid = session['user_id']
    session.setdefault('csrf', secrets.token_urlsafe(32))
    if request.method == 'POST':
        if not secrets.compare_digest(request.form.get('csrf', ''), session['csrf']):
            abort(403)
        name = request.form.get('name', '').strip()
        if not name or len(name) > 100:
            abort(400)
        auth.update_user(uid, display_name=name)
        session['user_name'] = name
        return redirect('/settings?saved=1')
    profile = auth.get_user(uid)
    return render_template('settings.html', profile=profile, name=profile.display_name or profile.email,
                           csrf=session['csrf'], saved=request.args.get('saved') == '1')

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/login')

if __name__ == '__main__':
    app.run(debug=True, port=5000)
