import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Đồng Hồ Báo Thức',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      home: AlarmPage(onThemeToggle: _toggleTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Alarm {
  final String id;
  final TimeOfDay time;
  bool isActive;

  Alarm({required this.id, required this.time, this.isActive = true});
}

class AlarmPage extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const AlarmPage({super.key, required this.onThemeToggle});

  @override
  _AlarmPageState createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  late FlutterTts _flutterTts;
  List<Alarm> alarms = [];
  int alarmCount = 0;
  TimeOfDay _selectedTime = TimeOfDay.now();
  String? _notificationMessage;
  String _currentTime = '';
  late Timer _timer;
  Alarm? _currentAlarm;

  void _showSaveAlarmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Đặt Báo Thức'),
          content: Text('Bạn có muốn đặt báo thức vào lúc ${_formatTime(_selectedTime)} không?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Đóng hộp thoại
              },
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () {
                _setAlarm(); // Đặt báo thức mới
                Navigator.of(context).pop(); // Đóng hộp thoại
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }


  @override
  void initState() {
    super.initState();
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    _flutterTts = FlutterTts();
    _initializeNotifications();
    tz.initializeTimeZones();
    _startClock();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      setState(() {
        _currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(
            2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });

      _checkAlarms(now);
    });
  }

  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
    InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _checkAlarms(DateTime currentTime) {
    for (var alarm in alarms) {
      final alarmTime = DateTime(currentTime.year, currentTime.month,
          currentTime.day, alarm.time.hour, alarm.time.minute);

      if (alarm.isActive &&
          alarmTime.isBefore(currentTime) &&
          alarmTime.add(const Duration(minutes: 1)).isAfter(currentTime)) {
        _onAlarmTriggered(alarm);
      }
    }
  }

  Future<void> _onAlarmTriggered(Alarm alarm) async {
    if (_currentAlarm != null)
      return; // Chỉ xử lý một báo thức tại một thời điểm

    _currentAlarm = alarm;
    await _flutterTts.speak("Đến giờ báo thức!");

    setState(() {
      _notificationMessage = "Báo thức: ${alarm.id} đã được kích hoạt!";
    });

    // Hiển thị thông báo với các tùy chọn
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Báo Thức!'),
          content: const Text('Đến giờ dậy rồi'),
          actions: [
            TextButton(
              onPressed: () => _dismissAlarm(),
              child: const Text('Đóng báo thức'),
            ),
            TextButton(
              onPressed: () => _snoozeAlarm(),
              child: const Text('Báo lại sau (5 phút)'),
            ),
          ],
        );
      },
    );
  }

  void _dismissAlarm() {
    _currentAlarm?.isActive = false; // Dừng báo thức
    _currentAlarm = null;
    Navigator.of(context).pop(); // Đóng thông báo
    setState(() {
      _notificationMessage = null;
    });
  }

  void _snoozeAlarm() {
    if (_currentAlarm != null) {
      final snoozeTime = TimeOfDay(
        hour: (_selectedTime.hour + (_selectedTime.minute + 5) ~/ 60) % 24,
        minute: (_selectedTime.minute + 5) % 60,
      );

      alarms.add(Alarm(id: '${_currentAlarm!.id}_snooze', time: snoozeTime));
    }

    _dismissAlarm();
  }

  Future<void> _setAlarm() async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    String alarmId = 'alarm_${alarmCount++}';
    alarms.add(Alarm(id: alarmId, time: _selectedTime));

    await _notificationsPlugin.zonedSchedule(
      alarmId.hashCode,
      'Báo Thức',
      'Đến giờ báo thức!',
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'your_channel_id',
          'your_channel_name',
          channelDescription: 'Mô tả kênh của bạn',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    setState(() {});
  }

  void _toggleAlarm(Alarm alarm) {
    setState(() {
      alarm.isActive = !alarm.isActive;
      if (!alarm.isActive) {
        _cancelAlarm(alarm);
      } else {
        _setAlarm();
      }
    });
  }

  Future<void> _cancelAlarm(Alarm alarm) async {
    await _notificationsPlugin.cancel(alarm.id.hashCode);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _deleteAlarm(Alarm alarm) {
    setState(() {
      _cancelAlarm(alarm);
      alarms.remove(alarm);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo Thức'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onThemeToggle, // Chuyển đổi giữa chế độ sáng/tối
          ),
        ],
      ),
      body: Container(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '${_currentTime.substring(0, 5)}', // Chỉ hiển thị giờ và phút
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        ':${_currentTime.substring(6, 8)}', // Hiển thị giây
                        style: const TextStyle(fontSize: 24),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (time != null) {
                        _selectedTime = time;
                        _showSaveAlarmDialog();
                      }
                    },
                    child: const Icon(Icons.add, size: 36), // Dấu cộng lớn
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: alarms.length,
                itemBuilder: (context, index) {
                  final alarm = alarms[index];
                  return ListTile(
                    title: Text('Báo thức: ${_formatTime(alarm.time)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: alarm.isActive,
                          onChanged: (value) => _toggleAlarm(alarm),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteAlarm(alarm),
                        ),
                      ],
                    ),
                    onLongPress: () => _deleteAlarm(alarm),
                  );
                },
              ),
            ),
            if (_notificationMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _notificationMessage!,
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _setAlarm,
        child: const Icon(Icons.add, size: 36), // Dấu cộng lớn
      ),
    );
  }
}