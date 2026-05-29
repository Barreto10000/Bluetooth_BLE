import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Instancia global para las notificaciones
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Configuración para Android
  const AndroidInitializationSettings initializationSettingsAndroid = 
      AndroidInitializationSettings('@mipmap/ic_launcher');
      
  // 2. Configuración para iOS (¡NUEVO!)
  const DarwinInitializationSettings initializationSettingsIOS = 
      DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
      );

  // 3. Juntar ambas configuraciones
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS, // Se agrega iOS aquí
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 4. Solicitar permiso explícito en iOS (¡NUEVO!)
  if (Platform.isIOS) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

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
        fontFamily: 'Roboto', 
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
      backgroundColor: const Color(0xFFF4F6F9), 
      appBar: AppBar(
        title: const Text('Dispositivos BLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), 
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
                      onPressed: () {
                        FlutterBluePlus.stopScan();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => DispositivoScreen(dispositivo: r.device),
                          ),
                        );
                      },
                      child: const Text('CONECTAR', style: TextStyle(color: Colors.cyanAccent)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =====================================================================
// PANTALLA 2: MONITOR DE ENERGÍA PREMIUM CON ALERTAS E HISTORIAL
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
  
  // Variables para la interfaz de energía
  String voltaje = "0.0";
  String corriente = "0.0";
  String potencia = "0.0";
  String consumo = "0.0000"; 
  List<FlSpot> _spots = [];
  
  // Variables para Alertas y Ajustes
  double _limitePotencia = 1500.0;
  double _limiteConsumo = 5.0;
  bool _autoApagar = false;
  DateTime? _ultimaNotificacion;
  List<Map<String, String>> _historialAlertas = [];

  // UUIDs
  final String serviceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String rxUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; 
  final String txUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  
  bool _conectando = true;
  Timer? _timerAnimacion;
  double _fase = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarAjustesYHistorial();
    conectarYDescubrir();
    _iniciarOndaEstetica();
  }

  // --- PERSISTENCIA DE DATOS ---
  Future<void> _cargarAjustesYHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _limitePotencia = prefs.getDouble('limitePotencia') ?? 1500.0;
      _limiteConsumo = prefs.getDouble('limiteConsumo') ?? 5.0;
      _autoApagar = prefs.getBool('autoApagar') ?? false;
      
      // Cargar historial
      List<String>? historialJson = prefs.getStringList('historialAlertas');
      if (historialJson != null) {
        _historialAlertas = historialJson.map((item) => Map<String, String>.from(jsonDecode(item))).toList();
      }
    });
  }

  Future<void> _guardarAlertaEnHistorial(String titulo, String cuerpo) async {
    final prefs = await SharedPreferences.getInstance();
    
    final nuevaAlerta = {
      'titulo': titulo,
      'cuerpo': cuerpo,
      'fecha': DateTime.now().toIso8601String(),
    };

    setState(() {
      _historialAlertas.insert(0, nuevaAlerta); // Agregar al inicio (más reciente primero)
      // Mantener solo las últimas 50 alertas para no saturar memoria
      if (_historialAlertas.length > 50) _historialAlertas.removeLast();
    });

    List<String> historialJson = _historialAlertas.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('historialAlertas', historialJson);
  }

  Future<void> _limpiarHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('historialAlertas');
    setState(() {
      _historialAlertas.clear();
    });
  }

  // --- ANIMACIÓN DE ONDA ---
  void _iniciarOndaEstetica() {
    _timerAnimacion = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) return;
      
      setState(() {
        _fase += 0.25; 
        _spots.clear();
        
        double amplitud = double.tryParse(voltaje) ?? 0.0;
        if (amplitud < 10) amplitud = 0; 
        
        for (int i = 0; i < 60; i++) {
          double y = amplitud * math.sin((i * 0.15) + _fase);
          _spots.add(FlSpot(i.toDouble(), y));
        }
      });
    });
  }

  // --- CONEXIÓN BLE ---
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

  // --- PROCESAMIENTO DE DATOS Y ALERTAS ---
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
            if (partes.length >= 4) {
              consumo = partes[3].substring(2); 
            }
          });
          
          _verificarLimites(double.tryParse(potencia) ?? 0.0, double.tryParse(consumo) ?? 0.0);
        }
      }
    } catch (e) {
      print("Error procesando trama: $e");
    }
  }

