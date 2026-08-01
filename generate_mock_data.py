import pymssql
import random
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Database connection settings
DB_CONFIG = {
    'server': 'localhost',
    'port': '1434',
    'user': 'sa',
    'password': os.getenv('DB_PASSWORD'),
    'database': 'IoT_ColdChain'
}

def generate_historical_data():
    try:
        print("Connecting to the database...")
        conn = pymssql.connect(**DB_CONFIG)
        cursor = conn.cursor()

        days_to_generate = 10
        current_time = datetime.now()
        
        batch_data = []
        total_records = 0
        anomaly_count = 0

        print("Calculating data, please wait...")
        for day_offset in range(days_to_generate, -1, -1):
            target_day = current_time - timedelta(days=day_offset)
            
            # Start generating data from 08:00 AM for each day
            start_time = target_day.replace(hour=8, minute=0, second=0, microsecond=0)
            
            # 8 hours of data (28,800 seconds), generating a record every 3 seconds
            for second in range(0, 28800, 3):
                log_time = start_time + timedelta(seconds=second)
                
                # 1% probability for a temperature spike (Anomaly)
                is_anomaly = random.random() > 0.99 
                
                if is_anomaly:
                    # Critical temperature range
                    temp = round(random.uniform(8.1, 12.5), 2)
                    anomaly_count += 1
                else:
                    # Normal cold chain temperature range
                    temp = round(random.uniform(2.5, 7.5), 2)
                
                # Append to the list as a tuple for bulk insertion later
                batch_data.append((temp, log_time.strftime('%Y-%m-%d %H:%M:%S')))
                total_records += 1

        print(f"Total of {total_records} records and {anomaly_count} potential anomalies calculated.")
        
        print("STEP 1: Bulk inserting all data into the TemperatureLogs table...")
        # EXECUTEMANY: The most efficient way to insert large datasets in data engineering
        # INTEGRATED FIX 1: Added 'SensorID' column and hardcoded its value to 1
        cursor.executemany(
            "INSERT INTO TemperatureLogs (SensorID, Temperature, LogDate) VALUES (1, %s, %s)",
            batch_data
        )
        
        print("STEP 2: Detecting anomalies and transferring them to the Anomalies table...")
        # INTEGRATED FIX 2: Added the required 'Description' column to the INSERT statement
        anomaly_query = """
        INSERT INTO Anomalies (LogID, Description, DetectedAt)
        SELECT LogID, 'Simulated Anomaly: Temp > 8.0°C', LogDate
        FROM TemperatureLogs 
        WHERE Temperature > 8.0
        """
        
        cursor.execute(anomaly_query)
        
        # Commit all transactions to the database to make changes permanent
        conn.commit()
        print("Data generation and transfer SUCCESSFUL! ✅ Data integrity maintained.")

    except Exception as e:
        print(f"ERROR: {e}")
    finally:
        # Guarantee connection closure
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    generate_historical_data()