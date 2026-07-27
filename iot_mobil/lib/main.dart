import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==========================================
// NEW AND CLEAN NOTIFICATION TRIGGER
// ==========================================
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (response.actionId == 'stop_alarm' || response.payload == 'stop_alarm') {
    FlutterBackgroundService().invoke('stopAlarmSound');
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'iot_background_channel',
    'IoT Cold Chain Background Service',
    description: 'Tracks temperature while the app is closed',
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
      notificationChannelId: 'iot_background_channel',
      initialNotificationTitle: 'IoT Cold Chain Active',
      initialNotificationContent: 'Monitoring temperature in background...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final AudioPlayer alarmPlayer = AudioPlayer(playerId: 'iot_emergency_alarm');

  // STATE VARIABLES MUST BE DECLARED BEFORE LISTENERS
  String lastLogDate = '';
  int sameDataCounter = 0;

  bool notifiedTemperature = false;
  bool notifiedServer = false;
  bool notifiedSensor = false;

  DateTime? temperatureErrorTime;
  DateTime? sensorErrorTime;
  DateTime? serverErrorTime;

  bool alarmPlayedTemperature = false;
  bool alarmPlayedSensor = false;
  bool alarmPlayedServer = false;

  service.on('stopService').listen((event) async {
    await alarmPlayer.stop();
    service.stopSelf();
  });

  service.on('stopAlarmSound').listen((event) async {
    await alarmPlayer.stop();
    final bgNotification = FlutterLocalNotificationsPlugin();
    bgNotification.cancel(id: 11);
    bgNotification.cancel(id: 12);
    bgNotification.cancel(id: 13);

    // RESET COUNTERS AND FLAGS
    if (alarmPlayedSensor) sensorErrorTime = DateTime.now();
    if (alarmPlayedTemperature) temperatureErrorTime = DateTime.now();
    if (alarmPlayedServer) serverErrorTime = DateTime.now();

    alarmPlayedSensor = false;
    alarmPlayedTemperature = false;
    alarmPlayedServer = false;
  });

  final FlutterLocalNotificationsPlugin bgNotification =
      FlutterLocalNotificationsPlugin();

  bgNotification.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      if (response.actionId == 'stop_alarm' ||
          response.payload == 'stop_alarm') {
        await alarmPlayer.stop();
        bgNotification.cancel(id: 11);
        bgNotification.cancel(id: 12);
        bgNotification.cancel(id: 13);

        // RESET COUNTERS AND FLAGS
        if (alarmPlayedSensor) sensorErrorTime = DateTime.now();
        if (alarmPlayedTemperature) temperatureErrorTime = DateTime.now();
        if (alarmPlayedServer) serverErrorTime = DateTime.now();

        alarmPlayedSensor = false;
        alarmPlayedTemperature = false;
        alarmPlayedServer = false;
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  Timer.periodic(const Duration(seconds: 3), (timer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String dynamicIp = prefs.getString('server_ip') ?? '192.168.1.11';

      final response = await http
          .get(Uri.parse('http://$dynamicIp:8000/latest-status'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        if (alarmPlayedServer) await alarmPlayer.stop();
        serverErrorTime = null;
        alarmPlayedServer = false;
        notifiedServer = false;

        final data = json.decode(response.body);

        if (data != null && data['Temperature'] != null) {
          double currentTemperature = data['Temperature'];
          String receivedDate = data['LogDate'];

          if (receivedDate == lastLogDate) {
            sameDataCounter++;
            if (sameDataCounter >= 3) {
              sensorErrorTime ??= DateTime.now();

              if (service is AndroidServiceInstance) {
                service.setForegroundNotificationInfo(
                  title: 'IoT Cold Chain (Sensor Disconnected)',
                  content: 'No data received from hardware!',
                );
              }

              if (DateTime.now().difference(sensorErrorTime!).inSeconds >= 60) {
                if (!alarmPlayedSensor) {
                  await alarmPlayer.setReleaseMode(ReleaseMode.loop);
                  await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

                  bgNotification.show(
                    id: 11,
                    title: '🚨 ALARM: SENSOR DISCONNECTED!',
                    body: 'NO DATA FROM HARDWARE FOR 1 MINUTE!',
                    payload: 'stop_alarm',
                    notificationDetails: const NotificationDetails(
                      android: AndroidNotificationDetails(
                        'silent_visual_alarm',
                        'Visual Alarm System',
                        channelDescription:
                            'Alarms managed by the audio player',
                        importance: Importance.max,
                        priority: Priority.high,
                        color: Colors.red,
                        enableVibration: true,
                        playSound: false,
                        fullScreenIntent: true,
                        actions: <AndroidNotificationAction>[
                          AndroidNotificationAction(
                            'stop_alarm',
                            'STOP ALARM',
                            showsUserInterface: false,
                            cancelNotification: true,
                          ),
                        ],
                      ),
                    ),
                  );
                  alarmPlayedSensor = true;
                }
              } else if (!notifiedSensor && !alarmPlayedSensor) {
                bgNotification.show(
                  id: 1,
                  title: '📡 Sensor Connection Lost',
                  body: 'No data from hardware, monitoring status...',
                  notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'iot_channel',
                      'System Alerts',
                      channelDescription: 'System Alerts',
                      importance: Importance.max,
                      priority: Priority.high,
                    ),
                  ),
                );
                notifiedSensor = true;
              }
            }
          } else {
            if (alarmPlayedSensor) await alarmPlayer.stop();
            lastLogDate = receivedDate;
            sameDataCounter = 0;
            notifiedSensor = false;
            sensorErrorTime = null;
            alarmPlayedSensor = false;

            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: 'IoT Cold Chain Active',
                content:
                    'Current Temp: ${currentTemperature.toStringAsFixed(1)}°C',
              );
            }

            if (currentTemperature > 8.0) {
              temperatureErrorTime ??= DateTime.now();

              if (DateTime.now().difference(temperatureErrorTime!).inSeconds >=
                  60) {
                if (!alarmPlayedTemperature) {
                  await alarmPlayer.setReleaseMode(ReleaseMode.loop);
                  await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

                  bgNotification.show(
                    id: 12,
                    title: '🚨 ALARM: CRITICAL TEMPERATURE!',
                    body:
                        'TEMPERATURE ABOVE THRESHOLD FOR 1 MINUTE (${currentTemperature.toStringAsFixed(1)}°C)!',
                    payload: 'stop_alarm',
                    notificationDetails: const NotificationDetails(
                      android: AndroidNotificationDetails(
                        'silent_visual_alarm',
                        'Visual Alarm System',
                        channelDescription:
                            'Alarms managed by the audio player',
                        importance: Importance.max,
                        priority: Priority.high,
                        color: Colors.red,
                        enableVibration: true,
                        playSound: false,
                        fullScreenIntent: true,
                        actions: <AndroidNotificationAction>[
                          AndroidNotificationAction(
                            'stop_alarm',
                            'STOP ALARM',
                            showsUserInterface: false,
                            cancelNotification: true,
                          ),
                        ],
                      ),
                    ),
                  );
                  alarmPlayedTemperature = true;
                }
              } else if (!notifiedTemperature && !alarmPlayedTemperature) {
                bgNotification.show(
                  id: 2,
                  title: '⚠️ Temperature Warning',
                  body:
                      'Temperature reached ${currentTemperature.toStringAsFixed(1)}°C.',
                  notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'iot_channel',
                      'System Alerts',
                      channelDescription: 'System Alerts',
                      importance: Importance.max,
                      priority: Priority.high,
                      color: Colors.orange,
                    ),
                  ),
                );
                notifiedTemperature = true;
              }
            } else {
              if (alarmPlayedTemperature) await alarmPlayer.stop();
              notifiedTemperature = false;
              temperatureErrorTime = null;
              alarmPlayedTemperature = false;
            }
          }
        }
      } else {
        serverErrorTime ??= DateTime.now();

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'IoT Cold Chain (Server Error)',
            content: 'Central server is not responding.',
          );
        }

        if (DateTime.now().difference(serverErrorTime!).inSeconds >= 60) {
          if (!alarmPlayedServer) {
            await alarmPlayer.setReleaseMode(ReleaseMode.loop);
            await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

            bgNotification.show(
              id: 13,
              title: '🚨 ALARM: SERVER CRASHED!',
              body: 'NO RESPONSE FROM SERVER FOR 1 MINUTE!',
              payload: 'stop_alarm',
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'silent_visual_alarm',
                  'Visual Alarm System',
                  channelDescription: 'Alarms managed by the audio player',
                  importance: Importance.max,
                  priority: Priority.high,
                  color: Colors.red,
                  enableVibration: true,
                  playSound: false,
                  fullScreenIntent: true,
                  actions: <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      'stop_alarm',
                      'STOP ALARM',
                      showsUserInterface: false,
                      cancelNotification: true,
                    ),
                  ],
                ),
              ),
            );
            alarmPlayedServer = true;
          }
        } else if (!notifiedServer && !alarmPlayedServer) {
          bgNotification.show(
            id: 3,
            title: '🔌 Server Error',
            body: 'Central server is not responding.',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'iot_channel',
                'System Alerts',
                channelDescription: 'System Alerts',
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
          );
          notifiedServer = true;
        }
      }
    } catch (e) {
      serverErrorTime ??= DateTime.now();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'IoT Cold Chain (No Connection)',
          content: 'Server unreachable.',
        );
      }

      if (DateTime.now().difference(serverErrorTime!).inSeconds >= 60) {
        if (!alarmPlayedServer) {
          await alarmPlayer.setReleaseMode(ReleaseMode.loop);
          await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

          bgNotification.show(
            id: 13,
            title: '🚨 ALARM: CONNECTION LOST!',
            body: 'CANNOT REACH SYSTEM FOR 1 MINUTE!',
            payload: 'stop_alarm',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'silent_visual_alarm',
                'Visual Alarm System',
                channelDescription: 'Alarms managed by the audio player',
                importance: Importance.max,
                priority: Priority.high,
                color: Colors.red,
                enableVibration: true,
                playSound: false,
                fullScreenIntent: true,
                actions: <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    'stop_alarm',
                    'STOP ALARM',
                    showsUserInterface: false,
                    cancelNotification: true,
                  ),
                ],
              ),
            ),
          );
          alarmPlayedServer = true;
        }
      } else if (!notifiedServer && !alarmPlayedServer) {
        bgNotification.show(
          id: 3,
          title: '🔌 Server Connection Lost',
          body: 'FastAPI server is unreachable.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'iot_channel',
              'System Alerts',
              channelDescription: 'System Alerts',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
        notifiedServer = true;
      }
    }
  });
}

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
      home: const MainScreen(),
    );
  }
}

