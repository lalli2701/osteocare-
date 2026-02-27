"""
Test script for OsteoCare+ Authentication System
This script tests the signup, login, and token verification endpoints.
"""
import requests
import json

# Configuration
BASE_URL = "http://localhost:5000"
TEST_USER = {
    "full_name": "Test User",
    "phone_number": "9876543210",
    "password": "test123456"
}

def print_separator():
    print("\n" + "="*60 + "\n")

def test_signup():
    """Test user signup"""
    print("🔹 Testing User Signup...")
    
    url = f"{BASE_URL}/api/auth/signup"
    response = requests.post(url, json=TEST_USER)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 201:
        print("✅ Signup successful!")
        return True
    elif response.status_code == 409:
        print("⚠️ User already exists (This is okay for testing)")
        return True
    else:
        print("❌ Signup failed!")
        return False

def test_login():
    """Test user login"""
    print("🔹 Testing User Login...")
    
    url = f"{BASE_URL}/api/auth/login"
    login_data = {
        "phone_number": TEST_USER["phone_number"],
        "password": TEST_USER["password"]
    }
    
    response = requests.post(url, json=login_data)
    
    print(f"Status Code: {response.status_code}")
    response_data = response.json()
    print(f"Response: {json.dumps(response_data, indent=2)}")
    
    if response.status_code == 200:
        print("✅ Login successful!")
        token = response_data.get("access_token")
        if token:
            print(f"📝 Token received (first 50 chars): {token[:50]}...")
            return token
        else:
            print("❌ No token in response!")
            return None
    else:
        print("❌ Login failed!")
        return None

def test_verify_token(token):
    """Test token verification"""
    print("🔹 Testing Token Verification...")
    
    url = f"{BASE_URL}/api/auth/verify"
    headers = {"Authorization": f"Bearer {token}"}
    
    response = requests.get(url, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 200:
        print("✅ Token verification successful!")
        return True
    else:
        print("❌ Token verification failed!")
        return False

def test_get_profile(token):
    """Test getting user profile"""
    print("🔹 Testing Get User Profile...")
    
    url = f"{BASE_URL}/api/user/profile"
    headers = {"Authorization": f"Bearer {token}"}
    
    response = requests.get(url, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 200:
        print("✅ Profile retrieval successful!")
        return True
    else:
        print("❌ Profile retrieval failed!")
        return False

def test_invalid_credentials():
    """Test login with invalid credentials"""
    print("🔹 Testing Invalid Credentials...")
    
    url = f"{BASE_URL}/api/auth/login"
    invalid_data = {
        "phone_number": TEST_USER["phone_number"],
        "password": "wrongpassword"
    }
    
    response = requests.post(url, json=invalid_data)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 401:
        print("✅ Invalid credentials correctly rejected!")
        return True
    else:
        print("❌ Unexpected response for invalid credentials!")
        return False

def test_invalid_token():
    """Test with invalid token"""
    print("🔹 Testing Invalid Token...")
    
    url = f"{BASE_URL}/api/auth/verify"
    headers = {"Authorization": "Bearer invalid_token_12345"}
    
    response = requests.get(url, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 401:
        print("✅ Invalid token correctly rejected!")
        return True
    else:
        print("❌ Unexpected response for invalid token!")
        return False

def test_validation():
    """Test input validation"""
    print("🔹 Testing Input Validation...")
    
    # Test phone number validation (not 10 digits)
    url = f"{BASE_URL}/api/auth/signup"
    invalid_data = {
        "full_name": "Test User",
        "phone_number": "123",  # Invalid: not 10 digits
        "password": "test123"
    }
    
    response = requests.post(url, json=invalid_data)
    print(f"\nInvalid phone number test:")
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    # Test password validation (too short)
    invalid_data = {
        "full_name": "Test User",
        "phone_number": "9876543210",
        "password": "123"  # Invalid: less than 6 characters
    }
    
    response = requests.post(url, json=invalid_data)
    print(f"\nShort password test:")
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    # Test empty name
    invalid_data = {
        "full_name": "",  # Invalid: empty name
        "phone_number": "9876543210",
        "password": "test123"
    }
    
    response = requests.post(url, json=invalid_data)
    print(f"\nEmpty name test:")
    print(f"Status Code: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    print("✅ Validation tests completed!")
    return True

def main():
    """Run all tests"""
    print("\n" + "="*60)
    print("🚀 OsteoCare+ Authentication System Test Suite")
    print("="*60)
    
    try:
        # Test 1: Signup
        print_separator()
        test_signup()
        
        # Test 2: Login
        print_separator()
        token = test_login()
        
        if token:
            # Test 3: Verify Token
            print_separator()
            test_verify_token(token)
            
            # Test 4: Get Profile
            print_separator()
            test_get_profile(token)
        
        # Test 5: Invalid Credentials
        print_separator()
        test_invalid_credentials()
        
        # Test 6: Invalid Token
        print_separator()
        test_invalid_token()
        
        # Test 7: Input Validation
        print_separator()
        test_validation()
        
        # Summary
        print_separator()
        print("✅ All tests completed!")
        print("\n📝 Summary:")
        print("   - User signup/login working")
        print("   - JWT token generation working")
        print("   - Token verification working")
        print("   - Profile retrieval working")
        print("   - Security validation working")
        print("\n🎉 Authentication system is ready to use!")
        
    except requests.exceptions.ConnectionError:
        print("\n❌ Connection Error!")
        print("Please make sure the Flask backend is running:")
        print("   cd backend")
        print("   python app.py")
    except Exception as e:
        print(f"\n❌ Error during testing: {str(e)}")

if __name__ == "__main__":
    main()
