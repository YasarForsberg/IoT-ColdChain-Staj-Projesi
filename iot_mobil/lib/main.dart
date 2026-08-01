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
// EDGE LOGGING YARDIMCI FONKSİYONU
// ==========================================
Future<void> saveLocalLog(String description, String type) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  List<String> logs = prefs.getStringList('local_alarms') ?? [];

  String now = DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> newLog = {
    'Description': description,
    'DetectedAt': now,
    'Type': type,
  };

  logs.add(json.encode(newLog));

  if (logs.length > 100) {
    logs = logs.sublist(logs.length - 100);
  }

  await prefs.setStringList('local_alarms', logs);
}

// ==========================================
// BACKGROUND NOTIFICATION TRIGGER
// ==========================================
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (response.actionId == 'stop_alarm') {
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

  String lastLogDate = '';

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
      if (response.actionId == 'stop_alarm') {
        await alarmPlayer.stop();
        bgNotification.cancel(id: 11);
        bgNotification.cancel(id: 12);
        bgNotification.cancel(id: 13);

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

  Future<void> handleServerError() async {
    serverErrorTime ??= DateTime.now();

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'IoT Cold Chain (Connection Error)',
        content: 'Cannot reach the central server.',
      );
    }

    if (DateTime.now().difference(serverErrorTime!).inSeconds >= 60) {
      if (!alarmPlayedServer) {
        if (alarmPlayedSensor || alarmPlayedTemperature)
          await alarmPlayer.stop();
        sensorErrorTime = null;
        temperatureErrorTime = null;
        alarmPlayedSensor = false;
        alarmPlayedTemperature = false;
        notifiedSensor = false;
        notifiedTemperature = false;

        await saveLocalLog('Server Connection Lost (1 min)', 'server_error');

        await alarmPlayer.setReleaseMode(ReleaseMode.loop);
        await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

        bgNotification.show(
          id: 13,
          title: '🚨 ALARM: CONNECTION LOST!',
          body: 'CANNOT REACH SYSTEM FOR 1 MINUTE!',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'silent_visual_alarm',
              'Visual Alarm System',
              channelDescription: 'Alarms managed by audio player',
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
      await saveLocalLog('Server Connection Temporarily Lost', 'server_error');

      bgNotification.show(
        id: 3,
        title: '🔌 Server Connection Lost',
        body: 'System is unreachable, monitoring...',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'iot_channel',
            'System Alerts',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
      notifiedServer = true;
    }
  }

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
            sensorErrorTime ??= DateTime.now();
          } else {
            if (alarmPlayedSensor) await alarmPlayer.stop();
            lastLogDate = receivedDate;
            sensorErrorTime = null;
            alarmPlayedSensor = false;
            notifiedSensor = false;
          }

          bool isSensorOfficiallyLost = false;
          bool isSensorDataDelayed = false;

          if (sensorErrorTime != null) {
            int diffSeconds = DateTime.now()
                .difference(sensorErrorTime!)
                .inSeconds;

            if (diffSeconds >= 10) {
              isSensorDataDelayed = true;

              if (service is AndroidServiceInstance) {
                service.setForegroundNotificationInfo(
                  title: 'IoT Cold Chain (Sensor Lost)',
                  content: 'No new data from hardware!',
                );
              }
            }

            if (diffSeconds >= 60) {
              isSensorOfficiallyLost = true;

              if (!alarmPlayedSensor) {
                if (alarmPlayedTemperature) await alarmPlayer.stop();
                temperatureErrorTime = null;
                alarmPlayedTemperature = false;
                notifiedTemperature = false;

                await saveLocalLog(
                  'Sensor Data Flow Lost (1 min)',
                  'sensor_error',
                );

                await alarmPlayer.setReleaseMode(ReleaseMode.loop);
                await alarmPlayer.play(AssetSource('alarm_sesi.mp3'));

                bgNotification.show(
                  id: 11,
                  title: '🚨 ALARM: SENSOR DISCONNECTED!',
                  body: 'NO DATA FROM HARDWARE FOR 1 MINUTE!',
                  notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'silent_visual_alarm',
                      'Visual Alarm System',
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
            } else if (diffSeconds >= 10 &&
                !notifiedSensor &&
                !alarmPlayedSensor) {
              await saveLocalLog('Sensor Data Flow Delayed', 'sensor_error');

              bgNotification.show(
                id: 1,
                title: '📡 Sensor Connection Lost',
                body: 'No data from hardware, monitoring...',
                notificationDetails: const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'iot_channel',
                    'System Alerts',
                    importance: Importance.max,
                    priority: Priority.high,
                  ),
                ),
              );
              notifiedSensor = true;
            }
          }

          if (!isSensorOfficiallyLost) {
            if (!isSensorDataDelayed) {
              if (service is AndroidServiceInstance) {
                service.setForegroundNotificationInfo(
                  title: 'IoT Cold Chain Active',
                  content:
                      'Current Temp: ${currentTemperature.toStringAsFixed(1)}°C',
                );
              }
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
                    notificationDetails: const NotificationDetails(
                      android: AndroidNotificationDetails(
                        'silent_visual_alarm',
                        'Visual Alarm System',
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
              temperatureErrorTime = null;
              alarmPlayedTemperature = false;
              notifiedTemperature = false;
            }
          }
        }
      } else {
        await handleServerError();
      }
    } catch (e) {
      await handleServerError();
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String lastLogDate = '';
  int sameDataCounter = 0;
  ConnectionStateEnum status = ConnectionStateEnum.connecting;
  bool thresholdExceeded = false;
  double currentTemperature = 0.0;
  final double THRESHOLD_VALUE = 8.0;

  List<FlSpot> chartData = [];
  List<String> chartTimes = [];

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
        if (response.actionId == 'stop_alarm') {
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
                  saveLocalLog('Sensor Data Flow Interrupted', 'sensor_error');
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
            saveLocalLog('Server Returned Error Code', 'server_error');
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
          List<String> times = [];

          for (int i = 0; i < last50Data.length; i++) {
            points.add(
              FlSpot(i.toDouble(), last50Data[i]['Temperature'].toDouble()),
            );

            String rawDate = last50Data[i]['LogDate'].toString();
            String timeStr = "";
            try {
              if (!rawDate.endsWith('Z') && !rawDate.contains('+')) {
                rawDate += 'Z';
              }
              DateTime dt = DateTime.parse(rawDate).toLocal();
              timeStr =
                  "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
            } catch (e) {
              timeStr = rawDate.length > 16 ? rawDate.substring(11, 16) : "";
            }
            times.add(timeStr);
          }

          setState(() {
            chartData = points;
            chartTimes = times;
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
          saveLocalLog('Cannot Reach Server', 'server_error');
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

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0A0E21),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.05),
              border: Border(
                bottom: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.security_rounded,
                  size: 48,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'SYSTEM AUDIT',
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
            ),
            title: Text(
              'Alarm History',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white24,
              size: 16,
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AlarmHistoryScreen(serverIp: serverIp),
                ),
              );
            },
          ),
        ],
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
      key: _scaffoldKey,
      drawer: _buildDrawer(),
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
                      Row(
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
                              icon: const Icon(Icons.menu, size: 22),
                              color: Colors.white70,
                              tooltip: 'Menu',
                              onPressed: () {
                                _scaffoldKey.currentState?.openDrawer();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
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
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.calendar_month, size: 22),
                              color: Colors.white70,
                              tooltip: 'Historical Data',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HistoricalDataScreen(
                                      serverIp: serverIp,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'IoT Cold Chain',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
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
                                      titlesData: FlTitlesData(
                                        show: true,
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 40,
                                            getTitlesWidget: (value, meta) {
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8.0,
                                                ),
                                                child: Text(
                                                  '${value.toStringAsFixed(1)}°',
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.white54,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 30,
                                            interval: 10,
                                            getTitlesWidget: (value, meta) {
                                              if (value == meta.max &&
                                                  value % 10 != 0) {
                                                return const Text('');
                                              }

                                              int index = value.toInt();
                                              if (index >= 0 &&
                                                  index < chartTimes.length) {
                                                return Padding(
                                                  // YENİ: Saatleri sağa kaydırmak için left: 25.0 eklendi
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 10.0,
                                                        left: 25.0,
                                                      ),
                                                  child: Text(
                                                    chartTimes[index],
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white54,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return const Text('');
                                            },
                                          ),
                                        ),
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

// ==========================================
// HISTORICAL DATA ANALYSIS SCREEN
// ==========================================
class HistoricalDataScreen extends StatefulWidget {
  final String serverIp;

  const HistoricalDataScreen({super.key, required this.serverIp});

  @override
  State<HistoricalDataScreen> createState() => _HistoricalDataScreenState();
}

class _HistoricalDataScreenState extends State<HistoricalDataScreen> {
  DateTime? selectedDate;
  List<FlSpot> chartData = [];
  List<String> chartTimes = [];
  bool isLoading = false;
  String errorMessage = '';

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.cyanAccent,
              onPrimary: Colors.black,
              surface: Color(0xFF1D2235),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0A0E21),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _fetchHistoricalData(picked);
    }
  }

  Future<void> _fetchHistoricalData(DateTime date) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      chartData = [];
      chartTimes = [];
    });

    String formattedDate =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    try {
      final response = await http
          .get(
            Uri.parse(
              'http://${widget.serverIp}:8000/data-by-date?target_date=$formattedDate',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        if (data.isEmpty) {
          setState(() {
            errorMessage = 'No data found for this date.';
            isLoading = false;
          });
          return;
        }

        int targetDataPoints = 50;

        int chunkSize = (data.length / targetDataPoints).ceil();
        if (chunkSize < 1) chunkSize = 1;

        List<FlSpot> points = [];
        List<String> times = [];
        int spotIndex = 0;

        for (int i = 0; i < data.length; i += chunkSize) {
          int end = i + chunkSize;
          if (end > data.length) end = data.length;

          List<dynamic> chunk = data.sublist(i, end);

          double sumTemp = 0;
          for (var item in chunk) {
            sumTemp += item['Temperature'].toDouble();
          }
          double avgTemp = sumTemp / chunk.length;

          points.add(FlSpot(spotIndex.toDouble(), avgTemp));

          int midIndex = i + (chunk.length ~/ 2);
          String rawDate = data[midIndex]['LogDate'].toString();
          String timeStr = "";
          try {
            if (!rawDate.endsWith('Z') && !rawDate.contains('+')) {
              rawDate += 'Z';
            }
            DateTime dt = DateTime.parse(rawDate).toLocal();
            timeStr =
                "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
          } catch (e) {
            timeStr = rawDate.length > 16 ? rawDate.substring(11, 16) : "";
          }
          times.add(timeStr);
          spotIndex++;
        }

        setState(() {
          chartData = points;
          chartTimes = times;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Server returned error: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to connect to server.';
        isLoading = false;
      });
    }
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Historical Analysis',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGlassCard(
                child: Column(
                  children: [
                    Text(
                      'Select a Date to Analyze',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.cyanAccent),
                        ),
                      ),
                      onPressed: () => _selectDate(context),
                      icon: const Icon(
                        Icons.calendar_month,
                        color: Colors.cyanAccent,
                      ),
                      label: Text(
                        selectedDate == null
                            ? 'Choose Date'
                            : "${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                          fontSize: 16,
                        ),
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
                        'TEMPERATURE LOGS',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white54,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(child: _buildChartContent()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          errorMessage,
          style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 16),
        ),
      );
    }

    if (chartData.isEmpty) {
      return Center(
        child: Text(
          'Please select a date to view historical data.',
          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    double dynamicInterval = (chartData.length / 6).ceilToDouble();
    if (dynamicInterval == 0) dynamicInterval = 1;

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.blueGrey.withOpacity(0.8),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                return LineTooltipItem(
                  '${touchedSpot.y.toStringAsFixed(2)}°C',
                  GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    '${value.toStringAsFixed(1)}°',
                    style: GoogleFonts.poppins(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: dynamicInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.max && value % dynamicInterval != 0) {
                  return const Text('');
                }

                int index = value.toInt();
                if (index >= 0 && index < chartTimes.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Text(
                      chartTimes[index],
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: chartData,
            isCurved: true,
            curveSmoothness: 0.35,
            color: Colors.cyanAccent,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            shadow: Shadow(
              color: Colors.cyanAccent.withOpacity(0.4),
              blurRadius: 4,
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.cyanAccent.withOpacity(0.05),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// NEW PAGE: ALARM HISTORY (ANOMALY LOGS & LOCAL LOGS)
// ==========================================
class AlarmHistoryScreen extends StatefulWidget {
  final String serverIp;

  const AlarmHistoryScreen({super.key, required this.serverIp});

  @override
  State<AlarmHistoryScreen> createState() => _AlarmHistoryScreenState();
}

class _AlarmHistoryScreenState extends State<AlarmHistoryScreen> {
  List<dynamic> alarms = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchAlarms();
  }

  Future<void> _clearLocalLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_alarms');

    _fetchAlarms();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local anomaly logs cleared.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchAlarms() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http
          .get(Uri.parse('http://${widget.serverIp}:8000/anomalies'))
          .timeout(const Duration(seconds: 5));

      List<dynamic> dbAlarms = [];
      if (response.statusCode == 200) {
        dbAlarms = json.decode(response.body);
        for (var alarm in dbAlarms) {
          alarm['Type'] = 'temperature_error';
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      List<String> localLogsString = prefs.getStringList('local_alarms') ?? [];
      List<dynamic> localAlarms = localLogsString
          .map((log) => json.decode(log))
          .toList();

      List<dynamic> combinedAlarms = [...dbAlarms, ...localAlarms];

      combinedAlarms.sort((a, b) {
        DateTime dateA = DateTime.parse(a['DetectedAt'].toString());
        DateTime dateB = DateTime.parse(b['DetectedAt'].toString());
        return dateB.compareTo(dateA);
      });

      setState(() {
        alarms = combinedAlarms;
        isLoading = false;
        errorMessage = response.statusCode != 200
            ? 'Offline Mode: Showing only local connection logs.'
            : '';
      });
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      List<String> localLogsString = prefs.getStringList('local_alarms') ?? [];
      List<dynamic> localAlarms = localLogsString
          .map((log) => json.decode(log))
          .toList();

      localAlarms.sort((a, b) {
        DateTime dateA = DateTime.parse(a['DetectedAt'].toString());
        DateTime dateB = DateTime.parse(b['DetectedAt'].toString());
        return dateB.compareTo(dateA);
      });

      setState(() {
        alarms = localAlarms;
        errorMessage = 'Offline Mode: Showing only local connection logs.';
        isLoading = false;
      });
    }
  }

  String formatAlarmDate(String rawDate) {
    try {
      if (!rawDate.endsWith('Z') && !rawDate.contains('+')) {
        rawDate += 'Z';
      }
      DateTime dt = DateTime.parse(rawDate).toLocal();
      List<String> months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return "${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return rawDate;
    }
  }

  Widget _buildGlassCard({required Widget child, required Color baseColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: baseColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: baseColor.withOpacity(0.2), width: 1.5),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'System Alarm Logs',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            tooltip: 'Clear Local Logs',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1D2235),
                  title: Text(
                    'Clear Logs?',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                  content: Text(
                    'Are you sure you want to delete all local connection logs?',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'CANCEL',
                        style: GoogleFonts.poppins(color: Colors.white54),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearLocalLogs();
                      },
                      child: Text(
                        'CLEAR',
                        style: GoogleFonts.poppins(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.cyanAccent),
            tooltip: 'Refresh',
            onPressed: () {
              _fetchAlarms();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.redAccent),
              )
            : Column(
                children: [
                  if (errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.orangeAccent.withOpacity(0.2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.offline_bolt,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage,
                              style: GoogleFonts.poppins(
                                color: Colors.orangeAccent,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: alarms.isEmpty
                        ? Center(
                            child: Text(
                              'No anomalies recorded. System is perfectly stable.',
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : RefreshIndicator(
                            color: Colors.cyanAccent,
                            backgroundColor: const Color(0xFF1D2235),
                            onRefresh: _fetchAlarms,
                            // YENİ: Liste boş olsa bile aşağı çekilebilir yapıldı (AlwaysScrollableScrollPhysics)
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16.0),
                              itemCount: alarms.length,
                              itemBuilder: (context, index) {
                                final alarm = alarms[index];
                                final description =
                                    alarm['Description'] ?? 'Unknown Error';
                                final detectedAt = formatAlarmDate(
                                  alarm['DetectedAt'].toString(),
                                );

                                IconData iconData;
                                Color iconColor;

                                if (alarm['Type'] == 'server_error') {
                                  iconData = Icons.electrical_services_rounded;
                                  iconColor = Colors.orangeAccent;
                                } else if (alarm['Type'] == 'sensor_error') {
                                  iconData = Icons.wifi_off_rounded;
                                  iconColor = Colors.blueAccent;
                                } else {
                                  iconData = Icons.error_outline_rounded;
                                  iconColor = Colors.redAccent;
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: _buildGlassCard(
                                    baseColor: iconColor,
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: iconColor.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            iconData,
                                            color: iconColor,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                description,
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                detectedAt,
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (alarm['Temperature'] != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: iconColor.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: iconColor,
                                              ),
                                            ),
                                            child: Text(
                                              '${alarm['Temperature'].toStringAsFixed(1)}°C',
                                              style: GoogleFonts.orbitron(
                                                color: iconColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