enum ConnectionStateEnum { connecting, active, waitingForSensor, serverError }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  String lastLogDate = '';
  int sameDataCounter = 0;
  ConnectionStateEnum status = ConnectionStateEnum.connecting;
  bool thresholdExceeded = false;
  double currentTemperature = 0.0;
  final double THRESHOLD_VALUE = 8.0;
  List<FlSpot> chartData = [];
  Timer? timer;

  final FlutterLocalNotificationsPlugin _notificationPlugin =
      FlutterLocalNotificationsPlugin();

  bool notifiedTemperature = false;
  bool notifiedServer = false;
  bool notifiedSensor = false;

  bool isBackgroundActive = true;

  String serverIp = '192.168.1.11';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadSettings();
    _checkBackgroundStatus();
    initializeNotificationSystem();

    fetchData();
    timer = Timer.periodic(
      const Duration(seconds: 3),
      (Timer t) => fetchData(),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      serverIp = prefs.getString('server_ip') ?? '192.168.1.11';
    });
  }

  Future<void> _checkBackgroundStatus() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    setState(() {
      isBackgroundActive = isRunning;
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

  Future<void> initializeNotificationSystem() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId == 'stop_alarm' ||
            response.payload == 'stop_alarm') {
          FlutterBackgroundService().invoke('stopAlarmSound');
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> sendNotification(int id, String title, String body) async {
    const AndroidNotificationDetails androidDetail = AndroidNotificationDetails(
      'iot_channel',
      'System Alerts',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      color: Colors.red,
    );
    await _notificationPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetail),
    );
  }

  Future<void> fetchData() async {
    try {
      final responseStatus = await http
          .get(Uri.parse('http://$serverIp:8000/latest-status'))
          .timeout(const Duration(seconds: 3));

      if (responseStatus.statusCode == 200) {
        final data = json.decode(responseStatus.body);
        if (data != null && data['Temperature'] != null) {
          setState(() {
            double rawTemp = data['Temperature'];
            String receivedDate = data['LogDate'];

            if (receivedDate == lastLogDate) {
              sameDataCounter++;
              if (sameDataCounter >= 5) {
                status = ConnectionStateEnum.waitingForSensor;
                thresholdExceeded = false;
                if (!notifiedSensor) {
                  sendNotification(
                    1,
                    '📡 SENSOR CONNECTION LOST',
                    'No data from hardware!',
                  );
                  notifiedSensor = true;
                }
              }
            } else {
              lastLogDate = receivedDate;
              sameDataCounter = 0;
              status = ConnectionStateEnum.active;
              currentTemperature = rawTemp;
              thresholdExceeded = currentTemperature > THRESHOLD_VALUE;

              notifiedServer = false;
              notifiedSensor = false;

              if (thresholdExceeded) {
                if (!notifiedTemperature) {
                  sendNotification(
                    2,
                    '⚠️ CRITICAL TEMPERATURE WARNING',
                    'Temperature reached ${currentTemperature.toStringAsFixed(1)}°C!',
                  );
                  notifiedTemperature = true;
                }
              } else {
                notifiedTemperature = false;
              }
            }
          });
        }
      } else {
        setState(() {
          status = ConnectionStateEnum.serverError;
          if (!notifiedServer) {
            sendNotification(3, '🔌 SERVER ERROR', 'Server not responding.');
            notifiedServer = true;
          }
        });
      }

      if (status != ConnectionStateEnum.serverError) {
        final responseHistory = await http
            .get(Uri.parse('http://$serverIp:8000/historical-data'))
            .timeout(const Duration(seconds: 3));
        if (responseHistory.statusCode == 200) {
          final List<dynamic> historyData = json.decode(responseHistory.body);
          final last50Data = historyData.length > 50
              ? historyData.sublist(historyData.length - 50)
              : historyData;
          List<FlSpot> points = [];
          for (int i = 0; i < last50Data.length; i++) {
            points.add(
              FlSpot(i.toDouble(), last50Data[i]['Temperature'].toDouble()),
            );
          }
          setState(() {
            chartData = points;
          });
        }
      }
    } catch (e) {
      setState(() {
        status = ConnectionStateEnum.serverError;
        thresholdExceeded = false;
        if (!notifiedServer) {
          sendNotification(
            3,
            '🔌 SERVER CONNECTION LOST',
            'Network unreachable.',
          );
          notifiedServer = true;
        }
      });
    }
  }

  Future<void> _showSettings() async {
    TextEditingController ipController = TextEditingController(text: serverIp);

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _buildGlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings, color: Colors.cyanAccent),
                    const SizedBox(width: 10),
                    Text(
                      'SYSTEM SETTINGS',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: ipController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Server IP Address',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.wifi, color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.cyanAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.cyanAccent),
                      ),
                    ),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();

                      String newIp = ipController.text.trim();

                      await prefs.setString('server_ip', newIp);

                      setState(() {
                        serverIp = newIp;
                      });

                      Navigator.pop(context);

                      fetchData();
                    },
                    child: Text(
                      'SAVE',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    Color activeColor;
    String centerText;
    double fontSize;

    switch (status) {
      case ConnectionStateEnum.serverError:
        activeColor = Colors.red.withOpacity(0.6);
        centerText = 'SERVER\nERROR';
        fontSize = 22;
        break;
      case ConnectionStateEnum.waitingForSensor:
        activeColor = Colors.orangeAccent;
        centerText = 'AWAITING\nDATA';
        fontSize = 18;
        break;
      case ConnectionStateEnum.connecting:
        activeColor = Colors.grey;
        centerText = 'CONNECTING...';
        fontSize = 16;
        break;
      case ConnectionStateEnum.active:
        activeColor = thresholdExceeded ? Colors.redAccent : Colors.cyanAccent;
        centerText = '${currentTemperature.toStringAsFixed(1)}°';
        fontSize = 48;
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
                color: activeColor.withOpacity(0.3),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withOpacity(0.5),
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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.settings, size: 22),
                          color: Colors.white70,
                          tooltip: 'Settings',
                          onPressed: _showSettings,
                        ),
                      ),
                      Text(
                        'IoT Cold Chain',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white70,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: isBackgroundActive
                              ? Colors.red.withOpacity(0.1)
                              : Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isBackgroundActive
                                ? Colors.red.withOpacity(0.3)
                                : Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            isBackgroundActive
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                          ),
                          color: isBackgroundActive
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          tooltip: isBackgroundActive
                              ? 'Stop Tracking'
                              : 'Start Tracking',
                          onPressed: () async {
                            final service = FlutterBackgroundService();

                            if (isBackgroundActive) {
                              service.invoke('stopService');
                              setState(() {
                                isBackgroundActive = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Background tracking stopped.'),
                                  backgroundColor: Colors.redAccent,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              await service.startService();
                              setState(() {
                                isBackgroundActive = true;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Background tracking started.'),
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
                          'LIVE STATUS',
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
                                  end:
                                      (status ==
                                          ConnectionStateEnum.serverError)
                                      ? 0
                                      : (currentTemperature / 30.0).clamp(
                                          0.0,
                                          1.0,
                                        ),
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
                                      activeColor,
                                    ),
                                    strokeCap: StrokeCap.round,
                                  );
                                },
                              ),
                              Center(
                                child: Text(
                                  centerText,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.orbitron(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: activeColor,
                                    shadows: [
                                      Shadow(
                                        color: activeColor,
                                        blurRadius:
                                            status == ConnectionStateEnum.active
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
                        if (thresholdExceeded &&
                            status == ConnectionStateEnum.active)
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
                                  'CRITICAL TEMPERATURE ($THRESHOLD_VALUE°C)',
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
                            'TEMP HISTORY (LAST 50)',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white54,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: chartData.isEmpty
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
                                          spots: chartData,
                                          isCurved: true,
                                          color: activeColor,
                                          barWidth: 4,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          shadow: Shadow(
                                            color: activeColor,
                                            blurRadius: 10,
                                          ),
                                          belowBarData: BarAreaData(
                                            show: true,
                                            color: activeColor.withOpacity(0.1),
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
