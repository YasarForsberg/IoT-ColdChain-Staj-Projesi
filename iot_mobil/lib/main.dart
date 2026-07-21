import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:typed_data'; // Israrcı alarm bayrağı (Int32List) için gerekli

// ==========================================
// 1. ARKA PLAN SERVİSİ KURULUMU
// ==========================================
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'iot_arkaplan_kanali',
    'IoT Cold Chain Arka Plan Servisi',
    description: 'Uygulama kapalıyken sıcaklık takibi yapar',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'iot_arkaplan_kanali',
      initialNotificationTitle: 'IoT Cold Chain Aktif',
      initialNotificationContent: 'Arka planda sıcaklık izleniyor...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
}

// ==========================================
// 2. EKRAN KAPALIYKEN ÇALIŞACAK MOTOR
// ==========================================
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final FlutterLocalNotificationsPlugin bgBildirim =
      FlutterLocalNotificationsPlugin();

  String sonLogTarihi = '';
  int ayniVeriSayaci = 0;

  bool bildirimGonderildiSicaklik = false;
  bool bildirimGonderildiSunucu = false;
  bool bildirimGonderildiSensor = false;

  DateTime? sicaklikHataZamani;
  DateTime? sensorHataZamani;
  DateTime? sunucuHataZamani;

  bool alarmCaldiSicaklik = false;
  bool alarmCaldiSensor = false;
  bool alarmCaldiSunucu = false;

  Timer.periodic(const Duration(seconds: 3), (timer) async {
    try {
      final response = await http
          .get(Uri.parse('http://192.168.1.11:8000/son-durum'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        sunucuHataZamani = null;
        alarmCaldiSunucu = false;

        final data = json.decode(response.body);

        if (data != null && data['Temperature'] != null) {
          double anlikSicaklik = data['Temperature'];
          String gelenTarih = data['LogDate'];

          if (gelenTarih == sonLogTarihi) {
            ayniVeriSayaci++;
            // 1. DURUM: SENSÖR KOPTU KONTROLÜ
            if (ayniVeriSayaci >= 3) {
              sensorHataZamani ??= DateTime.now();

              if (service is AndroidServiceInstance) {
                service.setForegroundNotificationInfo(
                  title: 'IoT Cold Chain (Sensör Koptu)',
                  content: 'Donanımdan veri alınamıyor!',
                );
              }

              if (DateTime.now().difference(sensorHataZamani!).inSeconds >=
                  60) {
                if (!alarmCaldiSensor) {
                  bgBildirim.show(
                    id: 11,
                    title: '🚨 ALARM: SENSÖR KOPTU!',
                    body: 'TAM 1 DAKİKADIR DONANIMDAN VERİ ALINAMIYOR!',
                    notificationDetails: NotificationDetails(
                      android: AndroidNotificationDetails(
                        'alarm_kanali',
                        'Acil Alarmlar',
                        channelDescription: 'Kritik Alarm Uyarıları',
                        importance: Importance.max,
                        priority: Priority.high,
                        color: Colors.red,
                        enableVibration: true,
                        fullScreenIntent: true,
                        additionalFlags: Int32List.fromList([4]),
                      ),
                    ),
                  );
                  alarmCaldiSensor = true;
                }
              } else if (!bildirimGonderildiSensor && !alarmCaldiSensor) {
                bgBildirim.show(
                  id: 1,
                  title: '📡 Sensör Bağlantısı Koptu',
                  body: 'Donanımdan veri gelmiyor, durum izleniyor...',
                  notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'iot_kanali',
                      'Sistem Uyarıları',
                      channelDescription: 'Sistem Uyarıları',
                      importance: Importance.max,
                      priority: Priority.high,
                    ),
                  ),
                );
                bildirimGonderildiSensor = true;
              }
            }
          } else {
            sonLogTarihi = gelenTarih;
            ayniVeriSayaci = 0;
            bildirimGonderildiSensor = false;
            bildirimGonderildiSunucu = false;
            sensorHataZamani = null;
            alarmCaldiSensor = false;

            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: 'IoT Cold Chain Aktif',
                content:
                    'Anlık Sıcaklık: ${anlikSicaklik.toStringAsFixed(1)}°C',
              );
            }

            // 2. DURUM: KRİTİK SICAKLIK KONTROLÜ
            if (anlikSicaklik > 8.0) {
              sicaklikHataZamani ??= DateTime.now();

              if (DateTime.now().difference(sicaklikHataZamani!).inSeconds >=
                  60) {
                if (!alarmCaldiSicaklik) {
                  bgBildirim.show(
                    id: 12,
                    title: '🚨 ALARM: KRİTİK SICAKLIK!',
                    body:
                        'SICAKLIK 1 DAKİKADIR EŞİĞİN ÜZERİNDE (${anlikSicaklik.toStringAsFixed(1)}°C)!',
                    notificationDetails: NotificationDetails(
                      android: AndroidNotificationDetails(
                        'alarm_kanali',
                        'Acil Alarmlar',
                        channelDescription: 'Kritik Alarm Uyarıları',
                        importance: Importance.max,
                        priority: Priority.high,
                        color: Colors.red,
                        enableVibration: true,
                        fullScreenIntent: true,
                        additionalFlags: Int32List.fromList([4]),
                      ),
                    ),
                  );
                  alarmCaldiSicaklik = true;
                }
              } else if (!bildirimGonderildiSicaklik && !alarmCaldiSicaklik) {
                bgBildirim.show(
                  id: 2,
                  title: '⚠️ Sıcaklık Uyarısı',
                  body: 'Sıcaklık ${anlikSicaklik.toStringAsFixed(1)}°C oldu.',
                  notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'iot_kanali',
                      'Sistem Uyarıları',
                      channelDescription: 'Sistem Uyarıları',
                      importance: Importance.max,
                      priority: Priority.high,
                      color: Colors.orange,
                    ),
                  ),
                );
                bildirimGonderildiSicaklik = true;
              }
            } else {
              bildirimGonderildiSicaklik = false;
              sicaklikHataZamani = null;
              alarmCaldiSicaklik = false;
            }
          }
        }
      } else {
        // 3. DURUM: SUNUCU YANIT VERMİYOR
        sunucuHataZamani ??= DateTime.now();

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'IoT Cold Chain (Sunucu Hatası)',
            content: 'Merkezi sunucu cevap vermiyor.',
          );
        }

        if (DateTime.now().difference(sunucuHataZamani!).inSeconds >= 60) {
          if (!alarmCaldiSunucu) {
            bgBildirim.show(
              id: 13,
              title: '🚨 ALARM: SUNUCU ÇÖKTÜ!',
              body: 'TAM 1 DAKİKADIR SUNUCUDAN YANIT ALINAMIYOR!',
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  'alarm_kanali',
                  'Acil Alarmlar',
                  channelDescription: 'Kritik Alarm Uyarıları',
                  importance: Importance.max,
                  priority: Priority.high,
                  color: Colors.red,
                  enableVibration: true,
                  fullScreenIntent: true,
                  additionalFlags: Int32List.fromList([4]),
                ),
              ),
            );
            alarmCaldiSunucu = true;
          }
        } else if (!bildirimGonderildiSunucu && !alarmCaldiSunucu) {
          bgBildirim.show(
            id: 3,
            title: '🔌 Sunucu Hatası',
            body: 'Merkezi sunucu cevap vermiyor.',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'iot_kanali',
                'Sistem Uyarıları',
                channelDescription: 'Sistem Uyarıları',
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
          );
          bildirimGonderildiSunucu = true;
        }
      }
    } catch (e) {
      // 3. DURUM: SUNUCUYA ULAŞILAMIYOR (BAĞLANTI KOPUK)
      sunucuHataZamani ??= DateTime.now();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'IoT Cold Chain (Bağlantı Yok)',
          content: 'Sunucuya ulaşılamıyor.',
        );
      }

      if (DateTime.now().difference(sunucuHataZamani!).inSeconds >= 60) {
        if (!alarmCaldiSunucu) {
          bgBildirim.show(
            id: 13,
            title: '🚨 ALARM: BAĞLANTI KOPTU!',
            body: 'TAM 1 DAKİKADIR SİSTEME ULAŞILAMIYOR!',
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                'alarm_kanali',
                'Acil Alarmlar',
                channelDescription: 'Kritik Alarm Uyarıları',
                importance: Importance.max,
                priority: Priority.high,
                color: Colors.red,
                enableVibration: true,
                fullScreenIntent: true,
                additionalFlags: Int32List.fromList([4]),
              ),
            ),
          );
          alarmCaldiSunucu = true;
        }
      } else if (!bildirimGonderildiSunucu && !alarmCaldiSunucu) {
        bgBildirim.show(
          id: 3,
          title: '🔌 Sunucu Bağlantısı Koptu',
          body: 'FastAPI sunucusuna ulaşılamıyor.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'iot_kanali',
              'Sistem Uyarıları',
              channelDescription: 'Sistem Uyarıları',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
        bildirimGonderildiSunucu = true;
      }
    }
  });
}

