import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MiAppBluetooth());
}

class MiAppBluetooth extends StatelessWidget {
  const MiAppBluetooth({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control BLE y Gráfica',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PantallaEscaneo(),
    );
  }
}

// ==========================================
// PANTALLA 1: ESCANEAR DISPOSITIVOS (Sin cambios)
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

    var subscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        resultados = results;
      });
    });

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
          final nombre = dispositivo.localName.isEmpty
              ? "Dispositivo Desconocido"
              : dispositivo.localName;

          return ListTile(
            title: Text(nombre),
            subtitle: Text(dispositivo.remoteId.toString()),
            trailing: ElevatedButton(
              child: const Text('Conectar'),
              onPressed: () {
                FlutterBluePlus.stopScan();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        PantallaDispositivo(dispositivo: dispositivo),
                  ),
                );
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
// PANTALLA 2: CONTROL DEL DISPOSITIVO Y GRÁFICA (MODIFICADA)
// ==========================================
class PantallaDispositivo extends StatefulWidget {
  final BluetoothDevice dispositivo;
  const PantallaDispositivo({super.key, required this.dispositivo});

  @override
  State<PantallaDispositivo> createState() => _PantallaDispositivoState();
}

class _PantallaDispositivoState extends State<PantallaDispositivo> {
  BluetoothCharacteristic? caracteristicaEscribir;

  // Variables separadas para mostrar en pantalla
  String voltajeRMS = "0.0";
  String rawData = "";

  // --- VARIABLES PARA LA GRÁFICA ---
  List<FlSpot> _spots = [];
  // ---------------------------------

  final String SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String CHARACTERISTIC_UUID_RX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  final String CHARACTERISTIC_UUID_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  @override
  void initState() {
    super.initState();
    conectarYDescubrir();
  }

  void conectarYDescubrir() async {
    try {
      await widget.dispositivo.connect();

      // ¡ESTO ES VITAL PARA RECIBIR LA TRAMA COMPLETA!
      await widget.dispositivo.requestMtu(512);

      List<BluetoothService> servicios = await widget.dispositivo
          .discoverServices();

      for (var servicio in servicios) {
        if (servicio.uuid.toString().toLowerCase() == SERVICE_UUID) {
          for (var caracteristica in servicio.characteristics) {
            // RX del ESP32 (Escribir comandos)
            if (caracteristica.uuid.toString().toLowerCase() ==
                CHARACTERISTIC_UUID_RX) {
              caracteristicaEscribir = caracteristica;
            }

            // TX del ESP32 (Recibir datos)
            if (caracteristica.uuid.toString().toLowerCase() ==
                CHARACTERISTIC_UUID_TX) {
              await caracteristica.setNotifyValue(true);
              caracteristica.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  // Decodificamos el texto recibido
                  String textoRecibido = utf8.decode(value).trim();

                  // Esperamos el formato: V:127.5|O:100,200,-50...
                  if (textoRecibido.contains("|")) {
                    List<String> partes = textoRecibido.split("|");

                    if (partes.length == 2) {
                      String parteVoltaje = partes[0].replaceAll(
                        "V:",
                        "",
                      ); // Sacamos los Voltios
                      String parteOnda = partes[1].replaceAll(
                        "O:",
                        "",
                      ); // Sacamos la cadena de números

                      List<String> puntosString = parteOnda.split(",");
                      List<FlSpot> nuevosPuntos = [];

                      // Llenamos la nueva lista de puntos (el eje X va del 0 al 49)
                      for (int i = 0; i < puntosString.length; i++) {
                        double? valY = double.tryParse(puntosString[i]);
                        if (valY != null) {
                          nuevosPuntos.add(FlSpot(i.toDouble(), valY));
                        }
                      }

                      // Actualizamos la UI
                      setState(() {
                        voltajeRMS = parteVoltaje;
                        _spots =
                            nuevosPuntos; // Reemplazamos toda la gráfica de golpe
                      });
                    }
                  }
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
      List<int> bytes = utf8.encode("!led_on\$");
      await caracteristicaEscribir!.write(bytes);
    }
  }

  void enviarComandoOFF() async {
    if (caracteristicaEscribir != null) {
      List<int> bytes = utf8.encode("!led_off\$");
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
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // --- TÍTULO DE VOLTAJE ---
            const Text(
              "Voltaje de Red",
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              "$voltajeRMS V",
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),

            const SizedBox(height: 30),

            // --- INICIO DE LA GRÁFICA ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: AspectRatio(
                aspectRatio: 1.5,
                child: LineChart(
                  LineChartData(
                    // 1. FIJAMOS LA ESCALA PARA QUE NO SE DEFORME
                    minY: -2000, // Límite negativo absoluto
                    maxY: 2000, // Límite positivo absoluto
                    minX: 0,
                    maxX: 29,

                    // 2. APAGAMOS LOS TEXTOS Y CUADRÍCULAS FEAS
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(show: false),

                    // 3. DIBUJAMOS LA LÍNEA DEL CERO (TU CERO VIRTUAL)
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: 0,
                          color: Colors.redAccent.withOpacity(0.5),
                          strokeWidth: 2,
                          dashArray: [5, 5], // Hace que la línea sea punteada
                        ),
                      ],
                    ),

                    lineBarsData: [
                      LineChartBarData(
                        show: true,
                        spots: _spots.isEmpty ? const [FlSpot(0, 0)] : _spots,
                        color: Colors.blueAccent,
                        barWidth: 3,
                        isCurved: true,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: false),

                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.blueAccent.withOpacity(0.2),
                        ),
                      ),
                    ],
                  ),
                duration: const Duration(milliseconds: 80),
                ),
              ),
            ),

            // --- FIN DE LA GRÁFICA ---
            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: enviarComandoON,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 20,
                    ),
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    "ON",
                    style: TextStyle(fontSize: 20, color: Colors.white),
                  ),
                ),
                ElevatedButton(
                  onPressed: enviarComandoOFF,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 20,
                    ),
                    backgroundColor: Colors.red,
                  ),
                  child: const Text(
                    "OFF",
                    style: TextStyle(fontSize: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
