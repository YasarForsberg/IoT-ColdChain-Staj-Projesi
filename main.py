from fastapi import FastAPI, HTTPException
import pymssql
import os
from dotenv import load_dotenv

# Load environment variables from the .env file
load_dotenv()

app = FastAPI()

# Database connection settings
DB_CONFIG = {
    'server': 'localhost',
    'port': '1434',
    'user': 'sa',
    'password': os.getenv('DB_PASSWORD'),
    'database': 'IoT_ColdChain'
}

@app.get("/")
def home():
    return {"message": "IoT API Server is running!"}

@app.get("/latest-status")
def get_latest_status():
    try:
        conn = pymssql.connect(**DB_CONFIG)
        cursor = conn.cursor(as_dict=True)
        cursor.execute("SELECT TOP 1 Temperature, LogDate FROM TemperatureLogs ORDER BY LogDate DESC")
        result = cursor.fetchone()
        
        return result
        
    except Exception as e:
        # Return proper HTTP 500 error instead of crashing the mobile app
        raise HTTPException(status_code=500, detail=str(e))
        
    finally:
        # Guarantee connection closure even if the query fails or network drops
        if 'conn' in locals():
            conn.close()

@app.get("/historical-data")
def get_historical_data():
    try:
        conn = pymssql.connect(**DB_CONFIG)
        cursor = conn.cursor(as_dict=True)
        
        # To draw the chart correctly from left to right (oldest to newest):
        # First grab the latest 50 records, then sort them chronologically.
        query = """
        SELECT * FROM (
            SELECT TOP 50 Temperature, LogDate 
            FROM TemperatureLogs 
            ORDER BY LogDate DESC
        ) AS SubQuery
        ORDER BY LogDate ASC
        """
        
        cursor.execute(query)
        result = cursor.fetchall()  # Using fetchall() instead of fetchone() to retrieve the entire list
        
        return result
    
    except Exception as e:
        # Return proper HTTP 500 error instead of a fake 200 OK with a dictionary
        raise HTTPException(status_code=500, detail=str(e))
        
    finally:
        # Guarantee connection closure even if the query fails or network drops
        if 'conn' in locals():
            conn.close()