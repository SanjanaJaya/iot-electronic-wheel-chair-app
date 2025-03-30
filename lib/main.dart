import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

void main() {
  runApp(const WheelchairApp());
}

class WheelchairApp extends StatelessWidget {
  const WheelchairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wheelchair Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const BluetoothScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  bool _isConnecting = false;
  bool _isConnected = false;
  String _statusMessage = "Searching for devices...";
  final String targetDeviceName = "ESP32_Wheelchair";

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _startScan();
  }

  Future<void> _checkPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
  }

  void _startScan() {
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.platformName == targetDeviceName) {
          _connectToDevice(result.device);
          break;
        }
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _statusMessage = "Connecting to ${device.platformName}...";
    });

    try {
      await device.connect(autoConnect: false);
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            _characteristic = characteristic;
            break;
          }
        }
      }

      setState(() {
        _connectedDevice = device;
        _isConnected = true;
        _isConnecting = false;
        _statusMessage = "Connected to ${device.platformName}";
      });

      if (_characteristic != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ControlScreen(characteristic: _characteristic!),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = "Connection failed: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wheelchair Controller'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isConnecting)
              const CircularProgressIndicator()
            else
              Icon(
                _isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                size: 50,
                color: _isConnected ? Colors.blue : Colors.grey,
              ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (!_isConnected && !_isConnecting)
              ElevatedButton(
                onPressed: _startScan,
                child: const Text('Retry Connection'),
              ),
          ],
        ),
      ),
    );
  }
}

class ControlScreen extends StatefulWidget {
  final BluetoothCharacteristic characteristic;

  const ControlScreen({super.key, required this.characteristic});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool _isEmergencyStop = false;
  double _speed = 0.5;
  bool _isMoving = false;
  String _lastCommand = '';

  void _sendCommand(String command) async {
    if (_lastCommand == command) return;

    try {
      await widget.characteristic.write(command.codeUnits);
      _lastCommand = command;

      if (command == 'S') {
        Vibration.vibrate(duration: 100);
        setState(() {
          _isMoving = false;
        });
      } else {
        setState(() {
          _isMoving = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command failed: $e')),
      );
    }
  }

  void _emergencyStop() {
    _sendCommand('S');
    setState(() {
      _isEmergencyStop = true;
    });
    Vibration.vibrate(duration: 500);
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isEmergencyStop = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wheelchair Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => _buildSettingsDialog(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Forward Button
                GestureDetector(
                  onTapDown: (_) => _sendCommand('F'),
                  onTapUp: (_) => _sendCommand('S'),
                  onTapCancel: () => _sendCommand('S'),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _isMoving && _lastCommand == 'F'
                          ? Colors.blue
                          : Colors.blue.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.arrow_upward, size: 60, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Left Button
                    GestureDetector(
                      onTapDown: (_) => _sendCommand('L'),
                      onTapUp: (_) => _sendCommand('S'),
                      onTapCancel: () => _sendCommand('S'),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: _isMoving && _lastCommand == 'L'
                              ? Colors.blue
                              : Colors.blue.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.arrow_back, size: 60, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 40),
                    // Stop Button
                    GestureDetector(
                      onTap: _emergencyStop,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: _isEmergencyStop ? Colors.red : Colors.grey,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(Icons.stop, size: 60, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 40),
                    // Right Button
                    GestureDetector(
                      onTapDown: (_) => _sendCommand('R'),
                      onTapUp: (_) => _sendCommand('S'),
                      onTapCancel: () => _sendCommand('S'),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: _isMoving && _lastCommand == 'R'
                              ? Colors.blue
                              : Colors.blue.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.arrow_forward, size: 60, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Backward Button
                GestureDetector(
                  onTapDown: (_) => _sendCommand('B'),
                  onTapUp: (_) => _sendCommand('S'),
                  onTapCancel: () => _sendCommand('S'),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _isMoving && _lastCommand == 'B'
                          ? Colors.blue
                          : Colors.blue.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.arrow_downward, size: 60, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: _emergencyStop,
              backgroundColor: Colors.red,
              child: const Icon(Icons.warning, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Speed: ${(_speed * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsDialog() {
    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Speed Control'),
          Slider(
            value: _speed,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            label: '${(_speed * 100).round()}%',
            onChanged: (value) {
              setState(() {
                _speed = value;
              });
              // Send speed command to ESP32
              _sendCommand('V${(value * 255).round()}');
            },
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Enable Vibration Feedback'),
            value: true,
            onChanged: (value) {
              // Vibration settings would go here
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}