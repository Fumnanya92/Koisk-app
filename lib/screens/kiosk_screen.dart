import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../constants/app_config.dart';
import '../services/kiosk_service.dart';
import '../services/pin_service.dart';
import '../services/battery_monitoring_service.dart';
import '../utils/logger.dart';
import 'admin_panel_screen.dart';

class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> with WidgetsBindingObserver {
  int _tapCount = 0;
  DateTime? _lastTap;

  bool _isDeviceOwner = false;
  bool _isLoading = false;
  Timer? _screensaverTimer; // Auto-lock timer
  Timer? _clockTimer; // Clock update timer
  DateTime _currentTime = DateTime.now();
  
  // Battery monitoring
  BatteryMonitoringService? _batteryService;
  StreamSubscription<int>? _batterySubscription;

  @override
  void initState() {
    super.initState();
    Logger.info('Kiosk screen initialized', context: 'KioskScreen');
    WidgetsBinding.instance.addObserver(this);
    _checkDeviceOwnerStatus();
    _enforceImmersiveMode();
    _startClockTimer();
    _initializeBatteryMonitoring();
  }

  void _startClockTimer() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _initializeBatteryMonitoring() async {
    final batteryService = BatteryMonitoringService();
    _batteryService = batteryService;
    await batteryService.initialize();
    
    if (!mounted) return;

    setState(() {});
    
    // Listen to battery level changes and update UI
    _batterySubscription = batteryService.batteryStream.listen((level) {
      if (!mounted) return;
      
      setState(() {});
      
      // Show alert dialog for critical battery
      if (level <= 10) {
        _showCriticalBatteryAlert(level);
      }
    });
  }

  void _showCriticalBatteryAlert(int level) {
    if (!mounted) return;
    
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.battery_alert, color: Color(0xFFFF5252), size: 48),
        title: const Text(
          '🔴 CRITICAL BATTERY',
          style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Battery level: $level%\n\n'
          'Device may shut down soon. '
          'Please alert security to charge the kiosk immediately.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screensaverTimer?.cancel(); // Cancel any pending timer
    _clockTimer?.cancel(); // Cancel clock timer
    _batterySubscription?.cancel();
    _batteryService?.dispose(); // Clean up battery monitoring
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Logger.info('App lifecycle changed: $state', context: 'KioskScreen');

    if (state == AppLifecycleState.resumed) {
      _enforceImmersiveMode();
      KioskService.reactivateOnResume();
      _checkDefaultPin();
    }
  }

