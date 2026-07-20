import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const IoTApp());
}

class IoTApp extends StatelessWidget {
  const IoTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermoTakip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const AnaEkran(),
    );
  }
}

// Bağlantı durumlarını net bir şekilde ayırıyoruz
enum BaglantiDurumu { baglaniliyor, aktif, sensorBekleniyor, sunucuHatasi }

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  String sonLogTarihi = '';
  int ayniVeriSayaci = 0;

  BaglantiDurumu durum = BaglantiDurumu.baglaniliyor;
  bool esikAsildi = false;
  double anlikSicaklik = 0.0;
  final double ESIK_DEGER = 8.0;

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
      // 3 Saniye içinde sunucu cevap vermezse Timeout (Sunucu Hatası) sayılacak
      final responseDurum = await http
          .get(Uri.parse('http://192.168.1.11:8000/son-durum'))
          .timeout(const Duration(seconds: 3));

      if (responseDurum.statusCode == 200) {
        final data = json.decode(responseDurum.body);

        if (data != null && data['Temperature'] != null) {
          setState(() {
            double hamSicaklik = data['Temperature'];
            String gelenTarih = data['LogDate'];

            if (gelenTarih == sonLogTarihi) {
              ayniVeriSayaci++;
              // Sunucu çalışıyor ama sensörden 5 turdur YENİ veri gelmiyor
              if (ayniVeriSayaci >= 5) {
                durum = BaglantiDurumu.sensorBekleniyor;
                esikAsildi = false;
              }
            } else {
              // Her şey kusursuz
              sonLogTarihi = gelenTarih;
              ayniVeriSayaci = 0;
              durum = BaglantiDurumu.aktif;
              anlikSicaklik = hamSicaklik;
              esikAsildi = anlikSicaklik > ESIK_DEGER;
            }
          });
        }
      } else {
        // Sunucu hata kodu döndürdü (örn: 500)
        setState(() => durum = BaglantiDurumu.sunucuHatasi);
      }

      // Sunucu tamamen çökmediyse geçmiş verileri de çek
      if (durum != BaglantiDurumu.sunucuHatasi) {
        final responseGecmis = await http
            .get(Uri.parse('http://192.168.1.11:8000/gecmis-veriler'))
            .timeout(const Duration(seconds: 3));

        if (responseGecmis.statusCode == 200) {
          final List<dynamic> gecmisData = json.decode(responseGecmis.body);

          // EKSİĞİMİZİ GİDERDİK: Gerçekten sadece SON 50 veriyi alıyoruz
          final son50Veri = gecmisData.length > 50
              ? gecmisData.sublist(gecmisData.length - 50)
              : gecmisData;

          List<FlSpot> noktalar = [];
          for (int i = 0; i < son50Veri.length; i++) {
            noktalar.add(
              FlSpot(i.toDouble(), son50Veri[i]['Temperature'].toDouble()),
            );
          }

          setState(() {
            grafikVerileri = noktalar;
          });
        }
      }
    } catch (e) {
      // Ağ hatası veya Timeout (Wi-Fi kapalı veya FastAPI sunucusu çökmüş)
      setState(() {
        durum = BaglantiDurumu.sunucuHatasi;
        esikAsildi = false;
      });
    }
  }

  Widget _buildGlassCard({required Widget child, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Arayüzdeki yazı ve renkleri Durum Makinesine göre belirliyoruz
    Color aktifRenk;
    String merkezYazi;
    double yaziBoyutu;

    switch (durum) {
      case BaglantiDurumu.sunucuHatasi:
        aktifRenk = Colors.red.withOpacity(0.6);
        merkezYazi = 'SUNUCU\nHATASI';
        yaziBoyutu = 22;
        break;
      case BaglantiDurumu.sensorBekleniyor:
        aktifRenk = Colors.orangeAccent;
        merkezYazi = 'VERİ\nBEKLENİYOR';
        yaziBoyutu = 18;
        break;
      case BaglantiDurumu.baglaniliyor:
        aktifRenk = Colors.grey;
        merkezYazi = 'BAĞLANILIYOR...';
        yaziBoyutu = 16;
        break;
      case BaglantiDurumu.aktif:
        aktifRenk = esikAsildi ? Colors.redAccent : Colors.cyanAccent;
        merkezYazi = '${anlikSicaklik.toStringAsFixed(1)}°';
        yaziBoyutu = 48;
        break;
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: aktifRenk.withOpacity(0.3),
                boxShadow: [
                  BoxShadow(
                    color: aktifRenk.withOpacity(0.5),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.4),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'TERMOTAKİP IOT',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildGlassCard(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CANLI DURUM',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white54,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: (durum == BaglantiDurumu.sunucuHatasi)
                                      ? 0
                                      : (anlikSicaklik / 30.0).clamp(0.0, 1.0),
                                ),
                                duration: const Duration(milliseconds: 1500),
                                builder: (context, value, _) {
                                  return CircularProgressIndicator(
                                    value: value,
                                    strokeWidth: 12,
                                    backgroundColor: Colors.white.withOpacity(
                                      0.1,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      aktifRenk,
                                    ),
                                    strokeCap: StrokeCap.round,
                                  );
                                },
                              ),
                              Center(
                                child: Text(
                                  merkezYazi,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.orbitron(
                                    fontSize: yaziBoyutu,
                                    fontWeight: FontWeight.bold,
                                    color: aktifRenk,
                                    shadows: [
                                      Shadow(
                                        color: aktifRenk,
                                        blurRadius:
                                            durum == BaglantiDurumu.aktif
                                            ? 20
                                            : 5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (esikAsildi && durum == BaglantiDurumu.aktif)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'KRİTİK SICAKLIK ($ESIK_DEGER°C)',
                                  style: GoogleFonts.poppins(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ISI GEÇMİŞİ (SON 50 VERİ)',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white54,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: grafikVerileri.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : LineChart(
                                    LineChartData(
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (value) =>
                                            FlLine(
                                              color: Colors.white.withOpacity(
                                                0.1,
                                              ),
                                              strokeWidth: 1,
                                            ),
                                      ),
                                      titlesData: const FlTitlesData(
                                        show: false,
                                      ),
                                      borderData: FlBorderData(show: false),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: grafikVerileri,
                                          isCurved: true,
                                          color: aktifRenk,
                                          barWidth: 4,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          shadow: Shadow(
                                            color: aktifRenk,
                                            blurRadius: 10,
                                          ),
                                          belowBarData: BarAreaData(
                                            show: true,
                                            color: aktifRenk.withOpacity(0.1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
