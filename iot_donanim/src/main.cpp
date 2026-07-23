#include <Arduino.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// Sol taraftaki 3 numaralı pini tanımlıyoruz
const int oneWireBus = 4;

OneWire oneWire(oneWireBus);
DallasTemperature sensors(&oneWire);

void setup() {
  // Bilgisayar ile haberleşme hızını belirliyoruz (platformio.ini ile aynı olmalı)
  Serial.begin(115200);

  // Sensörü başlatıyoruz
  sensors.begin();
  Serial.println("Fiziksel Sensor Testi Basliyor...");
}

void loop() {
  // Sensöre sıcaklığı ölçmesi için komut gönderiyoruz
  sensors.requestTemperatures();

  // Ölçülen sıcaklık değerini alıyoruz
  float temperatureC = sensors.getTempCByIndex(0);

  // Değeri ekrana (terminale) yazdırıyoruz
  Serial.print("Sicaklik: ");
  Serial.print(temperatureC);
  Serial.println(" C");

  // İki ölçüm arasında 2 saniye bekliyoruz
  delay(2000);
}