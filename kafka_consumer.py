import pymssql
import json
import os
from dotenv import load_dotenv
from kafka import KafkaConsumer

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

def get_db_connection():
    return pymssql.connect(server=DB_SERVER, port=DB_PORT, user=DB_USER, password=DB_PASSWORD, database=DB_NAME)

def load_sensor_rules():
    """
    To speed up the system, we read the threshold values of 150 sensors 
    from the database only once and keep them in RAM (as a Dictionary).
    """
    print("Fetching rule set (Metadata) from the database...")
    conn = get_db_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute("SELECT SensorID, MinThreshold, MaxThreshold FROM Sensors")
    
    # Create cache in the format: { 1: {'min': 2.0, 'max': 8.0}, 2: {'min': 1.0, 'max': 6.0} ... }
    rules = {row['SensorID']: {'min': row['MinThreshold'], 'max': row['MaxThreshold']} for row in cursor.fetchall()}
    conn.close()
    return rules

def main():
    print("🚀 Smart Rule Engine (ETL Pipeline) is starting...")
    rules_cache = load_sensor_rules()
    print(f"Total of {len(rules_cache)} sensor rules loaded into cache.")

    # Create the Consumer that will listen to Kafka
    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=[KAFKA_BROKER],
        auto_offset_reset='latest',
        enable_auto_commit=True,
        value_deserializer=lambda x: json.loads(x.decode('utf-8'))
    )

    # Keep the SQL connection continuously open for data write operations
    conn = get_db_connection()
    cursor = conn.cursor()

    print("-" * 50)
    print("🎧 Listening to Kafka... (Waiting for real-time data stream)")

    try:
        for message in consumer:
            data = message.value
            sensor_id = data['sensor_id']
            temp = data['temperature']

            # 1. Save the incoming temperature value to the DB and capture the generated LogID
            cursor.execute("""
                INSERT INTO TemperatureLogs (SensorID, Temperature) 
                OUTPUT inserted.LogID 
                VALUES (%s, %s)
            """, (sensor_id, temp))
            
            log_id = cursor.fetchone()[0]

            # 2. Rule Check (Anomaly Detection)
            sensor_rule = rules_cache.get(sensor_id)
            
            if sensor_rule:
                if temp < sensor_rule['min'] or temp > sensor_rule['max']:
                    print(f"🚨 ANOMALY! Sensor {sensor_id} | Temperature: {temp}°C (Limits: {sensor_rule['min']} - {sensor_rule['max']})")
                    
                    error_msg = f"Temperature exceeded critical limits with {temp} degrees!"
                    cursor.execute("""
                        INSERT INTO Anomalies (LogID, Description) 
                        VALUES (%s, %s)
                    """, (log_id, error_msg))
                else:
                    print(f"✅ Normal -> Sensor {sensor_id} | Temperature: {temp}°C")

            # Commit the transactions to the database
            conn.commit()

    except KeyboardInterrupt:
        print("\nRule Engine stopped.")
    finally:
        conn.close()
        consumer.close()

if __name__ == "__main__":
    main()