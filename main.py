from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import pymssql
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = FastAPI(title="IoT Cold Chain API - Multi Sensor")

# Allow requests from mobile apps (Flutter, etc.) or Web (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db_connection():
    return pymssql.connect(
        server='localhost',
        port='1434',
        user='sa',
        password=os.getenv('DB_PASSWORD'),
        database='IoT_ColdChain'
    )

# ==========================================
# 1. LIST ALL SENSORS (For Main Screen)
# ==========================================
@app.get("/sensors")
def get_sensors():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT SensorID, SensorName, Category, MinThreshold, MaxThreshold FROM Sensors")
        return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

# ==========================================
# 2. LATEST STATUS OF A SPECIFIC SENSOR
# ==========================================
@app.get("/latest-status/{sensor_id}")
def get_latest_status(sensor_id: int):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch only the most recent record of the requested sensor
        cursor.execute("""
            SELECT TOP 1 Temperature, LogDate 
            FROM TemperatureLogs 
            WHERE SensorID = %d
            ORDER BY LogDate DESC
        """ % (sensor_id,))
        row = cursor.fetchone()
        
        if row:
            return row
        return {"error": "No data found for this sensor."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

# ==========================================
# 3. HISTORICAL DATA OF A SPECIFIC SENSOR (For Chart)
# ==========================================
@app.get("/historical-data/{sensor_id}")
def get_historical_data(sensor_id: int):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch the last 50 records of the relevant sensor and sort them chronologically
        cursor.execute("""
            SELECT * FROM (
                SELECT TOP 50 Temperature, LogDate 
                FROM TemperatureLogs 
                WHERE SensorID = %d
                ORDER BY LogDate DESC
            ) AS SubQuery 
            ORDER BY LogDate ASC
        """ % (sensor_id,))
        data = cursor.fetchall()
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

# ==========================================
# 4. SEARCH BY DATE AND SENSOR
# ==========================================
@app.get("/data-by-date/{sensor_id}")
def get_data_by_date(sensor_id: int, target_date: str):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        cursor.execute("""
            SELECT Temperature, LogDate 
            FROM TemperatureLogs 
            WHERE SensorID = %d AND CAST(LogDate AS DATE) = %s 
            ORDER BY LogDate ASC
        """, (sensor_id, target_date))
        data = cursor.fetchall()
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

# ==========================================
# 5. ANOMALIES (With Sensor Name Details)
# ==========================================
@app.get("/anomalies")
def get_anomalies():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Join three tables to detail which sensor triggered the anomaly
        cursor.execute("""
            SELECT 
                A.AnomalyID, 
                S.SensorName, 
                S.Category, 
                T.Temperature, 
                A.Description, 
                A.DetectedAt 
            FROM Anomalies A
            LEFT JOIN TemperatureLogs T ON A.LogID = T.LogID
            LEFT JOIN Sensors S ON T.SensorID = S.SensorID
            ORDER BY A.DetectedAt DESC
        """)
        anomalies = cursor.fetchall()
        return anomalies
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()