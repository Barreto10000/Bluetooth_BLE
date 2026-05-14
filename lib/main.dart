import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MonitorEnergiaApp());
}

class MonitorEnergiaApp extends StatelessWidget {
  const MonitorEnergiaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor Premium ESP32',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto', // Fuente limpia y moderna
      ),
      home: const PantallaEscaneo(), 
    );
  }
}

// =====================================================================
// PANTALLA 1: ESCANEO Y CONEXIÓN BLUETOOTH
// =====================================================================
class PantallaEscaneo extends StatefulWidget {
  const PantallaEscaneo({Key? key}) : super(key: key);

  @override
  State<PantallaEscaneo> createState() => _PantallaEscaneoState();
}

class _PantallaEscaneoState extends State<PantallaEscaneo> {
  List<ScanResult> resultados = [];
  bool escaneando = false;

  @override
  void initState() {
    super.initState();
    _iniciarEscaneo();
  }

  void _iniciarEscaneo() async {
    setState(() => escaneando = true);
    resultados.clear();

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          resultados = results;
        });
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => escaneando = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Fondo premium sutil
      appBar: AppBar(
        title: const Text('Dispositivos BLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Tono oscuro elegante
        elevation: 0,
        actions: [
          if (escaneando)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
              onPressed: _iniciarEscaneo,
            )
        ],
      ),
      body: resultados.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_searching, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text("Buscando Enchufe Inteligente...", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: resultados.length,
              itemBuilder: (context, index) {
                final r = resultados[index];
                String nombreDispositivo = r.device.name.isNotEmpty ? r.device.name : "Dispositivo Desconocido";

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bluetooth, color: Colors.blueAccent),
                    ),
                    title: Text(nombreDispositivo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(r.device.remoteId.toString(), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('CONECTAR', style: TextStyle(color: Colors.cyanAccent)),
                      onPressed: () {
                        FlutterBluePlus.stopScan();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => DispositivoScreen(dispositivo: r.device),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =====================================================================
// PANTALLA 2: MONITOR DE ENERGÍA PREMIUM
// =====================================================================
class DispositivoScreen extends StatefulWidget {
  final BluetoothDevice dispositivo;
  const DispositivoScreen({Key? key, required this.dispositivo}) : super(key: key);

  @override
  State<DispositivoScreen> createState() => _DispositivoScreenState();
}

class _DispositivoScreenState extends State<DispositivoScreen> {
  BluetoothCharacteristic? _caracteristicaEscritura;
  BluetoothCharacteristic? _caracteristicaLectura;
  StreamSubscription<List<int>>? _suscripcionDatos;
  
  // Variables para la interfaz
  String voltaje = "0.0";
  String corriente = "0.0";
  String potencia = "0.0";
  String consumo = "0.0000"; // <--- Nueva variable de consumo
  List<FlSpot> _spots = [];

  // UUIDs
  final String serviceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String rxUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; 
  final String txUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  bool _conectando = true;

  // Variables para la Animación Hollywood
  Timer? _timerAnimacion;
  double _fase = 0.0;

  @override
  void initState() {
    super.initState();
    conectarYDescubrir();
    _iniciarOndaEstetica();
  }

  // --- EL EFECTO HOLLYWOOD ---
  void _iniciarOndaEstetica() {
    _timerAnimacion = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) return;
      
      setState(() {
        _fase += 0.25; // Velocidad de la onda
        _spots.clear();
        
        double amplitud = double.tryParse(voltaje) ?? 0.0;
        
        // Si el voltaje cae a 0 (desconectado), la línea se aplana sola
        if (amplitud < 10) amplitud = 0; 
        
        // Generamos la onda perfecta
        for (int i = 0; i < 60; i++) {
          double y = amplitud * math.sin((i * 0.15) + _fase);
          _spots.add(FlSpot(i.toDouble(), y));
        }
      });
    });
  }

  void conectarYDescubrir() async {
    try {
      await widget.dispositivo.connect(timeout: const Duration(seconds: 10));
      if (Platform.isAndroid) {
        await widget.dispositivo.requestMtu(512);
        await widget.dispositivo.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
      }

      List<BluetoothService> servicios = await widget.dispositivo.discoverServices();
      for (var servicio in servicios) {
        if (servicio.uuid.toString() == serviceUUID) {
          for (var caracteristica in servicio.characteristics) {
            
            if (caracteristica.uuid.toString() == txUUID) {
              _caracteristicaLectura = caracteristica;
              await _caracteristicaLectura!.setNotifyValue(true);
              
              _suscripcionDatos = _caracteristicaLectura!.lastValueStream.listen((value) {
                if (value.isNotEmpty) procesarDatos(value);
              });
            }

            if (caracteristica.uuid.toString() == rxUUID) {
              _caracteristicaEscritura = caracteristica;
            }
          }
        }
      }

      if (mounted) setState(() => _conectando = false);

    } catch (e) {
      print("Error en la conexión: $e");
      if (mounted) Navigator.pop(context);
    }
  }

  // --- PARSEO SÚPER RÁPIDO Y LIMPIO ---
  void procesarDatos(List<int> value) {
    try {
      String rawData = utf8.decode(value);
      List<String> partes = rawData.split('|');

      if (partes.length >= 3) {
        if (mounted) {
          setState(() {
            voltaje = partes[0].substring(2);
            corriente = partes[1].substring(2);
            potencia = partes[2].substring(2);
            // Extrae la energía si está disponible en la trama
            if (partes.length >= 4) {
              consumo = partes[3].substring(2); 
            }
          });
        }
      }
    } catch (e) {
      print("Error procesando trama: $e");
    }
  }

  void enviarComando(String comando) async {
    if (_caracteristicaEscritura != null) {
      String tramaCompleta = "!$comando\$";
      await _caracteristicaEscritura!.write(utf8.encode(tramaCompleta));
    }
  }

  @override
  void dispose() {
    _timerAnimacion?.cancel();
    _suscripcionDatos?.cancel();
    widget.dispositivo.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Fondo Dark Mode elegante
      appBar: AppBar(
        title: Text(widget.dispositivo.name.isEmpty ? "Panel de Control" : widget.dispositivo.name, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: _conectando 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.cyanAccent),
                const SizedBox(height: 20),
                Text("Sincronizando Sensores...", style: TextStyle(color: Colors.grey[400], fontSize: 16)),
              ],
            ),
          )
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
              child: Column(
                children: [
                  // --- TARJETAS DE LECTURA 2x2 ---
                  Row(
                    children: [
                      _buildMedidorCard("VOLTAJE", "$voltaje V", Icons.electric_bolt, Colors.cyanAccent),
                      _buildMedidorCard("CORRIENTE", "$corriente A", Icons.waves, Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 10), // Separación entre filas
                  Row(
                    children: [
                      _buildMedidorCard("POTENCIA", "$potencia W", Icons.speed, Colors.greenAccent),
                      _buildMedidorCard("CONSUMO", "$consumo kWh", Icons.bolt, Colors.purpleAccent), // <--- Tarjeta nueva
                    ],
                  ),
                  
                  const SizedBox(height: 35),

                  // --- OSCILOSCOPIO NEÓN ---
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "  SEÑAL EN TIEMPO REAL",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 180,
                    padding: const EdgeInsets.only(right: 20, left: 10, top: 30, bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B), // Fondo oscuro para resaltar la línea
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: LineChart(
                      LineChartData(
                        minY: -200, // Ajustado para 127V reales
                        maxY: 200,  
                        minX: 0,
                        maxX: 59, // 60 puntos perfectos
                        
                        titlesData: const FlTitlesData(show: false), 
                        borderData: FlBorderData(show: false), 
                        gridData: const FlGridData(show: false), 

                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 0, 
                              color: Colors.grey.withOpacity(0.3), 
                              strokeWidth: 1, 
                              dashArray: const [5, 5],
                            ),
                          ],
                        ),

                        lineBarsData: [
                          LineChartBarData(
                            show: true,
                            spots: _spots.isEmpty ? List.generate(60, (index) => FlSpot(index.toDouble(), 0)) : _spots, 
                            isCurved: true,
                            curveSmoothness: 0.4,
                            barWidth: 4, 
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false), 
                            
                            // Gradiente Neón en la línea
                            gradient: const LinearGradient(
                              colors: [Colors.cyanAccent, Colors.blueAccent, Colors.deepPurpleAccent],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            
                            // Relleno suave bajo la curva
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.cyanAccent.withOpacity(0.3),
                                  Colors.deepPurpleAccent.withOpacity(0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // --- BOTONES DE CONTROL DE POTENCIA ---
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildBotonControl(
                          "ENCENDER", 
                          Icons.power, 
                          Colors.greenAccent, 
                          () => enviarComando("led_on")
                        ),
                        Container(width: 1, height: 40, color: Colors.grey[700]), // Divisor
                        _buildBotonControl(
                          "APAGAR", 
                          Icons.power_off, 
                          Colors.redAccent, 
                          () => enviarComando("led_off")
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

  // --- WIDGETS REUTILIZABLES PREMIUM ---
  Widget _buildMedidorCard(String titulo, String valor, IconData icono, Color colorAcento) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colorAcento.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(color: colorAcento.withOpacity(0.1), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        child: Column(
          children: [
            Icon(icono, color: colorAcento, size: 24),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                valor,
                style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              style: TextStyle(fontSize: 10, color: Colors.grey[400], letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonControl(String texto, IconData icono, Color color, VoidCallback accion) {
    return Expanded( // <--- Esto obliga al botón a adaptarse al espacio exacto
      child: InkWell(
        onTap: accion,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // Centramos el contenido
            children: [
              Icon(icono, color: color, size: 24), // Ícono un pelín más pequeño
              const SizedBox(width: 5),
              Flexible( // Protege el texto por si la pantalla es en extremo pequeña
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    texto,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}