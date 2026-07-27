import pymssql
import random
import time
import os
from dotenv import load_dotenv

# Load environment variables from the .env file
load_dotenv()

# 1. Database Connection Settings
server = 'localhost'
port = '1434'  # Custom port number we specifically configured
user = 'sa'
password = os.getenv('DB_PASSWORD')
database = 'IoT_ColdChain'

try:
    print("Connecting to the database...")
    # Connecting to SQL Server
    conn = pymssql.connect(server=server, port=port, user=user, password=password, database=database)
    cursor = conn.cursor()
    print("Connection successful! Starting simulation...\n")
    print("-" * 50)

    # 2. Add a Virtual Sensor to the System (if not already added)
    cursor.execute("SELECT COUNT(*) FROM Sensors")
    record_count = cursor.fetchone()[0]
    
    if record_count == 0:
        print("No sensor found in the system. Creating a new virtual sensor record...")
        cursor.execute("""
            INSERT INTO Sensors (SensorName, Location, AlertThreshold) 
            VALUES ('ESP32_Sanal_Sensor', 'Ankara_Merkez_Depo', 8.00)
        """)
        conn.commit()

    # Fetch the ID and threshold value of the sensor from SQL
    cursor.execute("SELECT TOP 1 SensorID, AlertThreshold FROM Sensors")
    sensor_info = cursor.fetchone()
    sensor_id = sensor_info[0]
    threshold_value = float(sensor_info[1])

    # 3. Start Data Pumping (ETL Process)
    while True:
        # Generate temperature using Gaussian (Normal) distribution
        # Mean (mu) = 4.0°C, Standard Deviation (sigma) = 2.0
        # This ensures most data stays around 4°C, while extreme values (>8.00) occur rarely.
        temperature = round(random.gauss(4.0, 2.0), 2)
        
        # A. Insert temperature data securely and capture the inserted LogID instantly (Prevents Race Condition)
        cursor.execute("""
            INSERT INTO TemperatureLogs (SensorID, Temperature) 
            OUTPUT inserted.LogID 
            VALUES (%s, %s)
        """, (sensor_id, temperature))
        
        # Fetch the exact LogID of the row we just inserted
        last_log_id = cursor.fetchone()[0]
        conn.commit()

        # B. Rule Check: Did the temperature exceed the threshold?
        if temperature > threshold_value:
            print(f"🔴 ALARM! Temperature {temperature}°C. Threshold ({threshold_value}) exceeded!")
            
            # Save this rule violation to the Anomalies table securely
            error_message = f"Temperature reached {temperature} degrees."
            cursor.execute("""
                INSERT INTO Anomalies (LogID, Description) 
                VALUES (%s, %s)
            """, (last_log_id, error_message))
            conn.commit()
        else:
            print(f"🟢 Normal. Temperature: {temperature}°C")

        # Wait for 3 seconds and repeat the loop
        time.sleep(3)

except Exception as e:
    print(f"A critical error occurred: {e}")
finally:
    # Safely close the connection if the program stops
    if 'conn' in locals():
        conn.close()