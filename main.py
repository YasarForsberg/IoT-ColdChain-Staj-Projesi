from fastapi import FastAPI, HTTPException
import pymssql
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = FastAPI(title="IoT Cold Chain API")

# Database connection function
def get_db_connection():
    return pymssql.connect(
        server='localhost',
        port='1434',
        user='sa',
        password=os.getenv('DB_PASSWORD'),
        database='IoT_ColdChain'
    )

@app.get("/latest-status")
def get_latest_status():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch only the most recently added single record
        cursor.execute("""
            SELECT TOP 1 Temperature, LogDate 
            FROM TemperatureLogs 
            ORDER BY LogDate DESC
        """)
        row = cursor.fetchone()
        
        if row:
            return row
        return {"error": "No data found in the database."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

@app.get("/historical-data")
def get_historical_data():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch the last 50 records for the main screen chart and sort them chronologically (ASC)
        cursor.execute("""
            SELECT * FROM (
                SELECT TOP 50 Temperature, LogDate 
                FROM TemperatureLogs 
                ORDER BY LogDate DESC
            ) AS SubQuery 
            ORDER BY LogDate ASC
        """)
        data = cursor.fetchall()
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

@app.get("/data-by-date")
def get_data_by_date(target_date: str):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # Fetch all records belonging to the specific day (target_date) selected from the calendar
        cursor.execute("""
            SELECT Temperature, LogDate 
            FROM TemperatureLogs 
            WHERE CAST(LogDate AS DATE) = %s 
            ORDER BY LogDate ASC
        """, (target_date,))
        data = cursor.fetchall()
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()

# ==========================================
# NEW ENDPOINT: ALARM HISTORY (ANOMALIES)
# ==========================================
@app.get("/anomalies")
def get_anomalies():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(as_dict=True)
        # SQL JOIN: Anomaliler ile sıcaklık değerlerini LogID üzerinden birleştiriyoruz
        cursor.execute("""
            SELECT A.Description, A.DetectedAt, T.Temperature 
            FROM Anomalies A
            LEFT JOIN TemperatureLogs T ON A.LogID = T.LogID
            ORDER BY A.DetectedAt DESC
        """)
        anomalies = cursor.fetchall()
        return anomalies
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'conn' in locals():
            conn.close()