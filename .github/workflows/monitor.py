#!/usr/bin/env python3
"""MongoDB Storage Monitor Script"""
import pymongo
import os
import requests
from datetime import datetime

def send_telegram(message):
    token = os.environ['TELEGRAM_BOT_TOKEN']
    chat_id = os.environ['TELEGRAM_CHAT_ID']
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    requests.post(url, json={'chat_id': chat_id, 'text': message})

def main():
    client = pymongo.MongoClient(os.environ['MONGODB_URI'], serverSelectionTimeoutMS=10000)
    
    # Get database info
    db = client['claw-db1']
    collections = db.list_collection_names()
    num_collections = len(collections)
    
    # Count total documents
    total_objects = 0
    for col_name in collections:
        try:
            count = db[col_name].count_documents({})
            total_objects += count
        except:
            pass
    
    # Calculate real storage size in MB
    try:
        stats = db.command('dbStats')
        storage_size_mb = stats.get('storageSize', 0) / (1024 * 1024)
    except:
        # Fallback to rough estimate if dbStats fails
        storage_size_mb = num_collections * 0.1
    
    storage_limit_mb = 512
    threshold_mb = 200.0  # Only notify if storage exceeds this threshold
    percentage = (storage_size_mb / storage_limit_mb) * 100 if storage_limit_mb > 0 else 0
    
    if percentage > 90:
        emoji = '🚨'
    elif percentage > 80:
        emoji = '⚠️'
    else:
        emoji = '📊'
    
    message = f"""{emoji} MongoDB Storage Monitor

📊 Collections: {num_collections}
📦 Documents: {total_objects}
📊 Actual Storage: {storage_size_mb:.2f} MB / {storage_limit_mb} MB
🏁 Usage: {percentage:.1f}%

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"""
    
    print(message)
    
    # Only send notification if threshold exceeded or manually triggered
    # GitHub Action environment variable GITHUB_EVENT_NAME can tell us if it's a manual trigger
    event_name = os.environ.get('GITHUB_EVENT_NAME', 'workflow_dispatch')
    
    if storage_size_mb >= threshold_mb or event_name == 'workflow_dispatch':
        send_telegram(message)
        print("Notification sent.")
    else:
        print(f"Current storage ({storage_size_mb:.2f}MB) is below threshold ({threshold_mb}MB). No notification sent.")

if __name__ == '__main__':
    main()
