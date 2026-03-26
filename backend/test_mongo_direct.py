#!/usr/bin/env python3
"""
Direct MongoDB connection test.
Run this to see ✅ or ❌ status before starting the full app.
"""
import os
from dotenv import load_dotenv
from pymongo import MongoClient

# Load environment variables
load_dotenv()

MONGO_URI = os.environ.get("MONGODB_URI", "").strip()

print("\n" + "="*70)
print("MONGODB CONNECTION VERIFICATION TEST")
print("="*70 + "\n")

if not MONGO_URI:
    print("❌ MONGODB_URI is not set")
    print("   Set it in .env or environment variables")
    exit(1)

print(f"Connection String: {MONGO_URI[:50]}..." if len(MONGO_URI) > 50 else f"Connection String: {MONGO_URI}")
print(f"Timeout: 3 seconds (serverSelectionTimeoutMS=3000)\n")

try:
    print("Attempting connection...")
    client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
    
    print("Sending ping command...")
    client.admin.command('ping')
    
    print("\n✅ MongoDB CONNECTED")
    print("   Status: Connection successful and responsive")
    print("   Next: Full app.py startup will use this connection\n")
    exit(0)
    
except Exception as e:
    print(f"\n❌ MongoDB NOT CONNECTED")
    print(f"   Error: {e}")
    print(f"   Error Type: {type(e).__name__}\n")
    
    print("🔧 TROUBLESHOOTING:")
    print("   1. Check if MongoDB is running")
    print("      Windows: Services -> MongoDB")
    print("      Or: net start MongoDB")
    print()
    print("   2. Verify connection string in .env")
    print("      Example: mongodb://localhost:27017/")
    print()
    print("   3. Check MongoDB port (default: 27017)")
    print("      Check if it's listening: netstat -an | findstr 27017")
    print()
    exit(1)
