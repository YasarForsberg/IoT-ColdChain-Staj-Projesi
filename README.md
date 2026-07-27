🌡️ IoT Cold Chain Tracking System

This project is an end-to-end IoT ecosystem that ensures temperature data obtained from hardware (ESP32) is securely processed into a database and monitored in real-time via a mobile application.
🚀 Technologies Used

    Database: MS SQL Server (Isolated using Docker Container architecture)

    Backend (API): FastAPI (Python)

    Data Simulation: Python (For testing prior to real hardware integration)

    Mobile Application: Flutter (In development)

    Hardware: ESP32 (In development)

⚙️ Project Architecture

    Python simulation (or ESP32) generates/reads sensor data.

    Temperatures that violate the rules (e.g., > 8°C) are logged into the database as anomalies.

    FastAPI establishes a secure bridge between the database and the mobile application, serving data in JSON format.

🔒 Security

In this project, database passwords and sensitive information are kept within a .env file, and their privacy is ensured by utilizing .gitignore.