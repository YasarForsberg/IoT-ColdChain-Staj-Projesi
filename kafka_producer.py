import pymssql
import random
import time
import os
import json
from datetime import datetime
from dotenv import load_dotenv
from kafka import KafkaProducer

# Load environment variables
load_dotenv()

# Database and Kafka Settings
DB_SERVER = 'localhost'
DB_PORT = '1434'
DB_USER = 'sa'
DB_PASSWORD = os.getenv('DB_PASSWORD')
DB_NAME = 'IoT_ColdChain'

KAFKA_BROKER = 'localhost:9092'
KAFKA_TOPIC = 'sensor_data'

def fetch_sensors_from_db():
    print("Connecting to SQL Server to fetch sensor list...")
    conn = pymssql.connect(server=DB_SERVER, port=DB_PORT, user=DB_USER, password=DB_PASSWORD, database=DB_NAME)
    cursor = conn.cursor(as_dict=True)
    
    cursor.execute("SELECT SensorID, SensorName, Category, MinThreshold, MaxThreshold FROM Sensors")
    sensors = cursor.fetchall()
    conn.close()
    return sensors

def generate_temperature(min_t, max_t):
    # 10% chance to generate an anomaly (out of bounds)
    is_anomaly = random.random() < 0.10
    
    if is_anomaly:
        return round(random.uniform(max_t, max_t + 5.0), 2)
    else:
        return round(random.uniform(min_t + 0.5, max_t - 0.5), 2)

def main():
    sensors = fetch_sensors_from_db()
    
    if not sensors:
        print("Error: No sensors found in the database!")
        return

    print(f"Total of {len(sensors)} sensors successfully loaded.")
    
    # Initialize Kafka Producer
    producer = KafkaProducer(
        bootstrap_servers=[KAFKA_BROKER],
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )
    
    print("-" * 50)
    print("🚀 Sensor data started streaming to Kafka! (Press CTRL+C to stop)")
    
    try:
        while True:
            for sensor in sensors:
                current_temp = generate_temperature(sensor['MinThreshold'], sensor['MaxThreshold'])
                
                # Payload to be sent to Kafka
                payload = {
                    "sensor_id": sensor['SensorID'],
                    "temperature": current_temp,
                    "timestamp": datetime.now().isoformat()
                }
                
                # Send data to Kafka Topic
                producer.send(KAFKA_TOPIC, value=payload)
                
                print(f"[{payload['timestamp']}] SENT -> Sensor: {payload['sensor_id']} | Temp: {current_temp}°C")
            
            # Wait 2 seconds before the next batch cycle
            time.sleep(2)
            
    except KeyboardInterrupt:
        print("\nData production stopped.")
    finally:
        producer.close()

if __name__ == "__main__":
    main()