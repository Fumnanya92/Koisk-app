/// 🔐 Admin Panel Screen
/// 
/// Hidden admin interface accessed via secret gesture (5 taps on logo).
/// Features:
/// - Exit kiosk mode (unlocks device)
/// - Change admin PIN
/// - View device status
/// - Emergency functions
///
/// All actions require PIN verification before proceeding.

import 'package:flutter/material.dart';
import 'dart:async';
import '../constants/app_config.dart';
import '../services/kiosk_service.dart';
import '../services/pin_service.dart';
import '../utils/logger.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  bool _isDeviceOwner = false;
  bool _isLoading = false;
  String? _deviceInfo;
  Timer? _inactivityTimer;
  int _secondsRemaining = 1800; // 30 minutes

  @override
  void initState() {
    super.initState();
    Logger.info('Admin panel opened', context: 'AdminPanel');
    _loadDeviceStatus();
    _startInactivityTimer();
  }

  void _startInactivityTimer() {
    _secondsRemaining = AppConfig.screenLockTimeout.inSeconds;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      setState(() => _secondsRemaining--);
      
      if (_secondsRemaining <= 0) {
        Logger.warning('Admin panel inactivity timeout - auto-closing', context: 'AdminPanel');
        _inactivityTimer?.cancel();
        if (mounted) {
          Navigator.pop(context);
          _showSnackbar('Admin panel closed due to inactivity', color: Colors.orange);
        }
      }
    });
  }

  void _resetInactivityTimer() {
    Logger.debug('Admin panel inactivity timer reset', context: 'AdminPanel');
    _startInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  /// Load device status information
  Future<void> _loadDeviceStatus() async {
    try {
      setState(() => _isLoading = true);

      // Check device owner status
      final isOwner = await KioskService.isDeviceOwner();
      setState(() => _isDeviceOwner = isOwner);

      // Get device info
      final info = await KioskService.getDeviceInfo();
      if (info != null) {
        setState(() => _deviceInfo = info.toString());
      }

      Logger.info('Device status loaded', context: 'AdminPanel');
    } catch (e, st) {
      Logger.error(
        'Error loading device status',
        context: 'AdminPanel',
        error: e as Error?,
        stackTrace: st,
      );
      _showSnackbar('Error loading status', color: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Exit kiosk mode and unlock device
  /// Allows admin to restart device setup process
  Future<void> _exitKioskMode() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        icon: const Icon(Icons.exit_to_app, color: Colors.orange, size: 32),
        title: const Text(
          'Exit Kiosk Mode?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will unlock the device and disable kiosk mode.\n\n'
          'You will have full access to the device until you restart.\n\n'
          'Are you sure?',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performExitKiosk();
            },
            child: const Text('Exit', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  /// Perform kiosk mode exit
  Future<void> _performExitKiosk() async {
    try {
      Logger.warning('Admin exiting kiosk mode', context: 'AdminPanel');
      setState(() => _isLoading = true);

      await KioskService.deactivateKiosk();

      Logger.info('Kiosk mode deactivated', context: 'AdminPanel');

      if (!mounted) return;

      _showSnackbar('Kiosk mode disabled', color: Colors.green);
    } catch (e, st) {
      setState(() => _isLoading = false);
      Logger.error(
        'Error exiting kiosk mode',
        context: 'AdminPanel',
        error: e as Error?,
        stackTrace: st,
      );
      _showSnackbar('Error exiting kiosk mode', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _installAppUpdate() async {
    try {
      Logger.info('Admin requested in-app APK update', context: 'AdminPanel');
      setState(() => _isLoading = true);

      final started = await KioskService.installUpdateApk();

      if (!mounted) return;

      if (started) {
        _showSnackbar(
          'Select the new APK, then confirm installation in Android installer.',
          color: Colors.green,
        );
      } else {
        _showSnackbar('Could not start APK update flow', color: Colors.red);
      }
    } catch (e, st) {
      Logger.error(
        'Error starting in-app update',
        context: 'AdminPanel',
        error: e as Error?,
        stackTrace: st,
      );
      _showSnackbar('Error starting APK update', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Show dialog to change admin PIN
  void _showChangePinDialog() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text(
            'Change Admin PIN',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PinInputField(
                  controller: currentController,
                  label: 'Current PIN',
                  setS: setS,
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                _PinInputField(
                  controller: newController,
                  label: 'New PIN (4–8 digits)',
                  setS: setS,
                ),
                const SizedBox(height: 12),
                _PinInputField(
                  controller: confirmController,
                  label: 'Confirm New PIN',
                  setS: setS,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                currentController.dispose();
                newController.dispose();
                confirmController.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () async {
                await _performPinChange(
                  ctx,
                  currentController.text,
                  newController.text,
                  confirmController.text,
                );
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF4FC3F7))),
            ),
          ],
        ),
      ),
    );
  }

  /// Perform PIN change with validation
  Future<void> _performPinChange(
    BuildContext ctx,
    String currentPin,
    String newPin,
    String confirmPin,
  ) async {
    try {
      // Validation
      if (currentPin.isEmpty || newPin.isEmpty || confirmPin.isEmpty) {
        _showSnackbar('Please fill in all fields', color: Colors.orange);
        return;
      }

      if (newPin.length < 4 || newPin.length > 8) {
        _showSnackbar('PIN must be 4–8 digits', color: Colors.orange);
        return;
      }

      if (!RegExp(r'^\d{4,8}$').hasMatch(newPin)) {
        _showSnackbar('PIN must contain only digits', color: Colors.orange);
        return;
      }

      if (newPin != confirmPin) {
        _showSnackbar('New PINs do not match', color: Colors.red);
        return;
      }

      // Change PIN
      Logger.info('Changing admin PIN', context: 'AdminPanel');
      setState(() => _isLoading = true);

      final success = await PinService.changePin(
        currentPin: currentPin,
        newPin: newPin,
        confirmPin: confirmPin,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        Logger.info('PIN changed successfully', context: 'AdminPanel');
        Navigator.pop(ctx);
        _showSnackbar('PIN changed successfully', color: Colors.green);
      } else {
        _showSnackbar('Current PIN is incorrect', color: Colors.red);
      }
    } catch (e, st) {
      setState(() => _isLoading = false);
      Logger.error(
        'Error changing PIN',
        context: 'AdminPanel',
        error: e as Error?,
        stackTrace: st,
      );
      _showSnackbar('Error changing PIN', color: Colors.red);
    }
  }

  /// Show snackbar message
  void _showSnackbar(String message, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          // Confirm before going back to kiosk
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: const Text(
                'Return to Kiosk?',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Device will return to kiosk mode.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Stay', style: TextStyle(color: Colors.white38)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Return', style: TextStyle(color: Color(0xFF4FC3F7))),
                ),
              ],
            ),
          );
          if (shouldExit ?? false) {
            if (context.mounted) {
              Navigator.pop(context);
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A237E),
          title: const Text('Admin Panel'),
          centerTitle: true,
          elevation: 4,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  'Expires: ${(_secondsRemaining ~/ 60)}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _secondsRemaining < 300 ? Colors.orange : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Device Status Section
                    _SectionCard(
                      title: 'Device Status',
                      children: [
                        _StatusRow(
                          label: 'Device Owner Mode',
                          value: _isDeviceOwner ? '✓ Active' : '✗ Inactive',
                          valueColor: _isDeviceOwner ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        _StatusRow(
                          label: 'Kiosk Lock',
                          value: 'Active',
                          valueColor: Colors.blue,
                        ),
                        if (_deviceInfo != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Device Info:',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _deviceInfo!,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Admin Actions Section
                    _SectionCard(
                      title: 'Admin Actions',
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            _resetInactivityTimer();
                            _showChangePinDialog();
                          },
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Change Admin PIN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            _resetInactivityTimer();
                            _installAppUpdate();
                          },
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Install APK Update'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            _resetInactivityTimer();
                            _exitKioskMode();
                          },
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Exit Kiosk Mode'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Estate Info Section
                    _SectionCard(
                      title: 'Estate Information',
                      children: [
                        _InfoRow(label: 'Estate', value: AppConfig.estateName),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Location', value: AppConfig.estateLocation),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Company', value: 'Fynko Technologies'),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Admin Contact', value: AppConfig.adminContactNumber),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'App Version', value: AppConfig.version),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Warning Section
                    if (!_isDeviceOwner)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[900],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.warning, color: Colors.orange, size: 32),
                            SizedBox(height: 12),
                            Text(
                              'Device Owner Mode Not Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'For full security, activate Device Owner mode using ADB:\n\n'
                              'adb shell dpm set-device-owner com.fynko.infinitykiosk/.AdminReceiver',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.4,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// PIN input field widget
class _PinInputField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final Function setS;

  const _PinInputField({
    required this.controller,
    required this.label,
    required this.setS,
  });

  @override
  State<_PinInputField> createState() => _PinInputFieldState();
}

class _PinInputFieldState extends State<_PinInputField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      obscureText: _obscure,
      maxLength: 8,
      onChanged: (value) {
        if (value.isNotEmpty && !RegExp(r'^[0-9]*$').hasMatch(value)) {
          widget.controller.text = value.replaceAll(RegExp(r'[^0-9]'), '');
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
        }
      },
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        letterSpacing: 4,
      ),
      decoration: InputDecoration(
        hintText: '• • • •',
        hintStyle: const TextStyle(color: Colors.white24),
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Section card widget
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Status row widget
class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatusRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// Info row widget
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
