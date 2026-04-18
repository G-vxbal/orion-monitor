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
    
    # Get database info without admin command
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
    
    # Calculate approximate storage (rough estimate)
    storage_size_mb = num_collections * 0.1  # Rough estimate
    
    storage_limit_mb = 512
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
📊 Estimated Storage: ~{storage_size_mb:.1f} MB / {storage_limit_mb} MB

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"""
    
    print(message)
    send_telegram(message)

if __name__ == '__main__':
    main()
