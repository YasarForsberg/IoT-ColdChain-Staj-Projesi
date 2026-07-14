# 🌡️ IoT Cold Chain (Soğuk Zincir) Takip Sistemi

Bu proje, bir donanım (ESP32) üzerinden alınan sıcaklık verilerinin güvenli bir şekilde veri tabanına işlenmesini ve mobil uygulama üzerinden anlık olarak takip edilmesini sağlayan uçtan uca bir IoT ekosistemidir.

## 🚀 Kullanılan Teknolojiler
* **Veri Tabanı:** MS SQL Server (Docker Container mimarisi ile izole edilmiştir)
* **Backend (API):** FastAPI (Python)
* **Veri Simülasyonu:** Python (Gerçek donanım entegrasyonu öncesi test için)
* **Mobil Uygulama:** Flutter (Geliştirme aşamasında)
* **Donanım:** ESP32 (Geliştirme aşamasında)

## ⚙️ Projenin Mimarisi
1. Python simülasyonu (veya ESP32) sensör verilerini üretir/okur.
2. Kuralları ihlal eden sıcaklıklar (örneğin > 8°C) anomali olarak veri tabanına kaydedilir.
3. FastAPI, veri tabanı ile mobil uygulama arasında güvenli bir köprü kurarak verileri JSON formatında sunar.

## 🔒 Güvenlik
Bu projede veri tabanı şifreleri ve hassas bilgiler `.env` dosyası içinde tutulmakta olup, `.gitignore` kullanılarak gizliliği sağlanmıştır.