  Future<void> _enforceImmersiveMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      Logger.debug('Immersive mode re-enforced', context: 'KioskScreen');
    } catch (e, st) {
      Logger.warning(
        'Error enforcing immersive mode',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  Future<void> _checkDeviceOwnerStatus() async {
    try {
      final isOwner = await KioskService.isDeviceOwner();
      if (!mounted) return;

      setState(() => _isDeviceOwner = isOwner);

      if (!isOwner) {
        Logger.warning(
          'Device owner mode not active - security is limited',
          context: 'KioskScreen',
        );
        _showDeviceOwnerWarning();
      } else {
        Logger.info('Device owner mode confirmed', context: 'KioskScreen');
      }
    } catch (e, st) {
      Logger.error(
        'Error checking device owner status',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  Future<void> _checkDefaultPin() async {
    try {
      final isDefault = await PinService.isUsingDefaultPin();
      if (!mounted || !isDefault) return;

      Logger.warning('Default PIN still in use - prompting admin', context: 'KioskScreen');
      _showDefaultPinWarning();
    } catch (e, st) {
      Logger.error(
        'Error checking PIN status',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
    }
  }

  void _showDeviceOwnerWarning() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.warning, color: Colors.orange, size: 32),
        title: const Text(
          'Limited Security',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Device owner mode is not active. Security features are limited.\n\n'
          'For production deployment, set device owner mode using ADB:\n\n'
          'adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
  }

  void _showDefaultPinWarning() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.security, color: Colors.orange, size: 32),
        title: const Text(
          'Change Default PIN',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Your device is still using the default PIN (1234).\n\n'
          'This is a security risk. Please change it immediately using the admin panel.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showPinDialog();
            },
            child: const Text('Change Now', style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
  }

  void _handleSecretTap() {
    final now = DateTime.now();

    if (_lastTap != null && now.difference(_lastTap!) > const Duration(seconds: 3)) {
      _tapCount = 0;
    }

    _tapCount++;
    _lastTap = now;

    Logger.debug('Admin gesture count: $_tapCount', context: 'KioskScreen');

    if (_tapCount >= 5) {
      _tapCount = 0;
      _lastTap = null;
      Logger.info('Admin access code detected', context: 'KioskScreen');
      _showPinDialog();
    }
  }

  Future<void> _showPinDialog() async {
    // Cancel any existing timer
    _screensaverTimer?.cancel();
    
    // Create a timeout timer - 5 minutes of inactivity
    _screensaverTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        Logger.warning('PIN dialog timeout - auto-closing', context: 'KioskScreen');
        Navigator.of(context).pop();
        _showSnackbar('Session expired - please try again', color: Colors.orange);
      }
    });
    
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AdminPinDialog(
        onVerify: (pin) async {
          _screensaverTimer?.cancel(); // Cancel timer when user interacts
          await _verifyPin(ctx, pin);
        },
      ),
    );
    
    // Cancel timer when dialog closes
    _screensaverTimer?.cancel();
    return;
  }

  Future<void> _verifyPin(BuildContext ctx, String pin) async {
    try {
      if (pin.isEmpty) {
        _showSnackbar('Please enter PIN', color: Colors.orange);
        return;
      }

      if (pin.length < 4) {
        _showSnackbar('PIN must be at least 4 digits', color: Colors.orange);
        return;
      }

      final isValid = await PinService.verifyPin(pin);
      if (!mounted) return;

      if (!isValid) {
        Logger.warning('Invalid PIN attempted', context: 'KioskScreen');
        _showSnackbar('Invalid PIN', color: Colors.red);
        return;
      }

      Logger.info('Admin PIN verified successfully', context: 'KioskScreen');
      Navigator.pop(ctx);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
      );
    } catch (e, st) {
      Logger.error(
        'Error verifying PIN',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      _showSnackbar('Error verifying PIN', color: Colors.red);
    }
  }

  void _showSnackbar(String message, {required Color color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchAccessCodeNG() async {
    try {
      Logger.info('User tapped AccessCode NG button', context: 'KioskScreen');
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final success = await KioskService.openAccessCodeNG();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!success) {
        _showSnackbar(
          'AccessCode NG could not be opened. Please ensure it is installed.',
          color: Colors.orange,
        );
        Logger.warning('AccessCode NG app could not be opened', context: 'KioskScreen');
      }
    } catch (e, st) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      Logger.error(
        'Error launching AccessCode NG',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      _showSnackbar('Error launching app', color: Colors.red);
    }
  }

  Future<void> _callAdmin() async {
    try {
      Logger.info('User tapped call admin button', context: 'KioskScreen');
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final success = await KioskService.openDialer(AppConfig.adminContactNumber);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!success) {
        _showSnackbar('Dialer not available', color: Colors.orange);
        Logger.warning('Phone dialer not available', context: 'KioskScreen');
      }
    } catch (e, st) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      Logger.error(
        'Error opening dialer',
        context: 'KioskScreen',
        error: e is Error ? e : null,
        stackTrace: st,
      );
      _showSnackbar('Error opening dialer', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        Logger.debug('Back button pressed - ignoring', context: 'KioskScreen');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Column(
          children: [
            // Clock and Battery display at top
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 20, left: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Battery status on left
                  if (_batteryService != null)
                    StreamBuilder<int>(
                      stream: _batteryService!.batteryStream,
                      initialData: _batteryService!.currentBatteryLevel,
                      builder: (context, snapshot) {
                        final batteryService = _batteryService!;
                        final level = batteryService.currentBatteryLevel;
                        final status = batteryService.getBatteryStatus();
                        final isLow = batteryService.isLowBattery;
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isLow ? Colors.red.withValues(alpha: 0.2) : Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isLow ? Colors.red : Colors.green[400]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                level > 50 ? Icons.battery_full :
                                level > 20 ? Icons.battery_3_bar :
                                Icons.battery_alert,
                                color: isLow ? Colors.red : Colors.green[400],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                status,
                                style: TextStyle(
                                  color: isLow ? Colors.red : Colors.green[400],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  // Clock display on right
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[400]!, width: 1),
                    ),
                    child: Text(
                      _formatTime(_currentTime),
                      style: TextStyle(
                        color: Colors.blue[400],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                GestureDetector(
                  onTap: _handleSecretTap,
                  child: Column(
                    children: [
                      Icon(
                        Icons.security_rounded,
                        size: 80,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppConfig.estateName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppConfig.estateLocation,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Visitor Verification',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                ElevatedButton(
                  onPressed: _isLoading ? null : _launchAccessCodeNG,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: Colors.blue[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Column(
                          children: [
                            Icon(Icons.app_registration, size: 32),
                            SizedBox(height: 8),
                            Text(
                              'Open AccessCode NG',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Verify Visitor Access',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading ? null : _callAdmin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.phone, size: 28),
                      const SizedBox(height: 6),
                      const Text(
                        'Call Admin',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppConfig.adminContactNumber,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                if (!_isDeviceOwner)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Limited security mode. Device owner not set.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 60),
                Text(
                  'Infinity Estate Kiosk',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Made by Fynko Technologies',
                  style: TextStyle(
                    color: Colors.blue[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog({
    required this.onVerify,
  });

  final Future<void> Function(String pin) onVerify;

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  late final TextEditingController _controller;
  bool _obscureText = true;
  Timer? _timeoutTimer;
  int _secondsRemaining = 300; // 5 minutes

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _startTimeoutTimer();
    Logger.info('PIN dialog opened - timeout set to ${AppConfig.pinDialogTimeout.inSeconds}s', context: 'AdminPinDialog');
  }

  void _startTimeoutTimer() {
    _secondsRemaining = AppConfig.pinDialogTimeout.inSeconds;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsRemaining--);
      
      if (_secondsRemaining <= 0) {
        Logger.warning('PIN dialog timeout - auto-closing', context: 'AdminPinDialog');
        _timeoutTimer?.cancel();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    });
  }

  void _resetTimeout() {
    Logger.debug('PIN dialog timeout reset', context: 'AdminPinDialog');
    _startTimeoutTimer();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text(
        'Admin Access',
        style: TextStyle(color: Colors.white70, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              obscureText: _obscureText,
              autofocus: true,
              onChanged: (_) => _resetTimeout(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '****',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38,
                  ),
                  onPressed: () {
                    setState(() => _obscureText = !_obscureText);
                    _resetTimeout();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter admin PIN',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-closes in ${minutes}:${seconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: _secondsRemaining < 30 ? Colors.orange : Colors.white30,
                fontSize: 11,
                fontWeight: _secondsRemaining < 30 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timeoutTimer?.cancel();
            Navigator.pop(context);
          },
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () async {
            _timeoutTimer?.cancel();
            await widget.onVerify(_controller.text);
          },
          child: const Text('Verify', style: TextStyle(color: Color(0xFF4FC3F7))),
        ),
      ],
    );
  }
}
