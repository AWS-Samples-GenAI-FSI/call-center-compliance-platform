#!/usr/bin/env python3
import os
import json
import subprocess
import sys

def generate_audio_files():
    """Generate 100 WAV audio files from the test transcripts using text-to-speech"""
    
    # Check if we have the test transcripts
    test_dir = "/Users/shamakka/allay-eba-pca/test-transcripts"
    audio_dir = "/Users/shamakka/allay-eba-pca/test-audio"
    
    if not os.path.exists(test_dir):
        print("❌ Test transcripts not found. Run generate_test_files.py first.")
        return
    
    # Create audio directory
    os.makedirs(audio_dir, exist_ok=True)
    
    # Load test manifest
    manifest_path = os.path.join(test_dir, "test_manifest.json")
    with open(manifest_path, 'r') as f:
        manifest = json.load(f)
    
    print(f"🎵 Generating {len(manifest['files'])} audio files...")
    
    # Generate audio for each test file
    for i, test_file in enumerate(manifest['files'], 1):
        transcript_file = os.path.join(test_dir, test_file['file'])
        
        # Load transcript
        with open(transcript_file, 'r') as f:
            transcript_data = json.load(f)
        
        transcript_text = transcript_data['results']['transcripts'][0]['transcript']
        
        # Create audio filename
        audio_filename = test_file['file'].replace('.json', '.wav')
        audio_path = os.path.join(audio_dir, audio_filename)
        
        # Generate audio using macOS built-in text-to-speech
        try:
            # Use different voices for variety
            voices = ['Alex', 'Victoria', 'Samantha', 'Daniel', 'Karen']
            voice = voices[i % len(voices)]
            
            # Generate speech
            cmd = [
                'say',
                '-v', voice,
                '-o', audio_path,
                '--data-format=LEF32@22050',
                transcript_text
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"✅ Generated {i:3d}/100: {audio_filename}")
            else:
                print(f"❌ Failed {i:3d}/100: {audio_filename} - {result.stderr}")
                
        except Exception as e:
            print(f"❌ Error generating {audio_filename}: {str(e)}")
    
    # Create upload script for audio files
    create_audio_upload_script(audio_dir)
    
    print(f"\n🎵 Generated audio files in: {audio_dir}")
    print(f"📤 Upload script: {audio_dir}/upload_audio.sh")

def create_audio_upload_script(audio_dir):
    """Create script to upload audio files to S3"""
    
    upload_script = f"""#!/bin/bash

# Upload test audio files to S3 for processing
BUCKET="anycompany-input-prod-164543933824"
AUDIO_DIR="{audio_dir}"

echo "🚀 Uploading test audio files to S3..."

# Upload all audio files to audio/ prefix
for file in $AUDIO_DIR/test_*.wav; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Uploading $filename..."
        aws s3 cp "$file" "s3://$BUCKET/audio/$filename"
        
        # Delay to avoid overwhelming transcription service
        sleep 2
    fi
done

echo "✅ Upload complete! Files will be processed automatically."
echo "📊 Monitor transcription jobs: aws transcribe list-transcription-jobs --status IN_PROGRESS"
echo "📊 Monitor processing: aws logs tail /aws/lambda/anycompany-processor-prod --follow"
"""
    
    script_path = os.path.join(audio_dir, "upload_audio.sh")
    with open(script_path, 'w') as f:
        f.write(upload_script)
    
    os.chmod(script_path, 0o755)
    print(f"📤 Audio upload script created: {script_path}")

if __name__ == "__main__":
    # Check if 'say' command is available (macOS)
    try:
        subprocess.run(['which', 'say'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 'say' command not found. This script requires macOS text-to-speech.")
        print("💡 Alternative: Use online TTS services or record audio manually.")
        sys.exit(1)
    
    generate_audio_files()
    
    print("\n🎯 Audio Files Generated!")
    print("🚀 To test the complete pipeline:")
    print("   cd test-audio")
    print("   ./upload_audio.sh")
    print("\n📊 Monitor progress:")
    print("   aws transcribe list-transcription-jobs --status IN_PROGRESS")
    print("   aws logs tail /aws/lambda/anycompany-processor-prod --follow")