// ==========================================
// 3. UYGULAMANIN ANA BAŞLANGIÇ NOKTASI
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const IoTApp());
}

class IoTApp extends StatelessWidget {
  const IoTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Cold Chain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
      ),
      home: const AnaEkran(),
    );
  }
}

enum BaglantiDurumu { baglaniliyor, aktif, sensorBekleniyor, sunucuHatasi }

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});
  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> with WidgetsBindingObserver {
  String sonLogTarihi = '';
  int ayniVeriSayaci = 0;
  BaglantiDurumu durum = BaglantiDurumu.baglaniliyor;
  bool esikAsildi = false;
  double anlikSicaklik = 0.0;
  final double ESIK_DEGER = 8.0;
  List<FlSpot> grafikVerileri = [];
  Timer? timer;

  final FlutterLocalNotificationsPlugin _bildirimEklentisi =
      FlutterLocalNotificationsPlugin();

  bool bildirimGonderildiSicaklik = false;
  bool bildirimGonderildiSunucu = false;
  bool bildirimGonderildiSensor = false;

  bool arkaPlanAktif = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _arkaPlanDurumunuKontrolEt();

    bildirimSisteminiBaslat();
    veriGetir();
    timer = Timer.periodic(
      const Duration(seconds: 3),
      (Timer t) => veriGetir(),
    );
  }

  Future<void> _arkaPlanDurumunuKontrolEt() async {
    final service = FlutterBackgroundService();
    bool calisiyorMu = await service.isRunning();
    setState(() {
      arkaPlanAktif = calisiyorMu;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      FlutterBackgroundService().invoke('stopService');
    }
  }

  Future<void> bildirimSisteminiBaslat() async {
    const AndroidInitializationSettings androidAyarlari =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings kurulumAyarlari = InitializationSettings(
      android: androidAyarlari,
    );
    await _bildirimEklentisi.initialize(settings: kurulumAyarlari);

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _bildirimEklentisi
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> bildirimGonder(int id, String baslik, String icerik) async {
    const AndroidNotificationDetails androidDetay = AndroidNotificationDetails(
      'iot_kanali',
      'Sistem Uyarıları',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      color: Colors.red,
    );
    await _bildirimEklentisi.show(
      id: id,
      title: baslik,
      body: icerik,
      notificationDetails: const NotificationDetails(android: androidDetay),
    );
  }

  Future<void> veriGetir() async {
    try {
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
              if (ayniVeriSayaci >= 5) {
                durum = BaglantiDurumu.sensorBekleniyor;
                esikAsildi = false;
                if (!bildirimGonderildiSensor) {
                  bildirimGonder(
                    1,
                    '📡 SENSÖR BAĞLANTISI KOPTU',
                    'Donanımdan veri gelmiyor!',
                  );
                  bildirimGonderildiSensor = true;
                }
              }
            } else {
              sonLogTarihi = gelenTarih;
              ayniVeriSayaci = 0;
              durum = BaglantiDurumu.aktif;
              anlikSicaklik = hamSicaklik;
              esikAsildi = anlikSicaklik > ESIK_DEGER;

              bildirimGonderildiSunucu = false;
              bildirimGonderildiSensor = false;

              if (esikAsildi) {
                if (!bildirimGonderildiSicaklik) {
                  bildirimGonder(
                    2,
                    '⚠️ KRİTİK SICAKLIK UYARISI',
                    'Sıcaklık ${anlikSicaklik.toStringAsFixed(1)}°C seviyesine ulaştı!',
                  );
                  bildirimGonderildiSicaklik = true;
                }
              } else {
                bildirimGonderildiSicaklik = false;
              }
            }
          });
        }
      } else {
        setState(() {
          durum = BaglantiDurumu.sunucuHatasi;
          if (!bildirimGonderildiSunucu) {
            bildirimGonder(3, '🔌 SUNUCU HATASI', 'Sunucu cevap vermiyor.');
            bildirimGonderildiSunucu = true;
          }
        });
      }

      if (durum != BaglantiDurumu.sunucuHatasi) {
        final responseGecmis = await http
            .get(Uri.parse('http://192.168.1.11:8000/gecmis-veriler'))
            .timeout(const Duration(seconds: 3));
        if (responseGecmis.statusCode == 200) {
          final List<dynamic> gecmisData = json.decode(responseGecmis.body);
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
      setState(() {
        durum = BaglantiDurumu.sunucuHatasi;
        esikAsildi = false;
        if (!bildirimGonderildiSunucu) {
          bildirimGonder(3, '🔌 SUNUCU BAĞLANTISI KOPTU', 'Ağa ulaşılamıyor.');
          bildirimGonderildiSunucu = true;
        }
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48),
                      Text(
                        'IoT Cold Chain',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white70,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: arkaPlanAktif
                              ? Colors.red.withOpacity(0.1)
                              : Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: arkaPlanAktif
                                ? Colors.red.withOpacity(0.3)
                                : Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            arkaPlanAktif
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                          color: arkaPlanAktif
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          tooltip: arkaPlanAktif
                              ? 'Takibi Durdur'
                              : 'Takibi Başlat',
                          onPressed: () async {
                            final service = FlutterBackgroundService();

                            if (arkaPlanAktif) {
                              service.invoke('stopService');
                              setState(() {
                                arkaPlanAktif = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Arka plan takibi durduruldu.'),
                                  backgroundColor: Colors.redAccent,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              await service.startService();
                              setState(() {
                                arkaPlanAktif = true;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Arka plan takibi başlatıldı.'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
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
