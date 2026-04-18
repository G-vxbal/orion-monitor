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
    requests.post(url, json={'chat_id': chat_id, 'text': message, 'parse_mode': 'HTML'})

def main():
    client = pymongo.MongoClient(os.environ['MONGODB_URI'])
    db = client['admin']
    stats = db.command('dbStats')
    
    data_size_mb = stats.get('dataSize', 0) / (1024 * 1024)
    storage_size_mb = stats.get('storageSize', 0) / (1024 * 1024)
    index_size_mb = stats.get('indexSize', 0) / (1024 * 1024)
    num_collections = stats.get('collections', 0)
    num_objects = stats.get('objects', 0)
    
    storage_limit_mb = 512
    percentage = (storage_size_mb / storage_limit_mb) * 100
    
    if percentage > 90:
        emoji = '🚨'
        level = 'CRITICAL'
    elif percentage > 80:
        emoji = '⚠️'
        level = 'WARNING'
    else:
        emoji = '📊'
        level = 'INFO'
    
    message = f"""{emoji} MongoDB Storage Monitor

📊 Storage: {storage_size_mb:.2f} MB / {storage_limit_mb} MB ({percentage:.1f}%)
🔢 Collections: {num_collections}
📦 Objects: {num_objects}
💾 Data: {data_size_mb:.2f} MB
📇 Index: {index_size_mb:.2f} MB

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"""
    
    print(message)
    send_telegram(message)

if __name__ == '__main__':
    main()
