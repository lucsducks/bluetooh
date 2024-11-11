import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raspberry Bluetooth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: BluetoothApp(),
    );
  }
}

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  FlutterBluetoothSerial bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? connection;
  List<BluetoothDevice> devices = [];
  bool isConnected = false;
  String? savedDeviceAddress;
  TextEditingController messageController = TextEditingController();
  List<String> messages = [];

  @override
  void initState() {
    super.initState();
    _loadSavedDevice();
    _setupBluetooth();
  }

  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      savedDeviceAddress = prefs.getString('raspberryAddress');
    });
    if (savedDeviceAddress != null) {
      _connectToSavedDevice();
    }
  }

  Future<void> _saveDevice(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('raspberryAddress', address);
  }

  void _setupBluetooth() async {
    bool? isEnabled = await bluetooth.isEnabled;
    if (isEnabled ?? false) {
      _loadPairedDevices();
    } else {
      await bluetooth.requestEnable();
    }
  }

  void _loadPairedDevices() async {
    try {
      devices = await bluetooth.getBondedDevices();
      setState(() {});
    } catch (e) {
      print("Error al cargar dispositivos: $e");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        isConnected = true;
      });
      _saveDevice(device.address);
      _listenForMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conectado a ${device.name}')),
      );
    } catch (e) {
      print("Error de conexión: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar: $e')),
      );
    }
  }

  Future<void> _connectToSavedDevice() async {
    if (savedDeviceAddress == null) return;

    try {
      connection = await BluetoothConnection.toAddress(savedDeviceAddress!);
      setState(() {
        isConnected = true;
      });
      _listenForMessages();
    } catch (e) {
      print("Error al reconectar: $e");
    }
  }

  void _listenForMessages() {
    var subscription = connection?.input?.listen((Uint8List data) {
      try {
        // Intenta decodificar como UTF-8
        String message = utf8.decode(data);
        setState(() {
          print(message);

          messages.add("Raspberry: $message");
          print(messages);
        });
      } catch (e) {
        // Si falla la decodificación UTF-8, muestra los datos en hexadecimal
        String hexData = data
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        setState(() {
          messages.add("Raspberry (hex): $hexData");
          print(hexData);
          print(messages);
        });
      }
    });

    subscription?.onDone(() {
      setState(() {
        isConnected = false;
      });
    });

    subscription?.onError((error) {
      print("Error al recibir datos: $error");
      setState(() {
        isConnected = false;
      });
    });
  }

  Future<void> _sendMessage(String message) async {
    if (connection?.isConnected ?? false) {
      connection!.output.add(Uint8List.fromList(utf8.encode(message + "\n")));
      await connection!.output.allSent;
      setState(() {
        messages.add("Tú: $message");
        messageController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Raspberry Bluetooth'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadPairedDevices,
          ),
        ],
      ),
      body: Column(
        children: [
          // Lista de dispositivos
          if (!isConnected)
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(devices[index].name ?? "Desconocido"),
                    subtitle: Text(devices[index].address),
                    trailing: ElevatedButton(
                      onPressed: () => _connectToDevice(devices[index]),
                      child: Text('Conectar'),
                    ),
                  );
                },
              ),
            ),

          // Chat
          if (isConnected)
            Expanded(
              flex: 3,
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: messages[index].startsWith("Tú:")
                            ? Colors.blue[100]
                            : Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(messages[index]),
                    ),
                  );
                },
              ),
            ),

          // Campo de mensaje
          if (isConnected)
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (messageController.text.isNotEmpty) {
                        _sendMessage(messageController.text);
                      }
                    },
                    child: Icon(Icons.send),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }
}
