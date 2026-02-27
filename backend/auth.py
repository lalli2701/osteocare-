"""
Authentication module for OssoPulse using JWT and bcrypt.
"""
import sqlite3
import os
import bcrypt
import jwt
from datetime import datetime, timedelta
from functools import wraps
from flask import request, jsonify


# Configuration - can be overridden via environment variables
JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "osteocare-secret-key-change-in-production")
JWT_ALGORITHM = "HS256"
TOKEN_EXPIRY_MINUTES = 1440  # 24 hours for better user experience with health app


def get_db_connection(db_path: str) -> sqlite3.Connection:
    """Create a database connection."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def init_auth_db(db_path: str):
    """Initialize the authentication database schema."""
    conn = get_db_connection(db_path)
    cursor = conn.cursor()
    
    # Create users table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            full_name TEXT NOT NULL,
            phone_number TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            preferred_language TEXT DEFAULT 'english',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_login TIMESTAMP
        )
    ''')
    
    # Ensure migration-safe column for existing databases
    cursor.execute("PRAGMA table_info(users)")
    user_cols = [row[1] for row in cursor.fetchall()]
    if "preferred_language" not in user_cols:
        cursor.execute(
            "ALTER TABLE users ADD COLUMN preferred_language TEXT DEFAULT 'english'"
        )
    
    # Create index for faster phone lookups
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_phone_number 
        ON users(phone_number)
    ''')
    
    # Create risk_assessments table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS risk_assessments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            risk_score REAL NOT NULL,
            risk_level TEXT NOT NULL,
            next_reassessment_date TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id)
        )
    ''')

    # Ensure migration-safe column for existing databases
    cursor.execute("PRAGMA table_info(risk_assessments)")
    risk_cols = [row[1] for row in cursor.fetchall()]
    if "next_reassessment_date" not in risk_cols:
        cursor.execute(
            "ALTER TABLE risk_assessments ADD COLUMN next_reassessment_date TIMESTAMP"
        )
    
    # Create index for user_id in risk_assessments
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_risk_user_id 
        ON risk_assessments(user_id)
    ''')
    
    # Create recommendations table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS recommendations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            recommendation_text TEXT NOT NULL,
            category TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id)
        )
    ''')
    
    # Create index for user_id in recommendations
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_rec_user_id 
        ON recommendations(user_id)
    ''')
    
    conn.commit()
    conn.close()


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


def verify_password(password: str, password_hash: str) -> bool:
    """Verify a password against its hash."""
    return bcrypt.checkpw(password.encode('utf-8'), password_hash.encode('utf-8'))


def generate_token(user_id: int, phone_number: str) -> str:
    """Generate a JWT token for a user."""
    payload = {
        "user_id": user_id,
        "phone_number": phone_number,
        "exp": datetime.utcnow() + timedelta(minutes=TOKEN_EXPIRY_MINUTES),
        "iat": datetime.utcnow()
    }
    token = jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)
    return token


def decode_token(token: str) -> dict:
    """Decode and verify a JWT token."""
    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise ValueError("Token has expired")
    except jwt.InvalidTokenError:
        raise ValueError("Invalid token")


def token_required(f):
    """Decorator to protect routes with JWT authentication."""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        
        # Get token from Authorization header
        if 'Authorization' in request.headers:
            auth_header = request.headers['Authorization']
            try:
                token = auth_header.split(" ")[1]  # Bearer <token>
            except IndexError:
                return jsonify({"error": "Invalid authorization header format"}), 401
        
        if not token:
            return jsonify({"error": "Authorization token is missing"}), 401
        
        try:
            payload = decode_token(token)
            request.current_user = payload
        except ValueError as e:
            return jsonify({"error": str(e)}), 401
        
        return f(*args, **kwargs)
    
    return decorated


def signup_user(db_path: str, full_name: str, phone_number: str, password: str) -> dict:
    """
    Register a new user.
    
    Returns:
        dict: Success message or error details
    """
    # Validate inputs
    if not full_name or not full_name.strip():
        return {"error": "Full name is required", "status": 400}
    
    if not phone_number or len(phone_number) != 10 or not phone_number.isdigit():
        return {"error": "Phone number must be exactly 10 digits", "status": 400}
    
    if not password or len(password) < 6:
        return {"error": "Password must be at least 6 characters", "status": 400}
    
    conn = get_db_connection(db_path)
    cursor = conn.cursor()
    
    try:
        # Check if phone number already exists
        cursor.execute("SELECT id FROM users WHERE phone_number = ?", (phone_number,))
        existing_user = cursor.fetchone()
        
        if existing_user:
            conn.close()
            return {"error": "Phone number already registered", "status": 409}
        
        # Hash password and create user
        password_hash = hash_password(password)
        cursor.execute(
            "INSERT INTO users (full_name, phone_number, password_hash) VALUES (?, ?, ?)",
            (full_name.strip(), phone_number, password_hash)
        )
        conn.commit()
        conn.close()
        
        return {"message": "User registered successfully", "status": 201}
        
    except sqlite3.Error as e:
        conn.close()
        return {"error": f"Database error: {str(e)}", "status": 500}


def login_user(db_path: str, phone_number: str, password: str) -> dict:
    """
    Authenticate a user and generate JWT token.
    
    Returns:
        dict: Token and user info or error details
    """
    # Validate inputs
    if not phone_number or len(phone_number) != 10 or not phone_number.isdigit():
        return {"error": "Invalid phone number", "status": 400}
    
    if not password:
        return {"error": "Password is required", "status": 400}
    
    conn = get_db_connection(db_path)
    cursor = conn.cursor()
    
    try:
        # Fetch user by phone number
        cursor.execute(
            "SELECT id, full_name, phone_number, password_hash FROM users WHERE phone_number = ?",
            (phone_number,)
        )
        user = cursor.fetchone()
        
        if not user:
            conn.close()
            return {"error": "Invalid phone number or password", "status": 401}
        
        # Verify password
        if not verify_password(password, user['password_hash']):
            conn.close()
            return {"error": "Invalid phone number or password", "status": 401}
        
        # Update last login
        cursor.execute(
            "UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?",
            (user['id'],)
        )
        conn.commit()
        
        # Generate token
        token = generate_token(user['id'], user['phone_number'])
        
        conn.close()
        
        return {
            "access_token": token,
            "user": {
                "id": user['id'],
                "full_name": user['full_name'],
                "phone_number": user['phone_number']
            },
            "status": 200
        }
        
    except sqlite3.Error as e:
        conn.close()
        return {"error": f"Database error: {str(e)}", "status": 500}


def get_user_by_id(db_path: str, user_id: int) -> dict:
    """Get user information by ID."""
    conn = get_db_connection(db_path)
    cursor = conn.cursor()
    
    cursor.execute(
        "SELECT id, full_name, phone_number, created_at FROM users WHERE id = ?",
        (user_id,)
    )
    user = cursor.fetchone()
    conn.close()
    
    if user:
        return {
            "id": user['id'],
            "full_name": user['full_name'],
            "phone_number": user['phone_number'],
            "created_at": user['created_at']
        }
    return None
