import 'dart:async';
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
  String _statusMessage = "Initializing...";
  List<ScanResult> _foundDevices = [];
  final String targetDeviceName = "ESP32_Wheelchair";
  final String targetDeviceMac = "DE:BF:ED:58:16:F0"; // Replace with your ESP32's MAC
  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    try {
      await _checkPermissions();
      _startScan();
    } catch (e) {
      setState(() {
        _statusMessage = "Error: ${e.toString()}";
      });
    }
  }

  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetooth] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted ||
        statuses[Permission.bluetoothScan] != PermissionStatus.granted) {
      throw Exception("Bluetooth permissions denied");
    }

    bool isOn = await FlutterBluePlus.isOn;
    if (!isOn) {
      throw Exception("Bluetooth is turned off");
    }
  }

  void _startScan() {
    setState(() {
      _statusMessage = "Scanning for devices...";
      _foundDevices.clear();
    });

    FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;

      setState(() {
        _foundDevices = results;
      });

      for (ScanResult result in results) {
        final device = result.device;
        print("Found device: ${device.platformName} (${device.remoteId})");

        // Try to connect if name matches OR MAC matches
        if (device.platformName == targetDeviceName ||
            device.remoteId.toString() == targetDeviceMac) {
          FlutterBluePlus.stopScan();
          _connectToDevice(device);
          break;
        }
      }
    }, onError: (e) {
      setState(() {
        _statusMessage = "Scan failed: ${e.toString()}";
      });
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: false,
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = "Connecting to ${device.platformName}...";
    });

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 5));
      print("Connected to device!");

      List<BluetoothService> services = await device.discoverServices();
      print("Discovered ${services.length} services");

      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == characteristicUuid) {
              _characteristic = characteristic;
              print("Found matching characteristic!");
              break;
            }
          }
        }
      }

      if (_characteristic == null) {
        throw Exception("No matching characteristic found");
      }

      setState(() {
        _connectedDevice = device;
        _isConnected = true;
        _isConnecting = false;
        _statusMessage = "Connected to ${device.platformName}";
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ControlScreen(characteristic: _characteristic!),
          ),
        );
      }
    } catch (e) {
      print("Connection error: $e");
      setState(() {
        _isConnecting = false;
        _statusMessage = "Connection failed: ${e.toString()}";
      });
      await device.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wheelchair Controller'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _foundDevices.length,
              itemBuilder: (context, index) {
                final device = _foundDevices[index].device;
                return ListTile(
                  title: Text(device.platformName.isEmpty ? "Unknown" : device.platformName),
                  subtitle: Text(device.remoteId.toString()),
                  onTap: () => _connectToDevice(device),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_isConnecting)
                  const CircularProgressIndicator()
                else
                  Icon(
                    _isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                    size: 50,
                    color: _isConnected ? Colors.blue : Colors.grey,
                  ),
                const SizedBox(height: 10),
                Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _startScan,
                  child: const Text('Scan Again'),
                ),
              ],
            ),
          ),
        ],
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
  bool _connectionAlive = true;
  late StreamSubscription<BluetoothConnectionState> _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _setupDisconnectListener();
  }

  void _setupDisconnectListener() {
    _connectionSubscription = widget.characteristic.device.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionAlive = state == BluetoothConnectionState.connected;
      });
      if (!_connectionAlive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Device disconnected!")),
        );
      }
    });
  }

  Future<void> _sendCommand(String command) async {
    if (!_connectionAlive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected to device")),
      );
      return;
    }

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
      print("Command error: $e");
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
      if (mounted) {
        setState(() {
          _isEmergencyStop = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wheelchair Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildControlButton(
                  onTapDown: () => _sendCommand('F'),
                  icon: Icons.arrow_upward,
                  isActive: _isMoving && _lastCommand == 'F',
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildControlButton(
                      onTapDown: () => _sendCommand('L'),
                      icon: Icons.arrow_back,
                      isActive: _isMoving && _lastCommand == 'L',
                    ),
                    const SizedBox(width: 40),
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
                    _buildControlButton(
                      onTapDown: () => _sendCommand('R'),
                      icon: Icons.arrow_forward,
                      isActive: _isMoving && _lastCommand == 'R',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildControlButton(
                  onTapDown: () => _sendCommand('B'),
                  icon: Icons.arrow_downward,
                  isActive: _isMoving && _lastCommand == 'B',
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
          if (!_connectionAlive)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bluetooth_disabled, size: 50, color: Colors.red),
                      const SizedBox(height: 20),
                      const Text(
                        'Disconnected!',
                        style: TextStyle(color: Colors.white, fontSize: 24),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BluetoothScreen(),
                          ),
                        ),
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required VoidCallback onTapDown,
    required IconData icon,
    required bool isActive,
  }) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => _sendCommand('S'),
      onTapCancel: () => _sendCommand('S'),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.blue.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 60, color: Colors.white),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                _sendCommand('V${(value * 255).round()}');
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
      ),
    );
  }
}