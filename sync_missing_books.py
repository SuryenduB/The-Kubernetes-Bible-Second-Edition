import os
import json
import subprocess
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
LOCAL_IMPORT_DIR = "/Users/macbookpro/Downloads/calibre-import"
NAS_IMPORT_DIR = "/share/Public/calibre-import"
NAS_PATH = "/share/Public/calibre-library"
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

def get_drive_files():
    print("Fetching files list and IDs from Google Drive...")
    cmd = "rclone lsf gdrive: --format \"ip\" --recursive"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error fetching Google Drive files: {result.stderr}")
        return []
    
    drive_files = []
    lines = result.stdout.strip().split('\n')
    for line in lines:
        if ';' not in line:
            continue
        file_id, path = line.split(';', 1)
        # Skip folders
        if path.endswith('/'):
            continue
        filename = os.path.basename(path)
        ext = os.path.splitext(filename)[1].lower()
        if ext in {'.pdf', '.epub', '.mobi', '.azw3', '.azw', '.m4b'}:
            drive_files.append({
                'id': file_id,
                'name': filename,
                'path': path,
                'ext': ext.replace('.', '')
            })
    return drive_files

def get_nas_files():
    print("Fetching files list from QNAP NAS calibre-library...")
    cmd = f"sshpass -p '{NAS_PASS}' ssh -o StrictHostKeyChecking=no {NAS_USER}@{NAS_IP} \"find {NAS_PATH} -type f\""
    try:
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        lines = result.stdout.strip().split('\n')
        
        ebook_exts = {'.pdf', '.epub', '.mobi', '.azw', '.azw3', '.djvu', '.fb2'}
        nas_files = []
        for line in lines:
            filename = os.path.basename(line)
            ext = os.path.splitext(filename.lower())[1]
            if ext in ebook_exts:
                parts = line.split('/')
                if len(parts) >= 6:
                    author = parts[-3]
                    dir_title = parts[-2]
                    # Strip calibre ID suffix like " (3)"
                    clean_dir_title = re.sub(r'\s*\(\d+\)$', '', dir_title)
                    nas_files.append({
                        'path': line,
                        'name': filename,
                        'title': clean_dir_title,
                        'author': author,
                        'ext': ext.replace('.', '')
                    })
        return nas_files
    except Exception as e:
        print(f"Error fetching NAS files: {e}")
        return []

def clean_title(title):
    title_lower = title.lower()
    base = os.path.splitext(title_lower)[0]
    base = re.sub(r'\s*\([^)]*\)', '', base)
    base = re.sub(r'\s*\[[^\]]*\]', '', base)
    base = re.sub(r'\s+-\s+.*$', '', base)
    base = re.sub(r'\s*by\s*.*$', '', base)
    base = re.sub(r'[^a-z0-9\s]', ' ', base)
    return " ".join(base.split())

def similar(a, b):
    words_a = set(clean_title(a).split())
    words_b = set(clean_title(b).split())
    if not words_a or not words_b:
        return 0.0
    intersection = words_a.intersection(words_b)
    union = words_a.union(words_b)
    jaccard = len(intersection) / len(union)
    
    is_subset = words_a.issubset(words_b) or words_b.issubset(words_a)
    if is_subset and min(len(words_a), len(words_b)) >= 2:
        return 1.0
    return jaccard

def get_active_access_token():
    print("Refreshing Google Drive session token via rclone...")
    subprocess.run("rclone lsf gdrive: --max-depth 1", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run("rclone config show gdrive", shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    match = re.search(r'"access_token"\s*:\s*"([^"]+)"', result.stdout)
    if match:
        return match.group(1)
    return None

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
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    f.write(chunk)
        return True, book['name']
    except Exception as e:
        return False, f"{book['name']} (Error: {str(e)})"

def clean_filename(name):
    return re.sub(r'[^a-zA-Z0-9\s\-_.]', '', name)

def run_pipeline():
    if not check_rclone_config():
        print("CRITICAL: 'gdrive' remote is not configured in rclone.")
        print("Please configure it first by running 'rclone config'.")
        return

    nas_books = get_nas_files()
    print(f"Loaded {len(nas_books)} books from QNAP NAS library.")
    
    drive_books = get_drive_files()
    print(f"Loaded {len(drive_books)} books from Google Drive.")

    # Filter Drive books for technical keywords
    tech_drive_books = []
    for db in drive_books:
        name_lower = db['name'].lower()
        if any(keyword in name_lower for keyword in TECH_KEYWORDS):
            tech_drive_books.append(db)
    print(f"Identified {len(tech_drive_books)} technical books in Google Drive.")

    # Determine missing books
    missing_books = []
    for db in tech_drive_books:
        is_matched = False
        for nb in nas_books:
            # Match against folder name or raw file name
            if similar(db['name'], nb['title']) > 0.75 or similar(db['name'], nb['name']) > 0.75:
                is_matched = True
                break
        if not is_matched:
            missing_books.append(db)
            
    print(f"\nResult: Found {len(missing_books)} books in Google Drive not present on the NAS.")
    for idx, mb in enumerate(missing_books):
        print(f"  - {mb['name']}")

    if not missing_books:
        print("\nAll technical books are already in sync. Nothing to do!")
        return

    # Clean local staging directory
    if os.path.exists(LOCAL_IMPORT_DIR):
        print("\nCleaning up local temporary folder...")
        subprocess.run(f"rm -rf {LOCAL_IMPORT_DIR}/*", shell=True)
    os.makedirs(LOCAL_IMPORT_DIR, exist_ok=True)

    access_token = get_active_access_token()
    if not access_token:
        print("Error: Could not retrieve active access token from rclone.")
        return

    # Concurrent downloads
    print(f"\nDownloading {len(missing_books)} missing books concurrently (16 workers)...")
    downloaded_count = 0
    failed_books = []
    
    with ThreadPoolExecutor(max_workers=16) as executor:
        futures = {executor.submit(download_book, book, access_token): book for book in missing_books}
        completed_count = 0
        for future in as_completed(futures):
            completed_count += 1
            success, msg = future.result()
            if success:
                downloaded_count += 1
                print(f"[{completed_count}/{len(missing_books)}] ✓ Downloaded: {msg}")
            else:
                failed_books.append(msg)
                print(f"[{completed_count}/{len(missing_books)}] ✗ Failed: {msg}")

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
            print(f"\nAll new files successfully synced to QNAP NAS at: {NAS_IMPORT_DIR}")
        except Exception as e:
            print(f"NAS sync failed: {e}")

if __name__ == "__main__":
    run_pipeline()
