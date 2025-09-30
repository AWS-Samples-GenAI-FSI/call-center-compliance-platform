#!/usr/bin/env python3
"""
Create test audio files for Ally compliance system testing.
Uses text-to-speech to generate WAV files from transcripts.
"""

import os
import subprocess
import json

# Test transcripts with expected violations
test_calls = {
    "A001_C001_MA_collections.wav": {
        "text": "Hello, this is John Smith from AnyCompany Servicing. I'm calling for Robert Williams regarding your auto loan account. Can you confirm I'm speaking with Robert Williams? Thank you. I wanted to discuss your account status and available payment options.",
        "expected_violations": []
    },
    
    "A002_C002_TX_collections.wav": {
        "text": "Hi, this is Sarah calling about your car payment. You need to pay now or we'll repossess your vehicle. Your account is overdue and you must pay immediately. If you don't pay, we'll take legal action and garnish your wages.",
        "expected_violations": ["LO1001.12", "LO1006.03", "LO1006.04", "LO1007.05"]
    },
    
    "A003_C003_CA_collections.wav": {
        "text": "Hello, this is Mike Davis from AnyCompany Servicing calling for David Miller. I need to discuss your auto loan payment that's past due. Can we set up a payment arrangement today?",
        "expected_violations": ["LO1005.05"]
    },
    
    "A001_C004_NY_collections.wav": {
        "text": "Hi, this is John Smith from AnyCompany Servicing. I'm calling Jennifer Davis about your account. We need to discuss your payment options and get your account current.",
        "expected_violations": ["LO1005.06"]
    },
    
    "A002_C001_MA_collections.wav": {
        "text": "Hello, this is someone from AnyCompany Servicing calling about your auto loan. Can you confirm your identity please?",
        "expected_violations": ["LO1001.03"]
    },
    
    "A001_UNKNOWN_TX_collections.wav": {
        "text": "Hi, this is John Smith from AnyCompany Servicing. I'm looking for Lisa Brown. She has an overdue account balance of eighteen hundred dollars and needs to make a payment immediately.",
        "expected_violations": ["LO1005.02", "LO1005.24"]
    },
    
    "A003_C002_TX_collections.wav": {
        "text": "Hello, this is Michael from AnyCompany Servicing calling Lisa Brown about your collections account. We need to discuss payment options.",
        "expected_violations": ["LO1005.11"]
    },
    
    "A002_C005_MA_collections.wav": {
        "text": "Hi, this is Sarah Johnson from AnyCompany Servicing calling Robert Williams. Look, this is getting ridiculous. You need to pay this bill or we're going to have serious problems.",
        "expected_violations": ["LO1005.14"]
    }
}

def create_audio_files():
    """Create audio files using macOS 'say' command"""
    audio_dir = "audio"
    os.makedirs(audio_dir, exist_ok=True)
    
    for filename, data in test_calls.items():
        output_path = os.path.join(audio_dir, filename)
        text = data["text"]
        
        print(f"Creating {filename}...")
        
        # Use macOS 'say' command to create audio
        try:
            # Create temporary AIFF file
            temp_aiff = output_path.replace('.wav', '.aiff')
            subprocess.run([
                '/usr/bin/say', 
                '-o', temp_aiff,
                '-v', 'Alex',  # Use Alex voice
                text
            ], check=True)
            
            # Convert AIFF to WAV using ffmpeg (if available) or sox
            try:
                subprocess.run([
                    'ffmpeg', '-i', temp_aiff, 
                    '-ar', '16000',  # 16kHz sample rate for Transcribe
                    '-ac', '1',      # Mono
                    output_path
                ], check=True, capture_output=True)
            except FileNotFoundError:
                # Fallback: just rename AIFF to WAV (may work for testing)
                os.rename(temp_aiff, output_path)
                print(f"  Warning: ffmpeg not found, using AIFF as WAV")
            else:
                # Remove temporary AIFF file
                os.remove(temp_aiff)
                
            print(f"  ✓ Created {filename}")
            
        except subprocess.CalledProcessError as e:
            print(f"  ✗ Failed to create {filename}: {e}")
        except Exception as e:
            print(f"  ✗ Error creating {filename}: {e}")

def create_test_summary():
    """Create a summary of test cases"""
    with open("test_summary.json", "w") as f:
        json.dump(test_calls, f, indent=2)
    
    print("\nTest Summary:")
    print("=============")
    for filename, data in test_calls.items():
        violations = data["expected_violations"]
        print(f"{filename}: {len(violations)} expected violations")
        if violations:
            print(f"  - {', '.join(violations)}")

if __name__ == "__main__":
    print("Creating test audio files for Ally Compliance System...")
    print("=" * 50)
    
    create_audio_files()
    create_test_summary()
    
    print("\nTest files created!")
    print("\nTo use:")
    print("1. Upload master_reference.json to S3 reference/ folder")
    print("2. Upload audio/*.wav files to S3 audio/ folder")
    print("3. Check compliance results in your React UI")