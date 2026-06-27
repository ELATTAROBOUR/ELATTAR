import urllib.request
import sqlite3
import os

url = "https://raw.githubusercontent.com/mojlinux58/ELATTAR/DB_SUB/keygen/subscribers.db"
temp_db = "temp_github_subscribers.db"

try:
    print(f"Downloading from {url}...")
    urllib.request.urlretrieve(url, temp_db)
    print("Download completed. Size:", os.path.getsize(temp_db), "bytes")
    
    conn = sqlite3.connect(temp_db)
    cursor = conn.cursor()
    
    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()
    print("Tables in database:", tables)
    
    if ('subscribers',) in tables:
        cursor.execute("SELECT * FROM subscribers")
        rows = cursor.fetchall()
        print(f"Subscribers ({len(rows)}):")
        for r in rows:
            print(r)
    else:
        print("Table 'subscribers' NOT found!")
        
    conn.close()
except Exception as e:
    print("Error:", e)
finally:
    if os.path.exists(temp_db):
        os.remove(temp_db)
