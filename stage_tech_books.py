import os
import json
import subprocess
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

COMPARE_RESULT_PATH = "/Users/macbookpro/.gemini/antigravity-cli/brain/8d2d6c24-797a-49be-8502-1b833a3cd14e/scratch/compare_result.json"
LOCAL_IMPORT_DIR = "/Users/macbookpro/Downloads/calibre-import"
NAS_IMPORT_DIR = "/share/Public/calibre-import"
NAS_IP = "192.168.0.128"
NAS_USER = "admin"
NAS_PASS = "558068"

TECH_KEYWORDS = [
    'powershell', 'directory', 'k3s', 'kubernetes', 'docker', 'linux', 
    'azure', 'aws', 'microsoft', 'security', 'python', 'java', 
    'programming', 'network', 'cloud', 'cert', 'exam', 'cisco', 
    'monitoring', 'git', 'sql', 'database', 'copilot', 'tutor',
    'defense', 'forefront', 'intune', 'kusto', 'identity', 'cybersecurity'
]

def check_rclone_config():
    try:
        result = subprocess.run("rclone listremotes", shell=True, capture_output=True, text=True)
        remotes = result.stdout.strip().split('\n')
        return any('gdrive' in r for r in remotes)
    except Exception:
        return False

def get_active_access_token():
    print("Refreshing Google Drive session token via rclone...")
    # Force token refresh using a lightweight command
    subprocess.run("rclone lsf gdrive: --max-depth 1", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Extract token
    result = subprocess.run("rclone config show gdrive", shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    
    match = re.search(r'"access_token"\s*:\s*"([^"]+)"', result.stdout)
    if match:
        return match.group(1)
    return None

def clean_filename(name):
    return re.sub(r'[^a-zA-Z0-9\s\-_.]', '', name)

def download_book(book, access_token):
    file_id = book['id']
    filename = clean_filename(book['name'])
    dest_path = os.path.join(LOCAL_IMPORT_DIR, filename)
    
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media"
    req = urllib.request.Request(url)
    req.add_header('Authorization', f'Bearer {access_token}')
    
    import ssl
    context = ssl._create_unverified_context()
    
    try:
        with urllib.request.urlopen(req, context=context) as response:
            with open(dest_path, 'wb') as f:
                while True:
                    chunk = response.read(1024 * 1024) # Download in 1MB chunks
                    if not chunk:
                        break
                    f.write(chunk)
        return True, book['name']
    except Exception as e:
        return False, f"{book['name']} (Error: {str(e)})"

def run_staging():
    if not os.path.exists(COMPARE_RESULT_PATH):
        print(f"Error: Comparison result file not found at {COMPARE_RESULT_PATH}")
        return
        
    if not check_rclone_config():
        print("CRITICAL: 'gdrive' remote is not configured in rclone.")
        print("Please configure it first by running:")
        print("  rclone config")
        print("Create a new remote named 'gdrive' of type 'drive'.")
        return

    access_token = get_active_access_token()
    if not access_token:
        print("Error: Could not retrieve active access token from rclone.")
        return
        
    with open(COMPARE_RESULT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    drive_only = data.get('drive_only_books', [])
    
    # Filter for tech books
    tech_books = []
    for book in drive_only:
        name_lower = book['name'].lower()
        if any(keyword in name_lower for keyword in TECH_KEYWORDS):
            tech_books.append(book)
            
    print(f"Found {len(tech_books)} technical books to download (filtered from {len(drive_only)} total).")
    
    # Create local staging directory
    os.makedirs(LOCAL_IMPORT_DIR, exist_ok=True)
    
    # Download books concurrently via direct HTTPS
    print(f"\nDownloading books in parallel via high-speed HTTPS pool (16 workers)...")
    downloaded_count = 0
    failed_books = []
    
    with ThreadPoolExecutor(max_workers=16) as executor:
        futures = {executor.submit(download_book, book, access_token): book for book in tech_books}
        
        completed_count = 0
        for future in as_completed(futures):
            completed_count += 1
            success, msg = future.result()
            if success:
                downloaded_count += 1
                print(f"[{completed_count}/{len(tech_books)}] ✓ Downloaded: {msg}")
            else:
                failed_books.append(msg)
                print(f"[{completed_count}/{len(tech_books)}] ✗ Failed: {msg}")
                
    print(f"\nSuccessfully downloaded {downloaded_count} files to {LOCAL_IMPORT_DIR}.")
    if failed_books:
        print(f"Failed to download {len(failed_books)} files:")
        for fb in failed_books:
            print(f"  - {fb}")
            
    if downloaded_count > 0:
        # Create staging directory on NAS
        print("\nCreating staging folder on QNAP NAS...")
        mkdir_cmd = f"sshpass -p '{NAS_PASS}' ssh -o StrictHostKeyChecking=no {NAS_USER}@{NAS_IP} 'mkdir -p {NAS_IMPORT_DIR}'"
        try:
            subprocess.run(mkdir_cmd, shell=True, check=True)
            
            # Sync to NAS via rsync
            print("Syncing files to NAS using rsync...")
            rsync_cmd = f"sshpass -p '{NAS_PASS}' rsync -avz --progress \"{LOCAL_IMPORT_DIR}/\" {NAS_USER}@{NAS_IP}:{NAS_IMPORT_DIR}/"
            subprocess.run(rsync_cmd, shell=True, check=True)
            print(f"\nAll files successfully staged on QNAP NAS at: {NAS_IMPORT_DIR}")
            print("\nNext steps:")
            print("1. Log in to Calibre Web.")
            print("2. Navigate to Admin -> Basic Configuration -> Feature Configuration.")
            print("3. Check 'Enable Auto-Add' and set folder to: /share/Public/calibre-import")
            print("4. Calibre Web will auto-import, index, and organize the files into the main library!")
        except Exception as e:
            print(f"NAS sync failed: {e}")

if __name__ == "__main__":
    run_staging()