void _verificarLimites(double potActual, double consActual) {
    if (_ultimaNotificacion != null && DateTime.now().difference(_ultimaNotificacion!).inSeconds < 30) {
      return;
    }

    if (potActual > _limitePotencia) {
      String titulo = "¡Sobrecarga de Potencia! ⚡";
      String cuerpo = "El consumo alcanzó los $potActual W.";
      
      // --- LÓGICA DE APAGADO AUTOMÁTICO ---
      if (_autoApagar) {
        enviarComando("led_off"); // Corta la corriente inmediatamente
        cuerpo += " El enchufe se apagó por seguridad.";
      }

      _mostrarNotificacionPush(titulo, cuerpo);
      _guardarAlertaEnHistorial(titulo, cuerpo);
      _ultimaNotificacion = DateTime.now();
      
    } else if (consActual > _limiteConsumo) {
      String titulo = "¡Límite de Energía! 🔋";
      String cuerpo = "Has superado los $consActual kWh";
      _mostrarNotificacionPush(titulo, cuerpo);
      _guardarAlertaEnHistorial(titulo, cuerpo);
      _ultimaNotificacion = DateTime.now();
    }
  }

  Future<void> _mostrarNotificacionPush(String titulo, String cuerpo) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'canal_energia', 'Alertas de Energía',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.cyanAccent,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    
    await flutterLocalNotificationsPlugin.show(0, titulo, cuerpo, platformDetails);
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

  // --- INTERFAZ GRÁFICA ---

