from fastapi import FastAPI
import pymssql
import os
from dotenv import load_dotenv

# .env dosyasındaki şifreleri sisteme yükle
load_dotenv()

app = FastAPI()

# Bağlantı ayarları
DB_CONFIG = {
    'server': 'localhost',
    'port': '1434',
    'user': 'sa',
    'password': os.getenv('DB_PASSWORD'),
    'database': 'IoT_ColdChain'
}

@app.get("/")
def home():
    return {"mesaj": "IoT API Sunucusu Çalışıyor!"}

@app.get("/son-durum")
def get_son_durum():
    conn = pymssql.connect(**DB_CONFIG)
    cursor = conn.cursor(as_dict=True)
    cursor.execute("SELECT TOP 1 Temperature, LogDate FROM TemperatureLogs ORDER BY LogDate DESC")
    result = cursor.fetchone()
    conn.close()
    return result

@app.get("/gecmis-veriler")
def get_gecmis_veriler():
    try:
        conn = pymssql.connect(**DB_CONFIG)
        cursor = conn.cursor(as_dict=True)
        
        # Grafikte soldan sağa (eskiden yeniye) doğru düzgün çizilmesi için
        # önce son 50 veriyi alıyoruz, sonra onları kendi içinde tarihe göre sıralıyoruz.
        sorgu = """
        SELECT * FROM (
            SELECT TOP 50 Temperature, LogDate 
            FROM TemperatureLogs 
            ORDER BY LogDate DESC
        ) AS AltSorgu
        ORDER BY LogDate ASC
        """
        
        cursor.execute(sorgu)
        result = cursor.fetchall()  # fetchone() yerine tüm listeyi çekmek için fetchall() kullanıyoruz
        conn.close()
        
        return result
    
    except Exception as e:
        return {"hata": str(e)}