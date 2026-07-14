import pymssql
import random
import time
import os
from dotenv import load_dotenv

# .env dosyasındaki şifreleri sisteme yükle
load_dotenv()

# 1. Veri Tabanı Bağlantı Ayarları
sunucu = 'localhost'
port = '1434'  # Seninle özel olarak ayarladığımız kapı numarası
kullanici = 'sa'
sifre = os.getenv('DB_PASSWORD')
veritabani = 'IoT_ColdChain'

try:
    print("Veri tabanına bağlanılıyor...")
    # SQL Server'a sızıyoruz
    conn = pymssql.connect(server=sunucu, port=port, user=kullanici, password=sifre, database=veritabani)
    cursor = conn.cursor()
    print("Bağlantı başarılı! Simülasyon başlatılıyor...\n")
    print("-" * 50)

    # 2. Sisteme Sanal Bir Sensör Ekleyelim (Daha önce eklenmemişse)
    cursor.execute("SELECT COUNT(*) FROM Sensors")
    kayit_sayisi = cursor.fetchone()[0]
    
    if kayit_sayisi == 0:
        print("Sistemde sensör bulunamadı. Yeni sanal sensör sicili oluşturuluyor...")
        cursor.execute("""
            INSERT INTO Sensors (SensorName, Location, AlertThreshold) 
            VALUES ('ESP32_Sanal_Sensor', 'Ankara_Merkez_Depo', 8.00)
        """)
        conn.commit()

    # Eklediğimiz sensörün kimlik numarasını (ID) ve sınır değerini SQL'den çekelim
    cursor.execute("SELECT TOP 1 SensorID, AlertThreshold FROM Sensors")
    sensor_bilgisi = cursor.fetchone()
    sensor_id = sensor_bilgisi[0]
    esik_deger = float(sensor_bilgisi[1])

    # 3. Veri Pompalamaya (ETL) Başlıyoruz
    while True:
        # 2.00 ile 15.00 derece arasında rastgele bir sıcaklık üretelim
        sicaklik = round(random.uniform(2.0, 15.0), 2)
        
        # A. Sıcaklık verisini Ana Tabloya yaz
        cursor.execute(f"INSERT INTO TemperatureLogs (SensorID, Temperature) VALUES ({sensor_id}, {sicaklik})")
        conn.commit()

        # B. Kural Kontrolü: Sıcaklık eşiği aştı mı?
        if sicaklik > esik_deger:
            print(f"🔴 ALARM! Sıcaklık {sicaklik}°C. Eşik değer ({esik_deger}) aşıldı!")
            
            # Son eklenen verinin numarasını bul
            cursor.execute("SELECT MAX(LogID) FROM TemperatureLogs")
            son_log_id = cursor.fetchone()[0]
            
            # Anomali tablosuna bu kural ihlalini kaydet
            hata_mesaji = f"Sıcaklık {sicaklik} dereceye ulasti."
            cursor.execute(f"INSERT INTO Anomalies (LogID, Description) VALUES ({son_log_id}, '{hata_mesaji}')")
            conn.commit()
        else:
            print(f"🟢 Normal. Sıcaklık: {sicaklik}°C")

        # 3 saniye bekle ve döngüyü tekrarla
        time.sleep(3)

except Exception as e:
    print(f"Kritik bir hata oluştu: {e}")
finally:
    # Program durdurulursa kapıyı güvenli bir şekilde kapat
    if 'conn' in locals():
        conn.close()