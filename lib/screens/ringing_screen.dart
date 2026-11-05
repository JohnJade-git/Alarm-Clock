import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/alarm.dart';
import '../services/permission_service.dart';

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.alarm,
    required this.occurrenceId,
    required this.onDismiss,
    required this.onSnooze,
  });

  final Alarm alarm;
  final int occurrenceId;
  final Future<void> Function() onDismiss;
  final Future<void> Function() onSnooze;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  late bool _challengeCompleted;
  int _progress = 0;
  int? _initialStepCount;
  DateTime? _lastShake;
  String? _sensorError;
  StreamSubscription<UserAccelerometerEvent>? _shakeSubscription;
  StreamSubscription<StepCount>? _stepSubscription;

  int get _challengeTarget =>
      widget.alarm.challenge == WakeChallenge.shake ? 30 : 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _challengeCompleted = widget.alarm.challenge == WakeChallenge.none;
    if (!_challengeCompleted) unawaited(_startChallenge());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopChallengeSensors();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_challengeCompleted &&
        _sensorError != null) {
      unawaited(_startChallenge());
    }
  }

  Future<void> _startChallenge() async {
    await _stopChallengeSensors();
    if (!mounted || _challengeCompleted) return;
    setState(() => _sensorError = null);

    if (widget.alarm.challenge == WakeChallenge.shake) {
      _shakeSubscription =
          userAccelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 50),
          ).listen(
            _onAccelerometerEvent,
            onError: (Object error) => _showSensorError(
              'The motion sensor is unavailable. Try restarting the app.',
            ),
          );
      return;
    }

    if (!await PermissionService.ensureMotionPermission()) {
      _showSensorError(
        'Allow physical activity access in Settings to count your steps.',
      );
      return;
    }
    if (!mounted) return;
    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: (Object error) =>
          _showSensorError('The step counter is unavailable on this device.'),
    );
  }

  void _onAccelerometerEvent(UserAccelerometerEvent event) {
    if (_challengeCompleted) return;
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final now = DateTime.now();
    if (magnitude < 12 ||
        (_lastShake != null &&
            now.difference(_lastShake!) < const Duration(milliseconds: 350))) {
      return;
    }
    _lastShake = now;
    _addProgress();
  }

  void _onStepCount(StepCount event) {
    if (!mounted || _challengeCompleted) return;
    _initialStepCount ??= event.steps;
    final steps = event.steps - _initialStepCount!;
    if (steps > _progress) {
      setState(() {
        _progress = math.min(steps, _challengeTarget);
        _completeChallengeIfReady();
      });
    }
  }

  void _addProgress() {
    if (!mounted || _challengeCompleted) return;
    setState(() {
      _progress = math.min(_progress + 1, _challengeTarget);
      _completeChallengeIfReady();
    });
  }

  void _completeChallengeIfReady() {
    if (_progress < _challengeTarget) return;
    _challengeCompleted = true;
    _sensorError = null;
    unawaited(_stopChallengeSensors());
    HapticFeedback.heavyImpact();
  }

  Future<void> _stopChallengeSensors() async {
    await _shakeSubscription?.cancel();
    await _stepSubscription?.cancel();
    _shakeSubscription = null;
    _stepSubscription = null;
  }

  void _showSensorError(String message) {
    if (!mounted) return;
    setState(() => _sensorError = message);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: const Color(0xFF101426),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(
                Icons.alarm_rounded,
                size: 74,
                color: Color(0xFFB5A2FF),
              ),
              const SizedBox(height: 22),
              Text(
                TimeOfDay(
                  hour: widget.alarm.hour,
                  minute: widget.alarm.minute,
                ).format(context),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.alarm.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'It’s time to wake up',
                style: TextStyle(color: Colors.white70),
              ),
              if (widget.alarm.challenge != WakeChallenge.none) ...[
                const SizedBox(height: 24),
                _buildChallengeProgress(context),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 62,
                child: FilledButton.icon(
                  onPressed: _busy || !_challengeCompleted
                      ? null
                      : () => _runAction(widget.onSnooze),
                  icon: const Icon(Icons.snooze_rounded),
                  label: Text('Snooze · ${widget.alarm.snoozeMinutes} min'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF323750),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 62,
                child: FilledButton.icon(
                  onPressed: _busy || !_challengeCompleted
                      ? null
                      : () => _runAction(widget.onDismiss),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Dismiss alarm'),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildChallengeProgress(BuildContext context) {
    final title = widget.alarm.challenge == WakeChallenge.shake
        ? 'Shake your phone'
        : 'Walk around';
    final detail = widget.alarm.challenge == WakeChallenge.shake
        ? 'Shake 30 times to unlock alarm controls.'
        : 'Take 20 steps to unlock alarm controls.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF20263D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress / _challengeTarget,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          Text(
            '$_progress / $_challengeTarget',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_challengeCompleted)
            const Text(
              'Challenge complete. You can dismiss the alarm.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.greenAccent),
            ),
          if (_sensorError != null) ...[
            const SizedBox(height: 8),
            Text(
              _sensorError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
            TextButton(
              onPressed: () async {
                await PermissionService.openSystemSettings();
              },
              child: const Text('Open app settings'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!_challengeCompleted) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update alarm: $error')),
        );
        setState(() => _busy = false);
      }
    }
  }
}
