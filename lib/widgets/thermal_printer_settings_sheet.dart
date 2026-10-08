import 'package:flutter/material.dart';

import '../services/thermal_printer_service.dart';
import '../theme/app_colors.dart';

Future<void> showThermalPrinterSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ThermalPrinterSettingsSheet(),
    );

class ThermalPrinterSettingsSheet extends StatefulWidget {
  const ThermalPrinterSettingsSheet({super.key});

  @override
  State<ThermalPrinterSettingsSheet> createState() =>
      _ThermalPrinterSettingsSheetState();
}

class _ThermalPrinterSettingsSheetState
    extends State<ThermalPrinterSettingsSheet> {
  final _printerService = ThermalPrinterService.instance;
  List<ThermalPrinterDevice> _printers = [];
  String? _selectedAddress;
  bool _isScanning = false;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _printerService.initialize();
    _selectedAddress = _printerService.status.value.address;
  }

  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);
    try {
      final printers = await _printerService.scanPairedPrinters();
      if (!mounted) return;
      setState(() {
        _printers = printers;
        if (!_printers.any((item) => item.address == _selectedAddress)) {
          _selectedAddress = _printers.isEmpty ? null : _printers.first.address;
        }
      });
      _showMessage(
        printers.isEmpty
            ? 'No paired Bluetooth devices found. Pair the printer in Android Bluetooth Settings first.'
            : 'Found ${printers.length} paired device${printers.length == 1 ? '' : 's'}.',
      );
    } catch (error) {
      _showMessage('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connect() async {
    final address = _selectedAddress;
    final printer = _printers.where((item) => item.address == address);
    if (printer.isEmpty) {
      _showMessage('Scan devices and select a printer first.', isError: true);
      return;
    }
    setState(() => _isWorking = true);
    try {
      await _printerService.connect(printer.first);
      _showMessage('Successfully connected to ${printer.first.name}.');
    } catch (error) {
      _showMessage('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _reconnect() async {
    setState(() => _isWorking = true);
    try {
      await _printerService.reconnect();
      _showMessage('Successfully reconnected to the printer.');
    } catch (error) {
      _showMessage('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _isWorking = true);
    try {
      await _printerService.disconnect();
      _showMessage('Printer disconnected.');
    } catch (error) {
      _showMessage('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isWorking = true);
    try {
      await _printerService.printTestReceipt();
      _showMessage('Test receipt sent to printer.');
    } catch (error) {
      _showMessage('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bluetooth_rounded,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Bluetooth Printer',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<ThermalPrinterStatus>(
                valueListenable: _printerService.status,
                builder: (context, status, _) {
                  final color = status.isConnected
                      ? Colors.green.shade700
                      : status.isConnecting
                      ? Colors.orange.shade800
                      : Colors.red.shade700;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 11, color: color),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${status.label}${status.name == null ? '' : ' - ${status.name}'}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Paper width',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ValueListenableBuilder<ThermalPrinterStatus>(
                      valueListenable: _printerService.status,
                      builder: (context, status, _) => DropdownButton<int>(
                        value: status.paperWidth,
                        items: const [
                          DropdownMenuItem(value: 58, child: Text('58 mm')),
                          DropdownMenuItem(value: 80, child: Text('80 mm')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _printerService.setPaperWidth(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isScanning || _isWorking ? null : _scanDevices,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan Devices'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 5, 20, 5),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'On Android, printers must be paired first in Bluetooth Settings.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ),
              Flexible(
                child: _printers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Scan to show paired Bluetooth devices.'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _printers.length,
                        itemBuilder: (context, index) {
                          final printer = _printers[index];
                          final isSelected =
                              printer.address == _selectedAddress;
                          return ListTile(
                            selected: isSelected,
                            onTap: _isWorking
                                ? null
                                : () => setState(
                                    () => _selectedAddress = printer.address,
                                  ),
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              printer.name.isEmpty
                                  ? 'Thermal printer'
                                  : printer.name,
                            ),
                            subtitle: Text(printer.address),
                            trailing: const Icon(Icons.print_rounded),
                          );
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _isWorking || _isScanning ? null : _connect,
                      icon: const Icon(Icons.bluetooth_connected_rounded),
                      label: const Text('Connect'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isWorking || _isScanning ? null : _reconnect,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reconnect'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isWorking || _isScanning ? null : _testPrint,
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('Test Print'),
                    ),
                    TextButton.icon(
                      onPressed: _isWorking || _isScanning ? null : _disconnect,
                      icon: const Icon(Icons.bluetooth_disabled_rounded),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
              if (_isWorking)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
