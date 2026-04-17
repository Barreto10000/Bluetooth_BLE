import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MiAppBluetooth());
}

class MiAppBluetooth extends StatelessWidget {
  const MiAppBluetooth({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control BLE',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PantallaEscaneo(),
    );
  }
}

// ==========================================
// PANTALLA 1: ESCANEAR DISPOSITIVOS
// ==========================================
class PantallaEscaneo extends StatefulWidget {
  const PantallaEscaneo({super.key});

  @override
  State<PantallaEscaneo> createState() => _PantallaEscaneoState();
}

class _PantallaEscaneoState extends State<PantallaEscaneo> {
  List<ScanResult> resultados = [];
  bool escaneando = false;

  void escanear() async {
    setState(() {
      escaneando = true;
      resultados.clear();
    });

    // Escuchar resultados del escaneo
    var subscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        resultados = results;
      });
    });

    // Iniciar escaneo
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await Future.delayed(const Duration(seconds: 5));
    
    setState(() {
      escaneando = false;
    });
    FlutterBluePlus.stopScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth BLE')),
      body: ListView.builder(
        itemCount: resultados.length,
        itemBuilder: (context, index) {
          final dispositivo = resultados[index].device;
          final nombre = dispositivo.localName.isEmpty ? "Dispositivo Desconocido" : dispositivo.localName;
          
          return ListTile(
            title: Text(nombre),
            subtitle: Text(dispositivo.remoteId.toString()),
            trailing: ElevatedButton(
              child: const Text('Conectar'),
              onPressed: () {
                FlutterBluePlus.stopScan(); // Parar escaneo antes de conectar
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => PantallaDispositivo(dispositivo: dispositivo),
                ));
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: escaneando ? null : escanear,
        child: Icon(escaneando ? Icons.stop : Icons.search),
      ),
    );
  }
}

// ==========================================
// PANTALLA 2: CONTROL DEL DISPOSITIVO
// ==========================================
class PantallaDispositivo extends StatefulWidget {
  final BluetoothDevice dispositivo;
  const PantallaDispositivo({super.key, required this.dispositivo});

  @override
  State<PantallaDispositivo> createState() => _PantallaDispositivoState();
}

class _PantallaDispositivoState extends State<PantallaDispositivo> {
  BluetoothCharacteristic? caracteristicaEscribir;
  String mensajeRecibido = "Esperando datos...";

  // Los UUIDs deben coincidir exactamente con los de tu ESP32
  final String SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String CHARACTERISTIC_UUID_RX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // Flutter escribe aquí
  final String CHARACTERISTIC_UUID_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // Flutter lee de aquí

  @override
  void initState() {
    super.initState();
    conectarYDescubrir();
  }

  void conectarYDescubrir() async {
    try {
      await widget.dispositivo.connect();
      List<BluetoothService> servicios = await widget.dispositivo.discoverServices();

      for (var servicio in servicios) {
        if (servicio.uuid.toString().toLowerCase() == SERVICE_UUID) {
          for (var caracteristica in servicio.characteristics) {
            
            // Guardar la característica de escritura (RX del ESP32)
            if (caracteristica.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID_RX) {
              caracteristicaEscribir = caracteristica;
            }

            // Suscribirse a la característica de lectura (TX del ESP32)
            if (caracteristica.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID_TX) {
              await caracteristica.setNotifyValue(true);
              caracteristica.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  setState(() {
                    mensajeRecibido = utf8.decode(value); // Convertir bytes a texto
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      print("Error de conexión: $e");
    }
  }

  void enviarComandoON() async {
    if (caracteristicaEscribir != null) {
      List<int> bytes = utf8.encode("!led_on\$"); // Convierte el texto "ON" a bytes
      await caracteristicaEscribir!.write(bytes);
    }
  }
  void enviarComandoOFF() async {
    if (caracteristicaEscribir != null) {
      List<int> bytes = utf8.encode("!led_off\$"); // Convierte el texto "ON" a bytes
      await caracteristicaEscribir!.write(bytes);
    }
  }

  @override
  void dispose() {
    widget.dispositivo.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dispositivo.localName)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Datos recibidos del hardware:", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text(mensajeRecibido, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: enviarComandoON,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              child: const Text("Enviar Comando 'ON'", style: TextStyle(fontSize: 18)),
            ),
            ElevatedButton(
              onPressed: enviarComandoOFF,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              child: const Text("Enviar Comando 'OFF'", style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}
