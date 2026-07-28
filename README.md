# 🌡️ IoT Cold Chain Tracking System

This project is an end-to-end IoT ecosystem that ensures simulated sensor data is securely processed into a database and monitored in real-time via a mobile application.

## 🚀 Technologies Used
* **Database:** MS SQL Server (Isolated using Docker Container architecture)
* **Backend (API):** FastAPI (Python)
* **Data Simulation:** Python (Gaussian distribution-based data simulation)
* **Mobile Application:** Flutter (Cross-platform mobile client with background service & alerts)

## ⚙️ Project Architecture
1. The Python simulation engine generates realistic temperature data using statistical models.
2. Temperatures that violate predefined thresholds (e.g., > 8°C) are logged into the database as anomalies.
3. FastAPI establishes a secure bridge between the database and the mobile application, serving live and historical data in JSON format.
4. The Flutter mobile app monitors the system in real-time, displaying charts and triggering background alarm notifications.

## 🔒 Security
Database credentials and sensitive configurations are stored securely within a `.env` file and excluded from version control using `.gitignore`.