void _mostrarPanelAjustes(BuildContext context) {
    TextEditingController potCtrl = TextEditingController(text: _limitePotencia.toString());
    TextEditingController consCtrl = TextEditingController(text: _limiteConsumo.toString());
    bool autoApagarTemp = _autoApagar; 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // <-- Mantiene el permiso para subir
      backgroundColor: Colors.transparent, // <-- Lo hacemos transparente aquí
      builder: (context) {
        return StatefulBuilder( 
          builder: (BuildContext context, StateSetter setModalState) {
            
            return Padding(
              // 1. El padding que detecta el teclado va HASTA AFUERA
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                // 2. Le pasamos el diseño elegante al contenedor interno
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                ),
                // 3. El scroll ahora está protegido
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // <-- Clave para que no ocupe toda la pantalla
                      children: [
                        Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
                        const SizedBox(height: 20),
                        const Text("Ajustes del Dispositivo", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        
                        // --- INPUT POTENCIA ---
                        TextField(
                          controller: potCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.cyanAccent),
                          decoration: InputDecoration(
                            labelText: "Límite de Potencia (W)",
                            labelStyle: TextStyle(color: Colors.grey[400]),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)), borderRadius: BorderRadius.circular(15)),
                            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(15)),
                            prefixIcon: const Icon(Icons.speed, color: Colors.cyanAccent),
                          ),
                        ),
                        const SizedBox(height: 15),

                        // --- SWITCH DE APAGADO AUTOMÁTICO ---
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))
                          ),
                          child: SwitchListTile(
                            title: const Text("Apagar si excede los W", style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text("Corta la corriente por seguridad", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                            value: autoApagarTemp,
                            activeColor: Colors.cyanAccent,
                            onChanged: (bool value) {
                              setModalState(() {
                                autoApagarTemp = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 15),

                        // --- INPUT CONSUMO ---
                        TextField(
                          controller: consCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.purpleAccent),
                          decoration: InputDecoration(
                            labelText: "Límite de Consumo (kWh)",
                            labelStyle: TextStyle(color: Colors.grey[400]),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent.withOpacity(0.3)), borderRadius: BorderRadius.circular(15)),
                            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.purpleAccent), borderRadius: BorderRadius.circular(15)),
                            prefixIcon: const Icon(Icons.bolt, color: Colors.purpleAccent),
                          ),
                        ),
                        const SizedBox(height: 15),

                        // --- BOTÓN RESET CONSUMO ---
                        SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            icon: const Icon(Icons.restart_alt, color: Colors.redAccent),
                            label: const Text("RESET ACUMULADO (kWh)", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              enviarComando("reset"); 
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Comando de reset enviado al enchufe"), backgroundColor: Colors.purpleAccent)
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 25),

                        // --- BOTÓN GUARDAR ---
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              setState(() {
                                _limitePotencia = double.tryParse(potCtrl.text) ?? 1500.0;
                                _limiteConsumo = double.tryParse(consCtrl.text) ?? 5.0;
                                _autoApagar = autoApagarTemp; 
                              });
                              await prefs.setDouble('limitePotencia', _limitePotencia);
                              await prefs.setDouble('limiteConsumo', _limiteConsumo);
                              await prefs.setBool('autoApagar', _autoApagar);
                              Navigator.pop(context);
                            },
                            child: const Text("GUARDAR AJUSTES", style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _mostrarHistorial(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.7, // Ocupa el 70% de la pantalla
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Historial de Alertas", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        if (_historialAlertas.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                            onPressed: () {
                              _limpiarHistorial();
                              setModalState(() {}); // Actualiza el modal
                            },
                          )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _historialAlertas.isEmpty
                          ? Center(child: Text("No hay alertas registradas.", style: TextStyle(color: Colors.grey[500])))
                          : ListView.builder(
                              itemCount: _historialAlertas.length,
                              itemBuilder: (context, index) {
                                final alerta = _historialAlertas[index];
                                final fechaStr = alerta['fecha'] ?? '';
                                String fechaFormateada = "";
                                if (fechaStr.isNotEmpty) {
                                  DateTime dt = DateTime.parse(fechaStr);
                                  fechaFormateada = "${dt.day}/${dt.month} - ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                                }

                                return Card(
                                  color: const Color(0xFF0F172A),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  child: ListTile(
                                    leading: Icon(
                                      alerta['titulo']!.contains('Potencia') ? Icons.speed : Icons.bolt,
                                      color: alerta['titulo']!.contains('Potencia') ? Colors.cyanAccent : Colors.purpleAccent,
                                    ),
                                    title: Text(alerta['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text(alerta['cuerpo'] ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                                    trailing: Text(fechaFormateada, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                  ),
                                );
                              },
                            ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), 
      appBar: AppBar(
        title: Text(widget.dispositivo.name.isEmpty ? "Panel de Control" : widget.dispositivo.name, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            onPressed: () => _mostrarHistorial(context),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _mostrarPanelAjustes(context),
          )
        ],
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
                  Row(
                    children: [
                      _buildMedidorCard("VOLTAJE", "$voltaje V", Icons.electric_bolt, Colors.cyanAccent),
                      _buildMedidorCard("CORRIENTE", "$corriente A", Icons.waves, Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildMedidorCard("POTENCIA", "$potencia W", Icons.speed, Colors.greenAccent),
                      _buildMedidorCard("CONSUMO", "$consumo kWh", Icons.bolt, Colors.purpleAccent), 
                    ],
                  ),
                  
                  const SizedBox(height: 35),

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
                      color: const Color(0xFF1E293B), 
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: LineChart(
                      LineChartData(
                        minY: -200, 
                        maxY: 200,  
                        minX: 0,
                        maxX: 59, 
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
                            gradient: const LinearGradient(
                              colors: [Colors.cyanAccent, Colors.blueAccent, Colors.deepPurpleAccent],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
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
                        Container(width: 1, height: 40, color: Colors.grey[700]), 
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
    return Expanded( 
      child: InkWell(
        onTap: accion,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              Icon(icono, color: color, size: 24), 
              const SizedBox(width: 5),
              Flexible( 
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