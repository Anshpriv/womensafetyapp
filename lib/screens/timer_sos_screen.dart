import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/timer_sos_service.dart';

class TimerSOSScreen extends StatefulWidget {
  const TimerSOSScreen({super.key});

  @override
  State<TimerSOSScreen> createState() => _TimerSOSScreenState();
}

class _TimerSOSScreenState extends State<TimerSOSScreen> {
  TimerSOSService? _timerService;
  bool _isTimerActive = false;
  Duration? _remainingTime;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    _timerService = TimerSOSService(uid: user.uid);
    await _checkTimerStatus();
  }

  Future<void> _checkTimerStatus() async {
    if (_timerService == null) return;

    final isActive = await _timerService!.isTimerActive();
    final remaining = await _timerService!.getRemainingTime();

    setState(() {
      _isTimerActive = isActive;
      _remainingTime = remaining;
    });
  }

  Future<void> _startTimer() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (selectedTime == null) return;

    final now = DateTime.now();
    var expectedReturn = DateTime(
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (expectedReturn.isBefore(now)) {
      expectedReturn = expectedReturn.add(const Duration(days: 1));
    }

    await _timerService?.startTimer(expectedReturn);
    await _checkTimerStatus();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⏰ Timer set for ${selectedTime.format(context)}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _checkIn() async {
    await _timerService?.checkIn();
    await _checkTimerStatus();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Checked in safely!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        title: const Text('Timer SOS'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _isTimerActive ? Icons.timer : Icons.timer_off,
                      size: 80,
                      color: _isTimerActive ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isTimerActive ? 'Timer Active' : 'No Active Timer',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isTimerActive && _remainingTime != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Time Remaining: ${_formatDuration(_remainingTime!)}',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (!_isTimerActive) ...[
              const Text(
                '"I\'m Going Out" Feature',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Set your expected return time. If you don\'t check in by then, SOS will be triggered automatically.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _startTimer,
                icon: const Icon(Icons.timer),
                label: const Text('Set Timer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ] else ...[
              const Text(
                'Check in to cancel auto-SOS',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _checkIn,
                icon: const Icon(Icons.check_circle),
                label: const Text('Check In - I\'m Safe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(height: 8),
                  Text(
                    'How it works:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Set your expected return time\n'
                    '2. Go about your day\n'
                    '3. Check in when you return safely\n'
                    '4. If you forget, SOS triggers automatically',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
