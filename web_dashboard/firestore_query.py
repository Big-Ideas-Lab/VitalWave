import os
import firebase_admin
from firebase_admin import credentials, firestore
from flask import jsonify
import pandas as pd
from datetime import datetime, timedelta
import time
import redis
from pathlib import Path


start_time = time.time()

# Path to private key json file
# change to your path to firestore json key
key_path = Path.home() / "Documents" / "VitalWaveSecrets" / "firebase-admin.json"

if not firebase_admin._apps:
    cred = credentials.Certificate(str(key_path))
    firebase_admin.initialize_app(cred)

db = firestore.client()
data_collection_name = 'demo_data'

# Initialize Redis instance
redis_host = os.environ.get('REDISHOST', 'localhost')
redis_port = int(os.environ.get('REDISPORT', 6378))

cache = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)  # Connect to Redis instance


def get_devices(user_id):
    try:
        # Firestore collection path
        doc_ref = db.collection('demo_data').document(user_id)
        
        # Fetch the document
        doc = doc_ref.get()
        
        if doc.exists:
            # Retrieve the 'devices' field
            devices = doc.to_dict().get('devices')
            return devices
        else:
            print(f"No document found for user_id: {user_id}")
            return None
    except Exception as e:
        print(f"Error fetching devices for user_id {user_id}: {e}")
        return None
    

# Generates a Range of Dates to Query for around the desired date
# Makes sure that date is in correct format
def generate_date_range(center_date, days_before, days_after):
    date_format = "%m-%d-%Y"
    center_date_obj = datetime.strptime(center_date, date_format)

    date_range = [(center_date_obj + timedelta(days=offset)).strftime(date_format)
                  for offset in range(-days_before, days_after + 1)]
    return date_range

# main function to get data (3 dataframes)
def get_data(user_id, watch_id, daydate, days_range=10):
    print("Date Queried for:", daydate)
    day_data = []
    minute_data = []
    hour_data = []

    day_date_range = generate_date_range(daydate, days_before=days_range, days_after=days_range)

    user_doc_ref = db.collection(data_collection_name).document(user_id)
    watch_subcollection = user_doc_ref.collection(watch_id)

    # # First, check Redis cache
    # cached_data = cache.get(user_id)  # Used to be document_id
    # if cached_data:
    #     return jsonify({data: cached_data, ‘source’: ‘cache’})
                        
    def process_subcollection(subcollection_name, data_list, date_range=None, is_day=False):
        if is_day:
            for date in date_range:
                date_subcollection_ref = watch_subcollection.document(subcollection_name).collection(date)

                doc_snapshot = date_subcollection_ref.document("00:00:00").get()
                if doc_snapshot.exists:
                    doc_data = doc_snapshot.to_dict()
                    if doc_data:
                        doc_data['Date'] = date
                        doc_data['Time'] = "00:00:00"
                        data_list.append(doc_data)
        else:
            date_subcollection_ref = watch_subcollection.document(subcollection_name).collection(daydate)

            for time_doc in date_subcollection_ref.stream():
                time_doc_id = time_doc.id

                doc_data = time_doc.to_dict()
                if doc_data:
                    doc_data['Date'] = daydate
                    doc_data['Time'] = time_doc_id
                    data_list.append(doc_data)

    process_subcollection('day', day_data, date_range=day_date_range, is_day=True)
    process_subcollection('minute', minute_data)
    process_subcollection('hour', hour_data)

    day_df = pd.DataFrame(day_data)
    minute_df = pd.DataFrame(minute_data)
    hour_df = pd.DataFrame(hour_data)

    return day_df, hour_df, minute_df 

# Cache the Firestore query result if not in cache, else return cache query
def fetch_data(user_id, watch_id, daydate):
    query_output = None
    cached_data_json = cache.get(user_id)
    if cached_data_json is not None:
        cached_data = json.loads(cached_data_json)
        watch_data = cached_data.get(watch_id)
        if watch_data is not None:
            query_data = pd.read_json(watch_data["hour"], orient='split')
            print(f"GET DATA------------------------------\n\n{query_data}\n\n")
        else:
            print(f"No data found for watch id {watch_id}")
            query_output = get_data(user_id, watch_id, daydate)
            query_out_cache = query_output
            # Serialize each dataframe in the tuple
            serialized_tuple = {
                "day": query_out_cache[0].to_json(orient='split'),
                "hour": query_out_cache[1].to_json(orient='split'),
                "minute": query_out_cache[2].to_json(orient='split')
            }

            print(f"FETCH DATA------------------------------\n\n{query_output}\n\n")
            cache.set(user_id,json.dumps({watch_id: serialized_tuple}))
            # cache.expire(user_id, 60)
    else:
        print(f"No data found for user id {user_id}")
        query_output = get_data(user_id, watch_id, daydate)
        query_out_cache = query_output
        # Serialize each dataframe in the tuple
        serialized_tuple = {
            "day": query_out_cache[0].to_json(orient='split'),
            "hour": query_out_cache[1].to_json(orient='split'),
            "minute": query_out_cache[2].to_json(orient='split')
        }

        print(f"FETCH DATA------------------------------\n\n{query_output}\n\n")
        cache.set(user_id,json.dumps({watch_id: serialized_tuple}))
        # cache.expire(user_id, 60)
    return query_output
