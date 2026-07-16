import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const IoTApp());
}

class IoTApp extends StatelessWidget {
  const IoTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Soğuk Zincir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const AnaEkran(),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  String sicaklikDegeri = 'Bağlanılıyor...';
  String sonLogTarihi = '';

  // Kontrol Değişkenleri
  int ayniVeriSayaci = 0;
  bool sensorKoptu = false;
  bool esikAsildi = false;
  double anlikSicaklik = 0.0;
  final double ESIK_DEGER = 8.0; // Belirlediğimiz sınır değer

  List<FlSpot> grafikVerileri = [];
  Timer? timer;

  @override
  void initState() {
    super.initState();
    veriGetir();
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (Timer t) => veriGetir(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> veriGetir() async {
    try {
      // 1. Anlık durumu çek
      final responseDurum = await http.get(
        Uri.parse('http://127.0.0.1:8000/son-durum'),
      );

      if (responseDurum.statusCode == 200) {
        final data = json.decode(responseDurum.body);

        if (data != null && data['Temperature'] != null) {
          setState(() {
            double hamSicaklik = data['Temperature'];
            String gelenTarih = data['LogDate'];

            // Sensör Kopma Kontrolü
            if (gelenTarih == sonLogTarihi) {
              ayniVeriSayaci++;
              if (ayniVeriSayaci >= 5) {
                sensorKoptu = true;
                esikAsildi =
                    false; // Koptuğunda kafa karıştırmaması için uyarıyı gizle
                sicaklikDegeri = 'Sensör Verisi Bekleniyor...';
              }
            } else {
              sonLogTarihi = gelenTarih;
              ayniVeriSayaci = 0;
              sensorKoptu = false;

              anlikSicaklik = hamSicaklik;
              esikAsildi =
                  anlikSicaklik >
                  ESIK_DEGER; // Sıcaklık 8.0'dan büyük mü kontrolü
              sicaklikDegeri = '${anlikSicaklik.toStringAsFixed(1)} °C';
            }
          });
        }
      }

      // 2. Geçmiş verileri çekip grafiği güncelle (Sensör çalışıyorsa)
      if (!sensorKoptu) {
        final responseGecmis = await http.get(
          Uri.parse('http://127.0.0.1:8000/gecmis-veriler'),
        );
        if (responseGecmis.statusCode == 200) {
          final List<dynamic> gecmisData = json.decode(responseGecmis.body);

          List<FlSpot> noktalar = [];
          for (int i = 0; i < gecmisData.length; i++) {
            noktalar.add(
              FlSpot(i.toDouble(), gecmisData[i]['Temperature'].toDouble()),
            );
          }

          setState(() {
            grafikVerileri = noktalar;
          });
        }
      }
    } catch (e) {
      setState(() {
        sensorKoptu = true;
        esikAsildi = false;
        sicaklikDegeri = 'Bağlantı Koptu';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anlık Sıcaklık Takibi'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Üst Kısım: Anlık Sıcaklık
            Text(
              sicaklikDegeri,
              style: TextStyle(
                fontSize: 48, // Biraz daha büyüttük
                // Renk Mantığı: Sensör koptuysa turuncu, eşik aşıldıysa kırmızı, normalse beyaz
                color: sensorKoptu
                    ? Colors.orange
                    : (esikAsildi ? Colors.redAccent : Colors.white),
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            // Dinamik Uyarı Banner'ı (Sadece eşik aşıldığında ve sensör kopmadığında görünür)
            if (esikAsildi && !sensorKoptu)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KRİTİK SICAKLIK: $ESIK_DEGER °C AŞILDI!',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              const SizedBox(
                height: 32,
              ), // Uyarı yokken grafiğin yukarı zıplamasını engellemek için boşluk tutucu

            const SizedBox(height: 20),

            // Alt Kısım: Çizgi Grafik
            Expanded(
              child: grafikVerileri.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: grafikVerileri,
                            isCurved: true,
                            color: Colors.cyanAccent,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.cyanAccent.withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
