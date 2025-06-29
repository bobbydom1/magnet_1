// main.dart - Flutter MagLev PID Tuner App v12.1 mit verbesserten UI-Anpassungen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// App Version
const String APP_VERSION = "v13.0";

// BLE UUIDs
final Guid serviceUuid = Guid("19B10000-E8F2-537E-4F6C-D104768A1214");
final Guid pidCommandUuid = Guid("19B10001-E8F2-537E-4F6C-D104768A1214");
final Guid statusDataUuid = Guid("19B10002-E8F2-537E-4F6C-D104768A1214");
final Guid calibrationUuid = Guid("19B10003-E8F2-537E-4F6C-D104768A1214");

// Datenklasse für Sensor-Messwerte
class SensorReading {
  final DateTime timestamp;
  final double x;
  final double y;
  final int duty1;
  final int duty2;

  SensorReading({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.duty1,
    required this.duty2,
  });
}

// NEU: Klasse für Kalibrierungs-Kurvenpunkte
class CalibrationPoint {
  final int pwm;
  final double mainAxis;  // Statt 'deviation'
  final double crossAxis; // NEU

  CalibrationPoint({required this.pwm, required this.mainAxis, required this.crossAxis});
}

// NEU: Klasse für Live-Kalibrierungsdaten
class LiveCalibrationData {
  List<CalibrationPoint> xPositiveLive = [];
  List<CalibrationPoint> xNegativeLive = [];
  List<CalibrationPoint> yPositiveLive = [];
  List<CalibrationPoint> yNegativeLive = [];

  int currentProgress = 0;
  String currentCurve = "";
  int totalPoints = 101;
  int maxPwm = 1014;

  double? xOffset;
  double? yOffset;

  bool isCalibrating = false;
  bool isComplete = false;

  String firmwareVersion = "";

  void clear() {
    xPositiveLive.clear();
    xNegativeLive.clear();
    yPositiveLive.clear();
    yNegativeLive.clear();
    currentProgress = 0;
    currentCurve = "";
    isCalibrating = false;
    isComplete = false;
  }
}

// NEU: Klasse für Kalibrierungs-Kurven
class CalibrationCurves {
  List<CalibrationPoint> xPositive = [];
  List<CalibrationPoint> xNegative = [];
  List<CalibrationPoint> yPositive = [];
  List<CalibrationPoint> yNegative = [];
  int totalPoints = 0;
  int maxPwm = 1023;
  bool isComplete = false;

  void clear() {
    xPositive.clear();
    xNegative.clear();
    yPositive.clear();
    yNegative.clear();
    totalPoints = 0;
    isComplete = false;
  }
}

// Widget-Größen für iOS-Style Layout
enum AnalysisWidgetSize {
  smallSquare,   // 1x1 Kachel
  tallRectangle, // 1x2 Kachel
  wideRectangle, // 2x1 Kachel
  largeSquare,   // 2x2 Kachel
  extraWide,     // 3x1 Kachel
  extraTall,     // 1x3 Kachel
  huge,          // 3x2 Kachel
  giant,         // 4x2 Kachel
  massive,       // 4x3 Kachel
  fullWidth,     // 4x4 Kachel
}

// Grid-Position für Widgets
class GridPosition {
  int x;
  int y;
  
  GridPosition({required this.x, required this.y});
  
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  
  factory GridPosition.fromJson(Map<String, dynamic> json) {
    return GridPosition(x: json['x'], y: json['y']);
  }
}

// Grid-Manager für Widget-Layout
class WidgetGridManager {
  static const int gridColumns = 4;
  static const double cellSize = 80.0; // Reduziert von 100
  static const double cellSpacing = 8.0; // Reduziert von 12 für bessere Raumnutzung
  
  // Berechne Spaltenanzahl basierend auf Bildschirmbreite
  static int getResponsiveGridColumns(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    
    if (orientation == Orientation.portrait) {
      // In Portrait: Berechne Spalten basierend auf verfügbarer Breite
      final availableWidth = screenWidth - 16; // 8px padding auf jeder Seite
      final columnWidth = cellSize + cellSpacing;
      return math.max(2, (availableWidth / columnWidth).floor());
    } else {
      // In Landscape: Mehr Spalten für horizontales Scrollen
      final availableWidth = screenWidth - 16;
      final columnWidth = cellSize + cellSpacing;
      // Mindestens 6 Spalten im Landscape, damit Scrollen möglich ist
      return math.max(6, (availableWidth / columnWidth).floor());
    }
  }
  
  // Findet eine freie Position im Grid
  static GridPosition? findFreePosition(List<AnalysisWidgetModel> widgets, AnalysisWidgetModel newWidget) {
    // Erstelle eine Belegungsmatrix
    var occupiedCells = <String>{};
    
    for (var widget in widgets) {
      if (widget.position != null) {
        for (int x = widget.position!.x; x < widget.position!.x + widget.gridWidth; x++) {
          for (int y = widget.position!.y; y < widget.position!.y + widget.gridHeight; y++) {
            occupiedCells.add('$x,$y');
          }
        }
      }
    }
    
    // Suche die erste freie Position
    for (int y = 0; y < 50; y++) { // Maximal 50 Zeilen
      for (int x = 0; x <= gridColumns - newWidget.gridWidth; x++) {
        bool canPlace = true;
        
        // Prüfe ob alle benötigten Zellen frei sind
        for (int dx = 0; dx < newWidget.gridWidth; dx++) {
          for (int dy = 0; dy < newWidget.gridHeight; dy++) {
            if (occupiedCells.contains('${x + dx},${y + dy}')) {
              canPlace = false;
              break;
            }
          }
          if (!canPlace) break;
        }
        
        if (canPlace) {
          return GridPosition(x: x, y: y);
        }
      }
    }
    
    return null;
  }
  
  // Berechnet die Höhe des Grids basierend auf der Anzahl der Zeilen
  static double calculateGridHeight(int rows) {
    return rows * (cellSize + cellSpacing) + cellSpacing;
  }
  
  // Prüft ob eine Position gültig ist
  static bool isValidPosition(List<AnalysisWidgetModel> widgets, AnalysisWidgetModel widget, GridPosition newPosition) {
    // Prüfe Grid-Grenzen
    if (newPosition.x < 0 || newPosition.y < 0 || 
        newPosition.x + widget.gridWidth > gridColumns) {
      return false;
    }
    
    // Prüfe Kollisionen mit anderen Widgets
    for (var other in widgets) {
      if (other.id == widget.id || other.position == null) continue;
      
      // Prüfe Überlappung
      bool overlapsX = newPosition.x < other.position!.x + other.gridWidth &&
                      newPosition.x + widget.gridWidth > other.position!.x;
      bool overlapsY = newPosition.y < other.position!.y + other.gridHeight &&
                      newPosition.y + widget.gridHeight > other.position!.y;
      
      if (overlapsX && overlapsY) {
        return false;
      }
    }
    
    return true;
  }
}

// Grid-Hintergrund Painter für Edit-Mode
class GridBackgroundPainter extends CustomPainter {
  final double cellWidth;
  final double cellHeight;
  final int gridColumns;
  
  GridBackgroundPainter({
    required this.cellWidth,
    required this.cellHeight,
    required this.gridColumns,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = WidgetGridManager.cellSpacing;
    final gridSizeX = cellWidth + spacing;
    final gridSizeY = cellHeight + spacing;
    
    // Hintergrund-Farbe für Grid-Zellen
    final cellPaint = Paint()
      ..color = CupertinoColors.systemGrey6.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    // Rahmen für Grid-Zellen
    final borderPaint = Paint()
      ..color = CupertinoColors.systemGrey4.withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    // Zeichne Grid-Zellen - genau so viele Spalten wie definiert
    for (double y = spacing; y < size.height; y += gridSizeY) {
      for (int col = 0; col < gridColumns; col++) {
        final x = col * gridSizeX + spacing;
        
        // Zell-Hintergrund
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellWidth, cellHeight),
          Radius.circular(16), // Gleicher Radius wie Widgets
        );
        
        canvas.drawRRect(rect, cellPaint);
        canvas.drawRRect(rect, borderPaint);
      }
    }
    
    // Spaltenbeschriftung entfernt - wird nicht benötigt
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// iOS-Style Glassmorphism Container
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color color;
  final EdgeInsetsGeometry? padding;

  const GlassmorphicContainer({
    Key? key,
    required this.child,
    this.borderRadius = 16.0,
    this.blur = 20.0,
    this.color = Colors.white,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 1.0,
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// NEU: Basisklasse für alle Analyse-Widgets
abstract class AnalysisWidgetModel {
  final String id;
  final String title;
  final String type;
  AnalysisWidgetSize size;
  GridPosition? position;
  Offset? dragOffset;  // Für stufenloses Ziehen
  bool isBeingDragged;
  bool isResizing;
  
  AnalysisWidgetModel({
    required this.id,
    required this.title,
    required this.type,
    required this.size,
    this.position,
    this.isBeingDragged = false,
    this.isResizing = false,
  });
  
  // Größe des Widgets im Grid
  int get gridWidth {
    switch (size) {
      case AnalysisWidgetSize.smallSquare:
      case AnalysisWidgetSize.tallRectangle:
      case AnalysisWidgetSize.extraTall:
        return 1;
      case AnalysisWidgetSize.wideRectangle:
      case AnalysisWidgetSize.largeSquare:
        return 2;
      case AnalysisWidgetSize.extraWide:
      case AnalysisWidgetSize.huge:
        return 3;
      case AnalysisWidgetSize.giant:
      case AnalysisWidgetSize.massive:
      case AnalysisWidgetSize.fullWidth:
        return 4;
    }
  }
  
  int get gridHeight {
    switch (size) {
      case AnalysisWidgetSize.smallSquare:
      case AnalysisWidgetSize.wideRectangle:
      case AnalysisWidgetSize.extraWide:
        return 1;
      case AnalysisWidgetSize.tallRectangle:
      case AnalysisWidgetSize.largeSquare:
      case AnalysisWidgetSize.huge:
      case AnalysisWidgetSize.giant:
        return 2;
      case AnalysisWidgetSize.extraTall:
      case AnalysisWidgetSize.massive:
        return 3;
      case AnalysisWidgetSize.fullWidth:
        return 4;
    }
  }
  
  // Verfügbare Größen für Resize
  List<AnalysisWidgetSize> get availableSizes => [
    AnalysisWidgetSize.smallSquare,
    AnalysisWidgetSize.tallRectangle,
    AnalysisWidgetSize.wideRectangle,
    AnalysisWidgetSize.largeSquare,
    AnalysisWidgetSize.extraWide,
    AnalysisWidgetSize.extraTall,
    AnalysisWidgetSize.huge,
    AnalysisWidgetSize.giant,
    AnalysisWidgetSize.massive,
    AnalysisWidgetSize.fullWidth,
  ];
}

// Widget-Model für Chart
class ChartWidgetModel extends AnalysisWidgetModel {
  final bool showGrid;
  final bool showLegend;
  final int displayRange; // Zeitfenster in Sekunden
  final bool showTimeControls; // Neue Option für Zeitkontrollen
  
  ChartWidgetModel({
    required String id,
    required String title,
    this.showGrid = true,
    this.showLegend = true,
    this.displayRange = 10,
    this.showTimeControls = false,
    AnalysisWidgetSize size = AnalysisWidgetSize.wideRectangle,
    GridPosition? position,
  }) : super(id: id, title: title, type: 'chart', size: size, position: position);
}

// Widget-Model für Statistik-Box
class StatisticsWidgetModel extends AnalysisWidgetModel {
  final List<String> selectedStats; // z.B. ['min', 'max', 'avg', 'stdDev']
  final bool showXAxis;
  final bool showYAxis;
  
  StatisticsWidgetModel({
    required String id,
    required String title,
    this.selectedStats = const ['min', 'max', 'avg', 'stdDev'],
    this.showXAxis = true,
    this.showYAxis = true,
    AnalysisWidgetSize size = AnalysisWidgetSize.wideRectangle,
    GridPosition? position,
  }) : super(id: id, title: title, type: 'statistics', size: size, position: position);
}

// Widget-Model für Frequenz-Anzeige
class FrequencyWidgetModel extends AnalysisWidgetModel {
  final bool showBleFreq;
  final bool showLoopFreq;
  
  FrequencyWidgetModel({
    required String id,
    required String title,
    this.showBleFreq = true,
    this.showLoopFreq = true,
    AnalysisWidgetSize size = AnalysisWidgetSize.smallSquare,
    GridPosition? position,
  }) : super(id: id, title: title, type: 'frequency', size: size, position: position);
}

// Widget-Model für Duty-Cycle Anzeige
class DutyCycleWidgetModel extends AnalysisWidgetModel {
  final bool showDuty1;
  final bool showDuty2;
  final bool showAsGauge;
  
  DutyCycleWidgetModel({
    required String id,
    required String title,
    this.showDuty1 = true,
    this.showDuty2 = true,
    this.showAsGauge = false,
    AnalysisWidgetSize size = AnalysisWidgetSize.smallSquare,
    GridPosition? position,
  }) : super(id: id, title: title, type: 'duty_cycle', size: size, position: position);
}

// NEU: Klasse für Analyse-Tabs mit Widget-Unterstützung
class AnalysisTab {
  final String title;
  final bool isLive;
  final List<SensorReading> data;
  final DateTime createdAt;
  final List<AnalysisWidgetModel> widgets;
  bool isEditMode;
  
  AnalysisTab({
    required this.title,
    required this.isLive,
    required this.data,
    DateTime? createdAt,
    List<AnalysisWidgetModel>? widgets,
    this.isEditMode = false,
  }) : createdAt = createdAt ?? DateTime.now(),
        widgets = widgets ?? _getDefaultWidgets();
  
  // Standard-Widget-Konfiguration für neue Tabs
  static List<AnalysisWidgetModel> _getDefaultWidgets() {
    return [
      ChartWidgetModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Sensor-Diagramm',
      ),
      StatisticsWidgetModel(
        id: '${DateTime.now().millisecondsSinceEpoch + 1}',
        title: 'Statistiken',
      ),
    ];
  }
}

// Klasse für Kalibrierungs-Updates
class CalibrationUpdate {
  final bool? isCalibrated;
  final bool isCalibrating;
  final int calibrationStep;
  final CalibrationData? currentCalibrationData;
  final bool hasCalibData;

  CalibrationUpdate({
    required this.isCalibrated,
    required this.isCalibrating,
    required this.calibrationStep,
    required this.currentCalibrationData,
    this.hasCalibData = false,
  });
}

// Separates StatefulWidget für Kalibrierungs-Dialog
class CalibrationDialog extends StatefulWidget {
  final CalibrationUpdate initialUpdate;
  final Stream<CalibrationUpdate> calibrationStream;
  final Future<void> Function() onStartCalibration;
  final Future<void> Function() onConfirmStep;
  final Future<void> Function() onCancel;
  final Future<void> Function(String) onSendCommand;

  const CalibrationDialog({
    Key? key,
    required this.initialUpdate,
    required this.calibrationStream,
    required this.onStartCalibration,
    required this.onConfirmStep,
    required this.onCancel,
    required this.onSendCommand,
  }) : super(key: key);

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  late StreamSubscription<CalibrationUpdate> _subscription;
  late CalibrationUpdate _currentUpdate;

  int _localStep = 0;
  bool _calibEnabled = true; // For calibration toggle
  bool _baseOffsetEnabled = true; // NEUE ZEILE HINZUGEFÜGT

  @override
  void initState() {
    super.initState();
    _currentUpdate = widget.initialUpdate;
    _localStep = _currentUpdate.isCalibrating ? _currentUpdate.calibrationStep : 0;

    _subscription = widget.calibrationStream.listen((update) {
      if (mounted) {
        setState(() {
          _currentUpdate = update;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentlyCalibratingOnEsp = _currentUpdate.isCalibrating;
    final espStep = _currentUpdate.calibrationStep;
    final currentCalibrationDataFromEsp = _currentUpdate.currentCalibrationData;
    final isEspCalibrated = _currentUpdate.isCalibrated;

    return WillPopScope(
      onWillPop: () async {
        if (isCurrentlyCalibratingOnEsp) {
          await widget.onCancel();
        }
        return true;
      },
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings_input_antenna, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Sensor-Positionierung'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isCurrentlyCalibratingOnEsp && (isEspCalibrated == null || !isEspCalibrated)) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Sensor-Position prüfen',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Prüfen Sie die Position des Sensors über dem Magneten.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('WICHTIG: Entferne den schwebenden Magneten vor der Positionierung!',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _localStep = 1; });
                    widget.onStartCalibration();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Positionierung starten'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48)),
                ),
              ] else if (isCurrentlyCalibratingOnEsp) ...[
                _buildCalibrationStep(
                    _localStep > 0 ? _localStep : espStep,
                    currentCalibrationDataFromEsp,
                    widget.onConfirmStep,
                    widget.onCancel,
                    espStep
                ),
              ] else if (isEspCalibrated == true) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 48),
                      SizedBox(height: 8),
                      Text('Positionierung abgeschlossen!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Die Sensor-Position wurde geprüft.', textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () async {
                      setState(() { _localStep = 1; });
                      await widget.onStartCalibration();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erneut positionieren'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fertig'))),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationStep(
      int displayStep,
      CalibrationData? currentDataFromEsp,
      Future<void> Function() onConfirm,
      Future<void> Function() onCancel,
      int currentEspStep
      ) {
    String stepTitle = '';
    String stepDescription = '';
    IconData stepIcon = Icons.settings;

    switch (displayStep) {
      case 1: stepTitle = 'Nullpunkt prüfen'; stepDescription = 'Sensor-Position bei ausgeschalteten Spulen prüfen.'; stepIcon = Icons.center_focus_strong; break;
      case 2: stepTitle = 'X-Achse (+)'; stepDescription = 'X-Position justieren. X-Spule positiv.'; stepIcon = Icons.arrow_forward; break;
      case 3: stepTitle = 'X-Achse (-)'; stepDescription = 'X-Position justieren. X-Spule negativ.'; stepIcon = Icons.arrow_back; break;
      case 4: stepTitle = 'Y-Achse (+)'; stepDescription = 'Y-Position justieren. Y-Spule positiv.'; stepIcon = Icons.arrow_upward; break;
      case 5: stepTitle = 'Y-Achse (-)'; stepDescription = 'Y-Position justieren. Y-Spule negativ.'; stepIcon = Icons.arrow_downward; break;
      case 6: stepTitle = 'Abschluss-Check'; stepDescription = 'Nullpunkt erneut prüfen. Spulen aus.'; stepIcon = Icons.check_circle_outline; break;
      default: stepTitle = 'Unbekannter Schritt'; stepDescription = 'Bitte warten...'; stepIcon = Icons.hourglass_empty;
    }
    if (displayStep == 0 && currentEspStep > 0) {
      stepTitle = 'Starte Kalibrierung...';
    }

    return Column(
      children: [
        LinearProgressIndicator(value: (displayStep / 6).clamp(0.0, 1.0)),
        const SizedBox(height: 8),
        Text('Schritt $displayStep von 6', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),

        Icon(stepIcon, size: 48, color: Colors.blue),
        const SizedBox(height: 8),
        Text(stepTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(stepDescription, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),

        if (displayStep == 1 && currentEspStep == 1 && currentDataFromEsp == null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Column(children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('ESP32 führt Basis-Messung durch...', textAlign: TextAlign.center)
            ]),
          ),
        ] else if (currentDataFromEsp != null && displayStep > 0 && displayStep <=6) ...[
          _buildPositionIndicator(currentDataFromEsp),
          const SizedBox(height: 16),
          _buildQualityIndicator(currentDataFromEsp),
          const SizedBox(height: 16),
          // Manual PWM Control Buttons
          if (displayStep >= 0 && displayStep <= 5) ...[
            _buildManualPWMControls(displayStep),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Column(children: const [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Warte auf Sensordaten vom ESP32...', textAlign: TextAlign.center)
            ]),
          ),
        ],
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(child: OutlinedButton(
                onPressed: () async {
                  await onCancel();
                  Navigator.pop(context);
                },
                child: const Text('Abbrechen')
            )),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  print("Weiter geklickt: UI-Schritt $displayStep, ESP32-Schritt $currentEspStep");

                  if (currentEspStep == 1) {
                    if (mounted) setState(() { if (_localStep < 6) _localStep++; });
                    print(">>> APP: Sende onConfirm für ESP32-Schritt 1");
                    await onConfirm();
                  } else if (currentEspStep > 1 && currentEspStep <= 6) {
                    if (mounted) setState(() { if (_localStep < 6) _localStep++; });
                    print(">>> APP: Sende onConfirm für ESP32-Schritt $currentEspStep");
                    await onConfirm();
                  }

                  if (currentEspStep >= 6 && _currentUpdate.isCalibrated == true && !_currentUpdate.isCalibrating) {
                    await Future.delayed(const Duration(milliseconds: 500));
                    if (mounted && _currentUpdate.isCalibrated == true && !_currentUpdate.isCalibrating) {
                      Navigator.pop(context);
                    }
                  } else if (_localStep > 6 && !_currentUpdate.isCalibrating) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (currentEspStep == 1) ? Colors.blue :
                  (currentDataFromEsp != null && currentDataFromEsp.quality >= 3)
                      ? Colors.green
                      : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                child: Text(displayStep == 1 ? 'Weiter (Basis)' : displayStep < 6 ? 'Weiter' : 'Fertigstellen'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPositionIndicator(CalibrationData data) {
    double x = data.x;
    double y = data.y;

    double normalizedX = (x / 5.0).clamp(-1.0, 1.0);
    double normalizedY = (y / 5.0).clamp(-1.0, 1.0);

    return SizedBox(
      width: 200,
      height: 200,
      child: Container(
        decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade400, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(children: [
        CustomPaint(size: const Size(200, 200), painter: GridPainter()),
        const Center(child: Icon(Icons.add, size: 40, color: Colors.red)),
        Positioned(
          left: 100 + (normalizedX * 80) - 10,
          top: 100 - (normalizedY * 80) - 10,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: _getQualityColor(data.quality), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)]),
          ),
        ),
        Positioned(bottom: 4, left: 4,
            child: Text('X: ${x.toStringAsFixed(2)} mT',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Positioned(bottom: 4, right: 4,
            child: Text('Y: ${y.toStringAsFixed(2)} mT',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
      ]),
      ),
    );
  }

  Widget _buildQualityIndicator(CalibrationData data) {
    int quality = data.quality;
    double deviation = data.deviation;
    String qualityText = '';
    Color qualityColor = Colors.grey;
    IconData qualityIcon = Icons.circle;

    switch (quality) {
      case 5: qualityText = 'PERFEKT!'; qualityColor = Colors.green; qualityIcon = Icons.star; break;
      case 4: qualityText = 'Sehr gut'; qualityColor = Colors.lightGreen; qualityIcon = Icons.thumb_up; break;
      case 3: qualityText = 'Gut'; qualityColor = Colors.yellow.shade700; qualityIcon = Icons.check; break;
      case 2: qualityText = 'OK'; qualityColor = Colors.orange; qualityIcon = Icons.remove; break;
      default: qualityText = 'Schlecht'; qualityColor = Colors.red; qualityIcon = Icons.close;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: qualityColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: qualityColor.withOpacity(0.3))
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(qualityIcon, color: qualityColor, size: 24),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(qualityText,
              style: TextStyle(color: qualityColor, fontWeight: FontWeight.bold, fontSize: 16)),
          Text('Abweichung: ${deviation.toStringAsFixed(2)} mT',
              style: TextStyle(color: qualityColor.withOpacity(0.8), fontSize: 12)),
        ]),
      ]),
    );
  }

  Color _getQualityColor(int quality) {
    switch (quality) {
      case 5: return Colors.green;
      case 4: return Colors.lightGreen;
      case 3: return Colors.yellow.shade700;
      case 2: return Colors.orange;
      default: return Colors.red;
    }
  }

  Widget _buildManualPWMControls(int step) {
    String axis = '';
    bool isXAxis = false;
    bool isYAxis = false;
    
    switch (step) {
      case 0: // Beide Achsen aus - nur Kalibrier-Toggle
        break;
      case 1: // Beide Achsen aus - nur Kalibrier-Toggle  
        break;
      case 2: 
      case 3:
        axis = 'X';
        isXAxis = true;
        break;
      case 4:
      case 5:
        axis = 'Y';
        isYAxis = true;
        break;
      default: return const SizedBox.shrink();
    }
    
    // Aktuelle PWM-Werte aus den Daten holen
    int currentPwmX = _currentUpdate.currentCalibrationData?.pwmX ?? 0;
    int currentPwmY = _currentUpdate.currentCalibrationData?.pwmY ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PWM-Steuerung nur wenn eine Achse aktiv ist
          if (step >= 2 && step <= 5) ...[
            Text(
              'Manueller PWM-Test',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            // X-Achse Steuerung
            if (isXAxis) ...[
              Text('X-Achse PWM: $currentPwmX', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _buildPWMButton(
                    label: '-100',
                    icon: Icons.remove,
                    onPressed: () => _sendIncrementalPWM('X', currentPwmX - 100),
                  ),
                  _buildPWMButton(
                    label: '-10',
                    icon: Icons.remove,
                    onPressed: () => _sendIncrementalPWM('X', currentPwmX - 10),
                  ),
                  _buildPWMButton(
                    label: '+10',
                    icon: Icons.add,
                    onPressed: () => _sendIncrementalPWM('X', currentPwmX + 10),
                  ),
                  _buildPWMButton(
                    label: '+100',
                    icon: Icons.add,
                    onPressed: () => _sendIncrementalPWM('X', currentPwmX + 100),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => widget.onSendCommand('SET_PWM_X=0'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('X PWM = 0'),
              ),
            ],
            
            // Y-Achse Steuerung
            if (isYAxis) ...[
              Text('Y-Achse PWM: $currentPwmY', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _buildPWMButton(
                    label: '-100',
                    icon: Icons.remove,
                    onPressed: () => _sendIncrementalPWM('Y', currentPwmY - 100),
                  ),
                  _buildPWMButton(
                    label: '-10',
                    icon: Icons.remove,
                    onPressed: () => _sendIncrementalPWM('Y', currentPwmY - 10),
                  ),
                  _buildPWMButton(
                    label: '+10',
                    icon: Icons.add,
                    onPressed: () => _sendIncrementalPWM('Y', currentPwmY + 10),
                  ),
                  _buildPWMButton(
                    label: '+100',
                    icon: Icons.add,
                    onPressed: () => _sendIncrementalPWM('Y', currentPwmY + 100),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => widget.onSendCommand('SET_PWM_Y=0'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Y PWM = 0'),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
          ],
          
          // Kalibrier-Toggle immer anzeigen
          SwitchListTile(
            title: const Text('Kalibrierkorrektur verwenden'),
            subtitle: Text(
              step == 0 || step == 1 || step == 5 
                ? 'Bei PWM=0 hat dies keinen Effekt'
                : 'Beeinflusst die angezeigten Werte',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            value: _calibEnabled,
            onChanged: (value) {
              setState(() => _calibEnabled = value);
              widget.onSendCommand('CALIB_POPUP=${value ? "ON" : "OFF"}');
            },
            contentPadding: EdgeInsets.zero,
          ),
          
          // --- AB HIER DEN NEUEN CODE EINFÜGEN ---
          
          const SizedBox(height: 8), // Ein kleiner Abstand
          
          SwitchListTile(
            title: const Text('Basis-Offset-Korrektur anwenden'),
            subtitle: const Text(
              'Korrigiert den statischen Nullpunkt des Sensors',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            value: _baseOffsetEnabled, // Verwendet die neue Zustandsvariable
            onChanged: (value) {
              // Aktualisiert den lokalen Zustand und sendet den Befehl
              setState(() => _baseOffsetEnabled = value); 
              widget.onSendCommand('BASE_OFFSET=${value ? "ON" : "OFF"}');
            },
            contentPadding: EdgeInsets.zero,
          ),
          
          // --- ENDE DES NEUEN CODES ---
        ],
      ),
    );
  }
  
  Widget _buildPWMButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(50, 32),
      ),
    );
  }
  
  void _sendIncrementalPWM(String axis, int newValue) {
    // Begrenzen auf 0-1014 (DUTY_MAX)
    newValue = newValue.clamp(0, 1014);
    widget.onSendCommand('SET_PWM_$axis=$newValue');
  }
}

// Klasse für Kalibrierungsdaten
class CalibrationData {
  final double x;
  final double y;
  final double deviation;
  final int quality;
  final int? pwmX;
  final int? pwmY;

  CalibrationData({
    required this.x,
    required this.y,
    required this.deviation,
    required this.quality,
    this.pwmX,
    this.pwmY,
  });
}

// Hilfsklasse für Statistik-Zeilen
class StatRow {
  final String label;
  final String value;
  final Color? color;

  StatRow(this.label, this.value, [this.color]);
}

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.none); // NEUE ZEILE: Schaltet FBP-Logs aus
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MagLevTunerApp());
}

class MagLevTunerApp extends StatelessWidget {
  const MagLevTunerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MagLev PID Tuner $APP_VERSION',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Calibration UI states
enum CalibUiState {
  idle,
  ready_for_download,
  downloading,
  download_complete,
  download_aborted,
  error
}

// NEU: Dynamische Analyse-Workspace-Seite
class AnalysisWorkspacePage extends StatefulWidget {
  final List<SensorReading> sensorHistory;
  final bool isRecording;
  final Function(bool) onRecordingChanged;
  final int displayHistoryLength;
  final Function(int) onDisplayHistoryLengthChanged;
  final Function() onExportToCSV;
  final VoidCallback onClearHistory;
  final Function(bool)? onWidgetTouchChanged;
  
  const AnalysisWorkspacePage({
    Key? key,
    required this.sensorHistory,
    required this.isRecording,
    required this.onRecordingChanged,
    required this.displayHistoryLength,
    required this.onDisplayHistoryLengthChanged,
    required this.onExportToCSV,
    required this.onClearHistory,
    this.onWidgetTouchChanged,
  }) : super(key: key);

  @override
  State<AnalysisWorkspacePage> createState() => _AnalysisWorkspacePageState();
}

class _AnalysisWorkspacePageState extends State<AnalysisWorkspacePage> {
  // State für dynamische Tabs
  List<AnalysisTab> openTabs = [];
  int activeTabIndex = 0;
  
  // Frequenz und Duty Cycle Werte (werden über HomePage aktualisiert)
  double bleFrequency = 0.0;
  double loopFrequency = 0.0;
  int lastDuty1 = 0;
  int lastDuty2 = 0;
  
  @override
  void initState() {
    super.initState();
    // Initialisiere mit Live-Stream Tab
    openTabs = [
      AnalysisTab(
        title: 'Live-Stream',
        isLive: true,
        data: widget.sensorHistory,
      ),
    ];
    
    // ScrollController Listener um Scrollen zu verhindern wenn Widget berührt wird
    _scrollController.addListener(() {
      // BEGRÜNDUNG: Die Sperre wird nur noch aktiv, wenn kein Widget gezogen wird (_currentDragWidget == null).
      if (_isWidgetBeingTouched && _currentDragWidget == null && _lockedScrollPosition != null) {
        if (_scrollController.offset != _lockedScrollPosition) {
          _scrollController.jumpTo(_lockedScrollPosition!);
        }
      }
    });
    
    _horizontalScrollController.addListener(() {
      // BEGRÜNDUNG: Die Sperre wird nur noch aktiv, wenn kein Widget gezogen wird (_currentDragWidget == null).
      if (_isWidgetBeingTouched && _currentDragWidget == null && _lockedHorizontalScrollPosition != null) {
        if (_horizontalScrollController.offset != _lockedHorizontalScrollPosition) {
          _horizontalScrollController.jumpTo(_lockedHorizontalScrollPosition!);
        }
      }
    });
    
    // Initialisiere Orientierung und Grid-Zeilen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialisiere Orientierung korrekt
      final orientation = MediaQuery.of(context).orientation;
      _isPortrait = orientation == Orientation.portrait;
      
      // Setze initiale Grid-Zeilen basierend auf vorhandenen Widgets
      int maxRow = 0;
      for (var tab in openTabs) {
        for (var widget in tab.widgets) {
          if (widget.position != null) {
            final bottomRow = widget.position!.y + widget.gridHeight - 1;
            if (bottomRow > maxRow) {
              maxRow = bottomRow;
            }
          }
        }
      }
      
      setState(() {
        _currentGridRows = math.max(maxRow + 2, 10); // Mindestens 10 Zeilen
      });
    });
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }
  
  void _createSnapshot() {
    final now = DateTime.now();
    final title = 'Snapshot ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    // Erstelle eine echte Kopie der Daten
    final snapshotData = List<SensorReading>.from(widget.sensorHistory);
    
    setState(() {
      openTabs.add(AnalysisTab(
        title: title,
        isLive: false,
        data: snapshotData,
      ));
      activeTabIndex = openTabs.length - 1;
    });
  }
  
  void _showNewTabMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.camera_alt_outlined, color: Colors.blue),
                        ),
                        title: const Text(
                          'Snapshot erstellen',
                          style: TextStyle(fontSize: 17),
                        ),
                        subtitle: const Text(
                          'Momentaufnahme der aktuellen Daten',
                          style: TextStyle(fontSize: 13),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _createSnapshot();
                        },
                      ),
                      const Divider(height: 0.5, indent: 60),
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.analytics_outlined, color: Colors.grey),
                        ),
                        title: const Text(
                          'FFT-Analyse',
                          style: TextStyle(fontSize: 17, color: Colors.grey),
                        ),
                        subtitle: const Text(
                          'Kommt bald',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        enabled: false,
                        onTap: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _closeTab(int index) {
    if (openTabs.length > 1 && !openTabs[index].isLive) {
      setState(() {
        openTabs.removeAt(index);
        if (activeTabIndex >= openTabs.length) {
          activeTabIndex = openTabs.length - 1;
        } else if (activeTabIndex > index) {
          activeTabIndex--;
        }
      });
    }
  }
  
  void _showSnapshotStatistics() {
    final activeTab = openTabs[activeTabIndex];
    if (!activeTab.isLive && activeTab.data.isNotEmpty) {
      // Berechne Statistiken für Snapshot
      final stats = _calculateStatistics(activeTab.data);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Statistik - ${activeTab.title}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatRow('Datenpunkte:', stats['count'].toString()),
                const Divider(),
                _buildStatRow('X Min:', '${stats['xMin'].toStringAsFixed(3)} mT'),
                _buildStatRow('X Max:', '${stats['xMax'].toStringAsFixed(3)} mT'),
                _buildStatRow('X Durchschnitt:', '${stats['xAvg'].toStringAsFixed(3)} mT'),
                _buildStatRow('X Std.Abw.:', '${stats['xStdDev'].toStringAsFixed(3)} mT'),
                const Divider(),
                _buildStatRow('Y Min:', '${stats['yMin'].toStringAsFixed(3)} mT'),
                _buildStatRow('Y Max:', '${stats['yMax'].toStringAsFixed(3)} mT'),
                _buildStatRow('Y Durchschnitt:', '${stats['yAvg'].toStringAsFixed(3)} mT'),
                _buildStatRow('Y Std.Abw.:', '${stats['yStdDev'].toStringAsFixed(3)} mT'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    }
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
  
  Map<String, dynamic> _calculateStatistics(List<SensorReading> data) {
    if (data.isEmpty) {
      return {
        'count': 0,
        'xMin': 0.0, 'xMax': 0.0, 'xAvg': 0.0, 'xStdDev': 0.0,
        'yMin': 0.0, 'yMax': 0.0, 'yAvg': 0.0, 'yStdDev': 0.0,
      };
    }
    
    // X-Achse Statistiken
    final xValues = data.map((r) => r.x).toList();
    final xMin = xValues.reduce(math.min);
    final xMax = xValues.reduce(math.max);
    final xAvg = xValues.reduce((a, b) => a + b) / xValues.length;
    final xStdDev = math.sqrt(
      xValues.map((x) => math.pow(x - xAvg, 2)).reduce((a, b) => a + b) / xValues.length
    );
    
    // Y-Achse Statistiken
    final yValues = data.map((r) => r.y).toList();
    final yMin = yValues.reduce(math.min);
    final yMax = yValues.reduce(math.max);
    final yAvg = yValues.reduce((a, b) => a + b) / yValues.length;
    final yStdDev = math.sqrt(
      yValues.map((y) => math.pow(y - yAvg, 2)).reduce((a, b) => a + b) / yValues.length
    );
    
    return {
      'count': data.length,
      'xMin': xMin, 'xMax': xMax, 'xAvg': xAvg, 'xStdDev': xStdDev,
      'yMin': yMin, 'yMax': yMax, 'yAvg': yAvg, 'yStdDev': yStdDev,
    };
  }
  
  void _showContextMenu() {
    final activeTab = openTabs[activeTabIndex];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      // Bearbeiten-Modus Toggle
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: activeTab.isEditMode ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            activeTab.isEditMode ? Icons.done : Icons.edit,
                            color: activeTab.isEditMode ? Colors.orange : Colors.blue,
                          ),
                        ),
                        title: Text(
                          activeTab.isEditMode ? 'Bearbeitung beenden' : 'Widgets bearbeiten',
                          style: const TextStyle(fontSize: 17),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            activeTab.isEditMode = !activeTab.isEditMode;
                          });
                        },
                      ),
                      const Divider(height: 0.5, indent: 60),
                      
                      // Tab umbenennen (für alle Tabs)
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_outlined, color: Colors.blue),
                        ),
                        title: const Text(
                          'Tab umbenennen',
                          style: TextStyle(fontSize: 17),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _renameTab(activeTabIndex);
                        },
                      ),
                      
                      if (activeTab.isLive) ...[
                        const Divider(height: 0.5, indent: 60),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.file_download_outlined, color: Colors.grey),
                          ),
                          title: const Text(
                            'Als CSV exportieren',
                            style: TextStyle(fontSize: 17, color: Colors.grey),
                          ),
                          subtitle: const Text(
                            'Nur für Snapshots verfügbar',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          enabled: false,
                        ),
                        const Divider(height: 0.5, indent: 60),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.trending_flat, color: Colors.grey),
                          ),
                          title: const Text(
                            'Gleitender Mittelwert',
                            style: TextStyle(fontSize: 17, color: Colors.grey),
                          ),
                          subtitle: const Text(
                            'Kommt bald',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          enabled: false,
                        ),
                        const Divider(height: 0.5, indent: 60),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.vertical_align_center, color: Colors.grey),
                          ),
                          title: const Text(
                            'Trigger-Schranke',
                            style: TextStyle(fontSize: 17, color: Colors.grey),
                          ),
                          subtitle: const Text(
                            'Kommt bald',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          enabled: false,
                        ),
                      ] else ...[
                        const Divider(height: 0.5, indent: 60),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.file_download_outlined, color: Colors.blue),
                          ),
                          title: const Text(
                            'Als CSV exportieren',
                            style: TextStyle(fontSize: 17),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _exportSnapshotToCSV(activeTab);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _exportSnapshotToCSV(AnalysisTab tab) async {
    // Verwende die bestehende Export-Funktionalität
    // Erstelle temporäre CSV-Daten
    String csv = 'Timestamp,X (mT),Y (mT),Duty1,Duty2\n';
    for (var reading in tab.data) {
      csv += '${reading.timestamp.toIso8601String()},${reading.x},${reading.y},${reading.duty1},${reading.duty2}\n';
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/maglev_${tab.title.replaceAll(':', '-')}.csv');
    await file.writeAsString(csv);
    
    Share.shareXFiles([XFile(file.path)], text: 'MagLev Sensor Data - ${tab.title}');
  }
  
  void _renameTab(int index) {
    final controller = TextEditingController(text: openTabs[index].title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tab umbenennen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Neuer Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                openTabs[index] = AnalysisTab(
                  title: controller.text,
                  isLive: openTabs[index].isLive,
                  data: openTabs[index].data,
                  createdAt: openTabs[index].createdAt,
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final activeTab = openTabs[activeTabIndex];
    
    
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // iOS System Background
      body: Column(
        children: [
          // iOS-Style Tab-Leiste - Container geht bis zum Rand, nur Inhalt wird geschützt
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Container(
              height: 44, // iOS Standard Tab Height
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: openTabs.length,
                        itemBuilder: (context, index) {
                          final tab = openTabs[index];
                          final isActive = index == activeTabIndex;
                          
                          return GestureDetector(
                            onTap: () => setState(() => activeTabIndex = index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              constraints: const BoxConstraints(maxWidth: 180),
                              margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                              padding: EdgeInsets.symmetric(
                                horizontal: tab.isLive ? 16 : 12,
                                vertical: 0,
                              ),
                              decoration: BoxDecoration(
                                color: isActive 
                                  ? Colors.blue.withOpacity(0.15)
                                  : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tab.isLive 
                                      ? Icons.sensors 
                                      : Icons.camera_alt_outlined,
                                    size: 18,
                                    color: isActive 
                                      ? Colors.blue 
                                      : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      tab.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: isActive 
                                          ? Colors.blue 
                                          : Colors.grey.shade600,
                                        fontWeight: isActive 
                                          ? FontWeight.w600 
                                          : FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!tab.isLive) ...[
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _closeTab(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 32,
                      onPressed: _showNewTabMenu,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: CupertinoColors.activeBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          CupertinoIcons.plus,
                          size: 18,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Haupt-Content Bereich mit konfigurierbaren Widgets
          Expanded(
            child: Stack(
              children: [
                // Widget-Liste
                activeTab.widgets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.widgets_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Keine Widgets konfiguriert',
                            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Widget hinzufügen'),
                            onPressed: () => _showAddWidgetDialog(activeTabIndex),
                          ),
                        ],
                      ),
                    )
                  : _buildWidgetGrid(
                      widgets: activeTab.widgets,
                      tabIndex: activeTabIndex,
                      data: activeTab.isLive ? this.widget.sensorHistory : activeTab.data,
                      isEditMode: activeTab.isEditMode,
                    ),
                
                
                // Add Widget Button (nur im Edit-Mode)
                if (activeTab.isEditMode)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      onPressed: () => _showAddWidgetDialog(activeTabIndex),
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          
          // iOS-Style Werkzeugleiste
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: activeTab.isLive
                  ? _buildLiveStreamToolbar()
                  : _buildSnapshotToolbar(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLiveStreamToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Platzhalter für zukünftige Live-Toolbar-Funktionen
        Text(
          'Live-Stream',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        
        // Drei-Punkte-Menü
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showContextMenu,
        ),
      ],
    );
  }
  
  Widget _buildSnapshotToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.zoom_in),
          onPressed: null, // Platzhalter
          tooltip: 'Zoom In (kommt bald)',
        ),
        IconButton(
          icon: const Icon(Icons.zoom_out),
          onPressed: null, // Platzhalter
          tooltip: 'Zoom Out (kommt bald)',
        ),
        IconButton(
          icon: const Icon(Icons.straighten),
          onPressed: null, // Platzhalter
          tooltip: 'Mess-Cursor (kommt bald)',
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.bar_chart),
          label: const Text('Statistik'),
          onPressed: _showSnapshotStatistics,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showContextMenu,
        ),
      ],
    );
  }
  
  Widget _buildWidgetGrid({
    required List<AnalysisWidgetModel> widgets,
    required int tabIndex,
    required List<SensorReading> data,
    required bool isEditMode,
  }) {
    // Orientierung prüfen
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final gridColumns = WidgetGridManager.getResponsiveGridColumns(context);
    
    // Orientierungswechsel erkennen
    if (isPortrait != _isPortrait) {
      _handleOrientationChange(isPortrait, widgets, tabIndex);
      _isPortrait = isPortrait;
    }
    
    // Stelle sicher, dass alle Widgets Positionen haben
    for (var widget in widgets) {
      if (widget.position == null) {
        widget.position = WidgetGridManager.findFreePosition(widgets, widget);
      }
    }
    
    // Berechne die tatsächlich benötigte Grid-Höhe basierend auf dem untersten Widget
    int maxRow = 0;
    int maxCol = 0;
    for (var widget in widgets) {
      if (widget.position != null) {
        final bottomRow = widget.position!.y + widget.gridHeight - 1;
        if (bottomRow > maxRow) {
          maxRow = bottomRow;
        }
        
        // Berechne auch die rechteste Spalte für Landscape-Modus
        final rightCol = widget.position!.x + widget.gridWidth - 1;
        if (rightCol > maxCol) {
          maxCol = rightCol;
        }
      }
    }
    
    // Im Bearbeitungsmodus: Zeige das ganze Grid
    // Im normalen Modus: Nur bis zum untersten Widget + etwas Puffer
    final effectiveRows = isEditMode 
        ? _currentGridRows  // Im Edit-Modus das volle Grid zeigen
        : math.min(maxRow + 3, _currentGridRows);  // Im Normal-Modus nur bis zum letzten Widget + Puffer
    
    final gridHeight = WidgetGridManager.calculateGridHeight(effectiveRows);
    final minHeight = MediaQuery.of(context).size.height - 200; // Fast volle Höhe minus Header/Toolbar
    
    // Berechne Grid-Breite basierend auf Orientierung
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Im Landscape-Modus: Passe die Grid-Breite an die Widgets an
    final effectiveCols = isEditMode || isPortrait
        ? gridColumns  // Im Portrait oder Edit-Modus normale Spaltenanzahl
        : math.min(maxCol + 3, gridColumns);  // Im Landscape normal-Modus nur bis zum rechtesten Widget + Puffer
    
    final gridWidth = screenWidth - 16; // Reduziertes Padding (8px auf jeder Seite)
    
    // Berechne die tatsächliche Zellengröße basierend auf verfügbarem Platz
    // Bessere Formel: (verfügbare Breite - Gesamtspacing) / Anzahl Spalten
    final totalSpacing = WidgetGridManager.cellSpacing * (gridColumns + 1);
    final cellWidth = (gridWidth - totalSpacing) / gridColumns;
    final cellHeight = isPortrait ? cellWidth : WidgetGridManager.cellSize; // In Portrait quadratisch, in Landscape fixe Höhe
    
    return GestureDetector(
      // Blockiere horizontale Swipes wenn Widget berührt wird
      onHorizontalDragStart: isEditMode && (_isWidgetBeingTouched || _currentDragWidget != null) 
          ? (_) {} // Leerer Handler blockiert die Geste
          : null,
      child: Container(
        padding: const EdgeInsets.only(left: 8, top: 8, right: 8, bottom: 8),
        child: Listener(
        onPointerDown: (event) {
          if (isEditMode) {
            // Prüfe ob der Touch auf einem Widget ist
            final localPosition = event.localPosition - const Offset(8, 8); // Padding abziehen
            
            for (var widget in widgets) {
              if (widget.position != null) {
                final widgetLeft = widget.position!.x * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                final widgetTop = widget.position!.y * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                final widgetRight = widgetLeft + widget.gridWidth * cellWidth + (widget.gridWidth - 1) * WidgetGridManager.cellSpacing;
                final widgetBottom = widgetTop + widget.gridHeight * cellHeight + (widget.gridHeight - 1) * WidgetGridManager.cellSpacing;
                
                // Berücksichtige Scroll-Offset je nach Orientierung
                final verticalScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                final horizontalScrollOffset = _horizontalScrollController.hasClients ? _horizontalScrollController.offset : 0.0;
                
                // Immer beide Scroll-Offsets berücksichtigen, falls vorhanden
                final adjustedX = localPosition.dx + horizontalScrollOffset;
                final adjustedY = localPosition.dy + verticalScrollOffset;
                
                if (adjustedX >= widgetLeft && 
                    adjustedX <= widgetRight && 
                    adjustedY >= widgetTop && 
                    adjustedY <= widgetBottom) {
                  _setWidgetBeingTouched(true);
                  return;
                }
              }
            }
            _setWidgetBeingTouched(false);
          }
        },
        onPointerUp: (_) {
          _setWidgetBeingTouched(false);
        },
        onPointerCancel: (_) {
          _setWidgetBeingTouched(false);
        },
        child: isPortrait 
            ? SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.vertical,
                // BEGRÜNDUNG: Erlaubt programmatisches Scrollen, auch wenn ein Widget gezogen wird.
                physics: isEditMode && _isWidgetBeingTouched
                      ? const NeverScrollableScrollPhysics() 
                      : const AlwaysScrollableScrollPhysics(),
                child: Container(
                  width: double.infinity,
                  height: gridHeight < minHeight ? minHeight : gridHeight,
                  child: Stack(
                  children: [
                    // Grid-Hintergrund - nur im Edit-Modus sichtbar
                    if (isEditMode) _buildGridBackground(),
                    
                    // Vorschau-Rechteck beim Verschieben
                    if (_currentDragWidget != null && _dragPreviewPosition != null)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 100),
                        left: _dragPreviewPosition!.x * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
                        top: _dragPreviewPosition!.y * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
                        width: _currentDragWidget!.gridWidth * cellWidth + 
                               (_currentDragWidget!.gridWidth - 1) * WidgetGridManager.cellSpacing,
                        height: _currentDragWidget!.gridHeight * cellHeight + 
                                (_currentDragWidget!.gridHeight - 1) * WidgetGridManager.cellSpacing,
                        child: Container(
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: CupertinoColors.systemGreen,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    
                    // Widgets
                    ...widgets.asMap().entries.map((entry) {
                      final index = entry.key;
                      final widget = entry.value;
                      
                      if (widget.position == null) return Container();
                      
                      final posX = widget.isBeingDragged && widget.dragOffset != null
                          ? widget.dragOffset!.dx * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing
                          : widget.position!.x * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                          
                      final posY = widget.isBeingDragged && widget.dragOffset != null
                          ? widget.dragOffset!.dy * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing
                          : widget.position!.y * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                      
                      return Positioned(
                        left: posX,
                        top: posY,
                        width: widget.gridWidth * cellWidth + 
                               (widget.gridWidth - 1) * WidgetGridManager.cellSpacing,
                        height: widget.gridHeight * cellHeight + 
                                (widget.gridHeight - 1) * WidgetGridManager.cellSpacing,
                        child: AnimatedContainer(
                          duration: widget.isBeingDragged 
                              ? Duration.zero 
                              : const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: _buildGridWidget(
                            model: widget,
                            tabIndex: tabIndex,
                            widgetIndex: index,
                            data: data,
                            isEditMode: isEditMode,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ))
            : SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    // BEGRÜNDUNG: Erlaubt programmatisches Scrollen, auch wenn ein Widget gezogen wird.
                    physics: isEditMode && _isWidgetBeingTouched
                        ? const NeverScrollableScrollPhysics() 
                        : const AlwaysScrollableScrollPhysics(),
                    child: Container(
                    // Berechne die effektive Breite basierend auf den Widgets im Landscape-Modus
                    // Wichtig: Die Breite muss größer als der Viewport sein, damit Scrollen möglich ist
                    width: () {
                      final calculatedWidth = (gridColumns * (cellWidth + WidgetGridManager.cellSpacing)) + WidgetGridManager.cellSpacing;
                      final viewportWidth = MediaQuery.of(context).size.width - 16;
                      
                      // Im Edit-Modus oder wenn Widgets außerhalb des sichtbaren Bereichs sind
                      if (isEditMode) {
                        return math.max(calculatedWidth, viewportWidth);
                      } else {
                        // Im Normal-Modus: Breite basierend auf dem rechtesten Widget
                        final neededWidth = ((maxCol + 3) * (cellWidth + WidgetGridManager.cellSpacing)) + WidgetGridManager.cellSpacing;
                        return math.max(neededWidth, viewportWidth);
                      }
                    }(),
                    height: gridHeight < minHeight ? minHeight : gridHeight,
                    child: Stack(
                    children: [
                      // Grid-Hintergrund - nur im Edit-Modus sichtbar
                      if (isEditMode) _buildGridBackground(),
                      
                      // Vorschau-Rechteck beim Verschieben
                      if (_currentDragWidget != null && _dragPreviewPosition != null)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 100),
                          left: _dragPreviewPosition!.x * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
                          top: _dragPreviewPosition!.y * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
                          width: _currentDragWidget!.gridWidth * cellWidth + 
                                 (_currentDragWidget!.gridWidth - 1) * WidgetGridManager.cellSpacing,
                          height: _currentDragWidget!.gridHeight * cellHeight + 
                                  (_currentDragWidget!.gridHeight - 1) * WidgetGridManager.cellSpacing,
                          child: Container(
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGreen.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: CupertinoColors.systemGreen,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      
                      // Widgets für Landscape
                      ...widgets.asMap().entries.map((entry) {
                final index = entry.key;
                final widget = entry.value;
                
                if (widget.position == null) return Container();
                
                // Verwende dragOffset wenn das Widget gezogen wird, sonst die normale Position
                final posX = widget.isBeingDragged && widget.dragOffset != null
                    ? widget.dragOffset!.dx * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing
                    : widget.position!.x * (cellWidth + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                    
                final posY = widget.isBeingDragged && widget.dragOffset != null
                    ? widget.dragOffset!.dy * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing
                    : widget.position!.y * (cellHeight + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing;
                
                // Debug output entfernt um Performance zu verbessern
                
                return Positioned(
                  left: posX,
                  top: posY,
                  width: widget.gridWidth * cellWidth + 
                         (widget.gridWidth - 1) * WidgetGridManager.cellSpacing,
                  height: widget.gridHeight * cellHeight + 
                          (widget.gridHeight - 1) * WidgetGridManager.cellSpacing,
                  child: AnimatedContainer(
                    duration: widget.isBeingDragged 
                        ? Duration.zero 
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _buildGridWidget(
                      model: widget,
                      tabIndex: tabIndex,
                      widgetIndex: index,
                      data: data,
                      isEditMode: isEditMode,
                    ),
                  ),
                );
              }).toList(),
                    ],
                  ),
                ),
              ),
          ),
        ),
      );
  }
  
  Widget _buildGridBackground() {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;
    final gridColumns = WidgetGridManager.getResponsiveGridColumns(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = screenWidth - 16; // Gleiche Berechnung wie in _buildWidgetGrid
    
    // Gleiche Formel wie in _buildWidgetGrid verwenden
    final totalSpacing = WidgetGridManager.cellSpacing * (gridColumns + 1);
    final cellWidth = (gridWidth - totalSpacing) / gridColumns;
    final cellHeight = isPortrait ? cellWidth : WidgetGridManager.cellSize;
    
    return CustomPaint(
      size: Size.infinite,
      painter: GridBackgroundPainter(
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        gridColumns: gridColumns,
      ),
    );
  }
  
  Widget _buildDropZones(List<AnalysisWidgetModel> widgets) {
    return Stack(
      children: [
        for (int y = 0; y < 10; y++)
          for (int x = 0; x < WidgetGridManager.gridColumns; x++)
            Positioned(
              left: x * (WidgetGridManager.cellSize + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
              top: y * (WidgetGridManager.cellSize + WidgetGridManager.cellSpacing) + WidgetGridManager.cellSpacing,
              width: WidgetGridManager.cellSize,
              height: WidgetGridManager.cellSize,
              child: DragTarget<AnalysisWidgetModel>(
                onWillAccept: (data) {
                  if (data == null) return false;
                  final newPosition = GridPosition(x: x, y: y);
                  return WidgetGridManager.isValidPosition(widgets, data, newPosition);
                },
                onAccept: (data) {
                  setState(() {
                    data.position = GridPosition(x: x, y: y);
                  });
                  HapticFeedback.lightImpact();
                },
                builder: (context, candidateData, rejectedData) {
                  final hasCandidate = candidateData.isNotEmpty;
                  return Container(
                    decoration: BoxDecoration(
                      color: hasCandidate 
                          ? CupertinoColors.activeBlue.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: hasCandidate
                          ? Border.all(
                              color: CupertinoColors.activeBlue,
                              width: 2,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }
  
  Widget _buildGridWidget({
    required AnalysisWidgetModel model,
    required int tabIndex,
    required int widgetIndex,
    required List<SensorReading> data,
    required bool isEditMode,
  }) {
    final activeTab = openTabs[tabIndex];
    
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (isEditMode) {
          // Sofort blockieren, ohne auf Gesture-Erkennung zu warten
          _setWidgetBeingTouched(true);
          
          // Wichtig: Sofort HapticFeedback für bessere Reaktion
          HapticFeedback.selectionClick();
          
          // Stoppe aktives Scrolling sofort und verhindere weiteres Scrollen
          try {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.offset);
              // Wichtig: Position merken für späteren Vergleich
              _lockedScrollPosition = _scrollController.offset;
            }
            if (_horizontalScrollController.hasClients) {
              _horizontalScrollController.jumpTo(_horizontalScrollController.offset);
              // Wichtig: Position merken für späteren Vergleich  
              _lockedHorizontalScrollPosition = _horizontalScrollController.offset;
            }
          } catch (e) {
            // Error handling silent
          }
          
          // Touch detected - _isWidgetBeingTouched set to true
        }
      },
      onPointerUp: (_) {
        if (isEditMode) {
          _setWidgetBeingTouched(false);
          _lockedScrollPosition = null;
          _lockedHorizontalScrollPosition = null;
          // Pointer up - scroll unlocked
        }
      },
      onPointerCancel: (_) {
        if (isEditMode) {
          _setWidgetBeingTouched(false);
          _lockedScrollPosition = null;
          _lockedHorizontalScrollPosition = null;
          // Pointer cancelled - scroll unlocked
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Niedrigere Schwelle für Drag-Erkennung
        dragStartBehavior: DragStartBehavior.down,
        // Wichtig: onPanDown wird sofort beim Touch ausgelöst
        onPanDown: (details) {
          if (!isEditMode || model.isResizing) return;
          
          // Sofort visuelles Feedback geben und Scrollen blockieren
          setState(() {
            _currentDragWidget = model;
            model.isBeingDragged = true;
            _dragStartPosition = details.globalPosition;
            _dragStartGridPosition = model.position;
            _dragPreviewPosition = model.position;
            _setWidgetBeingTouched(true); // Wichtig: Sofort setzen für AbsorbPointer
          });
          
          HapticFeedback.selectionClick();
        },
        // Drag-Funktionalität für das gesamte Widget
        onPanStart: (details) {
          if (!isEditMode || model.isResizing) return;
          
          // onPanDown hat bereits die wichtigsten Werte gesetzt
          // Hier nur noch fehlende Werte ergänzen
          
          // Reset alle anderen Widgets
          for (var widget in openTabs[tabIndex].widgets) {
            if (widget != model) {
              widget.isBeingDragged = false;
              widget.dragOffset = null;
            }
          }
          
          // Setze den korrekten Scroll-Offset basierend auf der Orientierung
          final orientation = MediaQuery.of(context).orientation;
          final isPortrait = orientation == Orientation.portrait;
          
          _dragStartScrollOffset = isPortrait 
              ? (_scrollController.hasClients ? _scrollController.offset : 0.0)
              : (_horizontalScrollController.hasClients ? _horizontalScrollController.offset : 0.0);
          
          // Setze initiale dragOffset auf aktuelle Position
          model.dragOffset = Offset(
            model.position!.x.toDouble(),
            model.position!.y.toDouble(),
          );
          
          // Starte Auto-Scroll gleich beim Start
          _startAutoScroll(details.globalPosition.dy, dragPositionX: details.globalPosition.dx);
        },
        onPanUpdate: (details) {
          if (!isEditMode || !model.isBeingDragged || _currentDragWidget != model) return;

          if (_dragStartPosition != null && _dragStartGridPosition != null) {
            // Kompensiere für Scroll-Offset-Änderungen
            final orientation = MediaQuery.of(context).orientation;
            final isPortrait = orientation == Orientation.portrait;
            
            final currentScrollOffset = isPortrait 
                ? (_scrollController.hasClients ? _scrollController.offset : 0.0)
                : (_horizontalScrollController.hasClients ? _horizontalScrollController.offset : 0.0);
            final scrollDelta = currentScrollOffset - _dragStartScrollOffset;
            
            final delta = details.globalPosition - _dragStartPosition! + Offset(
              isPortrait ? 0 : scrollDelta,
              isPortrait ? scrollDelta : 0,
            );
            
            final currentGridColumns = WidgetGridManager.getResponsiveGridColumns(context);
            final screenWidth = MediaQuery.of(context).size.width;
            final gridWidth = screenWidth - 16;
            final totalSpacing = WidgetGridManager.cellSpacing * (currentGridColumns + 1);
            final cellWidth = (gridWidth - totalSpacing) / currentGridColumns;
            final cellHeight = isPortrait ? cellWidth : WidgetGridManager.cellSize;

            final exactX = _dragStartGridPosition!.x + (delta.dx / (cellWidth + WidgetGridManager.cellSpacing));
            final exactY = _dragStartGridPosition!.y + (delta.dy / (cellHeight + WidgetGridManager.cellSpacing));

            // Harte Grenze bei 50 Zeilen
            final maxAllowedRow = 50 - model.gridHeight;
            
            // Beschränke exactY auf die maximale erlaubte Position
            final clampedExactY = exactY.clamp(0.0, maxAllowedRow.toDouble());
            
            // Berechne die nächste Grid-Position für die Vorschau
            final previewX = exactX.round().clamp(0, currentGridColumns - model.gridWidth);
            final previewY = clampedExactY.round().clamp(0, math.min(_currentGridRows - 1, maxAllowedRow));
            
            final previewPosition = GridPosition(x: previewX.toInt(), y: previewY.toInt());
            
            // Erweitere Grid wenn nötig (aber nur bis zur maximalen Position)
            if (previewY >= _currentGridRows - 2 && _currentGridRows < 50) {
              setState(() {
                _currentGridRows = math.min(_currentGridRows + 1, 50);
              });
            }
            
            // Zeige Warnung wenn versucht wird, über die Grenze zu ziehen
            if (exactY > maxAllowedRow && !_maxRowsWarningShown) {
              _maxRowsWarningShown = true;
              
              // Haptisches Feedback für "harte Grenze"
              HapticFeedback.heavyImpact();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Maximale Anzahl von 50 Zeilen erreicht!'),
                    ],
                  ),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.orange.shade700,
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }

            setState(() {
              // Nur die Vorschau-Position aktualisieren, wenn die Position gültig ist (keine Kollision)
              if (WidgetGridManager.isValidPosition(openTabs[tabIndex].widgets, model, previewPosition)) {
                _dragPreviewPosition = previewPosition;
              }
              
              // Widget stoppt hart an der Grenze
              model.dragOffset = Offset(
                exactX.clamp(0.0, (currentGridColumns - model.gridWidth).toDouble()),
                clampedExactY,
              );
            });

            // Rufe die korrigierte Auto-Scroll-Funktion auf
            _startAutoScroll(details.globalPosition.dy, dragPositionX: details.globalPosition.dx);
          }
        },
        onPanEnd: (_) {
          if (!isEditMode || !model.isBeingDragged) return;
          // Pan ended
          
          // Setze Widget auf die Vorschau-Position
          if (_dragPreviewPosition != null) {
            model.position = _dragPreviewPosition;
            // Widget moved to preview position
          } else {
            // No preview position, keeping current position
          }
          
          model.isBeingDragged = false;
          model.dragOffset = null;  // Reset dragOffset
          _dragStartPosition = null;
          _dragStartGridPosition = null;
          _currentDragWidget = null;
          _dragPreviewPosition = null;
          _setWidgetBeingTouched(false); // Reset touch state
          _maxRowsWarningShown = false; // Reset warning flag
          
          // Stoppe Auto-Scroll
          _stopAutoScroll();
          
          // Drag ended, all values reset
          
          HapticFeedback.mediumImpact();
          
          // Verzögertes setState um Frame-Skipping zu vermeiden
          Future.microtask(() {
            if (mounted) {
              setState(() {});
            }
          });
        },
        onPanCancel: () {
          if (!isEditMode || !model.isBeingDragged) return;
          
          // Reset alles wenn Geste abgebrochen wird
          model.isBeingDragged = false;
          model.dragOffset = null;
          _dragStartPosition = null;
          _dragStartGridPosition = null;
          _currentDragWidget = null;
          _dragPreviewPosition = null;
          _setWidgetBeingTouched(false);
          
          setState(() {});
        },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          if (isEditMode) {
            // Widget is being resized
            // Touch detected - _isWidgetBeingTouched set to true
          }
        },
        onPointerUp: (_) {
          if (isEditMode && _currentDragWidget == null) {
            // Drag ended
          }
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: model.isBeingDragged ? 1.05 : 1.0,
          child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.systemGrey.withOpacity(
                  model.isBeingDragged ? 0.3 : 0.1
                ),
                blurRadius: model.isBeingDragged ? 20 : 10,
                offset: Offset(0, model.isBeingDragged ? 10 : 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
              // Widget-Inhalt
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    SizedBox(
                      height: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              model.title,
                              style: TextStyle(
                                fontSize: model.gridWidth >= 2 ? 14 : 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (model.type == 'chart' && !isEditMode && model.gridWidth >= 2)
                            GestureDetector(
                              onTap: () => _showWidgetSettings(tabIndex, widgetIndex),
                              child: Icon(
                                CupertinoIcons.settings,
                                size: 16,
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Content
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return _buildScaledWidgetContent(
                            model: model,
                            data: data,
                            constraints: constraints,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              // Edit-Mode Overlay
              if (isEditMode)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: model.isResizing 
                          ? CupertinoColors.activeBlue.withOpacity(0.1)
                          : model.isBeingDragged
                              ? CupertinoColors.systemGreen.withOpacity(0.1)
                              : CupertinoColors.systemGrey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: (model.isResizing || model.isBeingDragged)
                          ? Border.all(
                              color: model.isResizing 
                                  ? CupertinoColors.activeBlue
                                  : CupertinoColors.systemGreen,
                              width: 2,
                            )
                          : null,
                    ),
                    child: Stack(
                      children: [
                        // Drag Indikator (nur visuell)
                        Positioned(
                          top: 5,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 20,
                              decoration: BoxDecoration(
                                color: model.isBeingDragged
                                    ? CupertinoColors.systemGreen
                                    : CupertinoColors.systemGrey3.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                CupertinoIcons.move,
                                color: model.isBeingDragged
                                    ? CupertinoColors.white
                                    : CupertinoColors.systemGrey,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                        // Size Indicator während Resize
                        if (model.isResizing)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemBackground.resolveFrom(context),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: CupertinoColors.systemGrey.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                _getSizeLabel(model.size),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.activeBlue,
                                ),
                              ),
                            ),
                          ),
                        // Resize-Handle (Apple Style) mit größerem Touch-Bereich
                        Positioned(
                          right: -10,
                          bottom: -10,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque, // Wichtig: Events nicht durchlassen
                            onPanStart: (details) {
                              setState(() {
                                model.isResizing = true;
                                model.isBeingDragged = false;
                                _currentDragWidget = null; // Explizit Drag abbrechen
                                _resizeStartPosition = details.globalPosition;
                                _originalWidgetSize = model.size;
                                _currentResizeWidget = model;
                                _setWidgetBeingTouched(true); // Scrolling blockieren beim Resize
                              });
                              HapticFeedback.selectionClick();
                            },
                            onPanUpdate: (details) {
                              if (_currentResizeWidget == model) {
                                _handleWidgetResize(model, details, tabIndex);
                              }
                            },
                            onPanEnd: (_) {
                              setState(() {
                                model.isResizing = false;
                                _resizeStartPosition = null;
                                _originalWidgetSize = null;
                                _currentResizeWidget = null;
                                _setWidgetBeingTouched(false); // Scrolling wieder erlauben
                              });
                              HapticFeedback.mediumImpact();
                            },
                            child: Container(
                          width: 60, // Größerer Touch-Bereich
                          height: 60,
                          alignment: Alignment.bottomRight,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: model.isResizing ? 45 : 35,
                            height: model.isResizing ? 45 : 35,
                            margin: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: model.isResizing 
                                  ? CupertinoColors.activeBlue
                                  : CupertinoColors.activeBlue.withOpacity(0.3),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(model.isResizing ? 22 : 18),
                                bottomRight: Radius.circular(18),
                              ),
                              boxShadow: model.isResizing ? [
                                BoxShadow(
                                  color: CupertinoColors.activeBlue.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ] : null,
                            ),
                            child: Center(
                              child: Transform.rotate(
                                angle: model.isResizing ? math.pi / 4 : 0,
                                child: Icon(
                                  model.isResizing 
                                      ? CupertinoIcons.resize
                                      : CupertinoIcons.arrow_up_left_arrow_down_right,
                                  color: model.isResizing 
                                      ? CupertinoColors.white
                                      : CupertinoColors.activeBlue,
                                  size: model.isResizing ? 22 : 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                          ),
                        ),
                        
                        // Delete Button
                        Positioned(
                          right: 4,
                          top: 4,
                          child: GestureDetector(
                            onTap: () => _deleteWidget(tabIndex, widgetIndex),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemRed.withOpacity(0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: CupertinoColors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    ),
  );
}
  
  void _handleWidgetResize(AnalysisWidgetModel widget, DragUpdateDetails details, int tabIndex) {
    if (_resizeStartPosition == null || _originalWidgetSize == null) return;
    
    // Berechne die Drag-Distanz seit Start
    final dragDelta = details.globalPosition - _resizeStartPosition!;
    
    // Schwellenwerte für Größenänderung
    const gridStepThreshold = 40.0; // Pixel pro Grid-Schritt
    
    // Berechne gewünschte Breiten- und Höhenänderung basierend auf Drag-Richtung
    final widthSteps = (dragDelta.dx / gridStepThreshold).round();
    final heightSteps = (dragDelta.dy / gridStepThreshold).round();
    
    // Aktuelle Größe analysieren
    final currentWidth = widget.gridWidth;
    final currentHeight = widget.gridHeight;
    final originalWidth = _getWidgetWidth(_originalWidgetSize!);
    final originalHeight = _getWidgetHeight(_originalWidgetSize!);
    
    // Neue Breite und Höhe berechnen
    final newWidth = (originalWidth + widthSteps).clamp(1, 4);
    final newHeight = (originalHeight + heightSteps).clamp(1, 4);
    
    // Finde die beste passende Größe
    AnalysisWidgetSize? bestSize = _findBestSize(newWidth, newHeight);
    
    if (bestSize != null && bestSize != widget.size) {
      // Setze neue Größe temporär
      final originalSize = widget.size;
      widget.size = bestSize;
      
      // Prüfe ob die neue Größe gültig ist
      if (!WidgetGridManager.isValidPosition(openTabs[tabIndex].widgets, widget, widget.position!)) {
        // Zurücksetzen wenn nicht gültig
        widget.size = originalSize;
      } else {
        setState(() {});
        HapticFeedback.lightImpact();
      }
    }
  }
  
  int _getWidgetWidth(AnalysisWidgetSize size) {
    switch (size) {
      case AnalysisWidgetSize.smallSquare:
      case AnalysisWidgetSize.tallRectangle:
      case AnalysisWidgetSize.extraTall:
        return 1;
      case AnalysisWidgetSize.wideRectangle:
      case AnalysisWidgetSize.largeSquare:
        return 2;
      case AnalysisWidgetSize.extraWide:
      case AnalysisWidgetSize.huge:
        return 3;
      case AnalysisWidgetSize.giant:
      case AnalysisWidgetSize.massive:
      case AnalysisWidgetSize.fullWidth:
        return 4;
    }
  }
  
  int _getWidgetHeight(AnalysisWidgetSize size) {
    switch (size) {
      case AnalysisWidgetSize.smallSquare:
      case AnalysisWidgetSize.wideRectangle:
      case AnalysisWidgetSize.extraWide:
        return 1;
      case AnalysisWidgetSize.tallRectangle:
      case AnalysisWidgetSize.largeSquare:
      case AnalysisWidgetSize.huge:
      case AnalysisWidgetSize.giant:
        return 2;
      case AnalysisWidgetSize.extraTall:
      case AnalysisWidgetSize.massive:
        return 3;
      case AnalysisWidgetSize.fullWidth:
        return 4;
    }
  }
  
  AnalysisWidgetSize? _findBestSize(int targetWidth, int targetHeight) {
    // Finde die Größe, die am besten zu den Zielmaßen passt
    final sizes = [
      AnalysisWidgetSize.smallSquare,   // 1x1
      AnalysisWidgetSize.tallRectangle, // 1x2
      AnalysisWidgetSize.wideRectangle, // 2x1
      AnalysisWidgetSize.largeSquare,   // 2x2
      AnalysisWidgetSize.extraWide,     // 3x1
      AnalysisWidgetSize.extraTall,     // 1x3
      AnalysisWidgetSize.huge,          // 3x2
      AnalysisWidgetSize.giant,         // 4x2
      AnalysisWidgetSize.massive,       // 4x3
      AnalysisWidgetSize.fullWidth,     // 4x4
    ];
    
    for (var size in sizes) {
      if (_getWidgetWidth(size) == targetWidth && _getWidgetHeight(size) == targetHeight) {
        return size;
      }
    }
    
    // Wenn keine exakte Übereinstimmung, finde die nächstbeste
    AnalysisWidgetSize? closestSize;
    int minDifference = 999;
    
    for (var size in sizes) {
      final widthDiff = (_getWidgetWidth(size) - targetWidth).abs();
      final heightDiff = (_getWidgetHeight(size) - targetHeight).abs();
      final totalDiff = widthDiff + heightDiff;
      
      if (totalDiff < minDifference) {
        minDifference = totalDiff;
        closestSize = size;
      }
    }
    
    return closestSize;
  }
  
  // Hilfsvariablen für Resize
  Offset? _resizeStartPosition;
  AnalysisWidgetSize? _originalWidgetSize;
  AnalysisWidgetModel? _currentResizeWidget;
  
  // Hilfsvariablen für Drag
  Offset? _dragStartPosition;
  GridPosition? _dragStartGridPosition;
  AnalysisWidgetModel? _currentDragWidget;
  GridPosition? _dragPreviewPosition;
  bool _isWidgetBeingTouched = false;
  double _dragStartScrollOffset = 0.0;
  
  // Orientierungs-Management
  bool _isPortrait = true;
  Map<String, Map<String, dynamic>> _portraitWidgetStates = {};
  Map<String, Map<String, dynamic>> _landscapeWidgetStates = {};
  
  // ScrollController für Auto-Scroll beim Drag
  ScrollController _scrollController = ScrollController();
  ScrollController _horizontalScrollController = ScrollController();
  double? _lockedScrollPosition;
  double? _lockedHorizontalScrollPosition;
  Timer? _autoScrollTimer;
  
  // Grid-Zeilen Management
  int _currentGridRows = 10; // Start mit 10 Zeilen
  bool _maxRowsWarningShown = false; // Flag für die Warnung bei max Zeilen
  
  void _setWidgetBeingTouched(bool value) {
    if (_isWidgetBeingTouched != value) {
      _isWidgetBeingTouched = value;
      widget.onWidgetTouchChanged?.call(value);
      
      // Lock scroll positions when widget is touched
      if (value) {
        _lockedScrollPosition = _scrollController.hasClients ? _scrollController.offset : null;
        _lockedHorizontalScrollPosition = _horizontalScrollController.hasClients ? _horizontalScrollController.offset : null;
      } else {
        _lockedScrollPosition = null;
        _lockedHorizontalScrollPosition = null;
      }
    }
  }
  
  void _startAutoScroll(double dragPositionY, {double? dragPositionX}) {
    _autoScrollTimer?.cancel();

    final viewportHeight = MediaQuery.of(context).size.height;
    final viewportWidth = MediaQuery.of(context).size.width;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    const edgeThreshold = 100.0;
    const scrollSpeed = 15.0;

    double scrollDeltaY = 0.0;
    double scrollDeltaX = 0.0;

    if (isPortrait && _scrollController.hasClients) {
      if (dragPositionY < edgeThreshold) {
        scrollDeltaY = -scrollSpeed * (1 - dragPositionY / edgeThreshold);
      } else if (dragPositionY > viewportHeight - edgeThreshold) {
        scrollDeltaY = scrollSpeed * ((dragPositionY - (viewportHeight - edgeThreshold)) / edgeThreshold);
      }
    } else if (!isPortrait && _horizontalScrollController.hasClients && dragPositionX != null) {
      if (dragPositionX < edgeThreshold) {
        scrollDeltaX = -scrollSpeed * (1 - dragPositionX / edgeThreshold);
      } else if (dragPositionX > viewportWidth - edgeThreshold) {
        scrollDeltaX = scrollSpeed * ((dragPositionX - (viewportWidth - edgeThreshold)) / edgeThreshold);
      }
    }

    if (scrollDeltaY != 0.0 || scrollDeltaX != 0.0) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (_currentDragWidget == null) {
          timer.cancel();
          return;
        }
        if (isPortrait && _scrollController.hasClients) {
          final pos = _scrollController.position;
          _scrollController.jumpTo((_scrollController.offset + scrollDeltaY).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        } else if (!isPortrait && _horizontalScrollController.hasClients) {
          final pos = _horizontalScrollController.position;
          _horizontalScrollController.jumpTo((_horizontalScrollController.offset + scrollDeltaX).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        }
      });
    }
  }
  
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }
  
  void _handleOrientationChange(bool isPortrait, List<AnalysisWidgetModel> widgets, int tabIndex) {
    if (isPortrait) {
      // Wechsel zu Portrait: Speichere Landscape-Zustand und lade Portrait-Zustand
      _saveLandscapeState(widgets);
      _loadPortraitState(widgets);
    } else {
      // Wechsel zu Landscape: Speichere Portrait-Zustand und lade Landscape-Zustand
      _savePortraitState(widgets);
      _loadLandscapeState(widgets);
    }
  }
  
  void _savePortraitState(List<AnalysisWidgetModel> widgets) {
    _portraitWidgetStates.clear();
    for (var widget in widgets) {
      _portraitWidgetStates[widget.id] = {
        'position': widget.position?.toJson(),
        'size': widget.size.index,
      };
    }
  }
  
  void _saveLandscapeState(List<AnalysisWidgetModel> widgets) {
    _landscapeWidgetStates.clear();
    for (var widget in widgets) {
      _landscapeWidgetStates[widget.id] = {
        'position': widget.position?.toJson(),
        'size': widget.size.index,
      };
    }
  }
  
  void _loadPortraitState(List<AnalysisWidgetModel> widgets) {
    final gridColumns = WidgetGridManager.getResponsiveGridColumns(context);
    
    for (var widget in widgets) {
      final state = _portraitWidgetStates[widget.id];
      if (state != null) {
        // Wiederherstellen der gespeicherten Position und Größe
        if (state['position'] != null) {
          widget.position = GridPosition.fromJson(state['position']);
        }
        widget.size = AnalysisWidgetSize.values[state['size']];
      } else {
        // Wenn kein gespeicherter Zustand, passe Widget an Portrait an
        _adjustWidgetForPortrait(widget, gridColumns);
      }
    }
    
    // Reorganisiere Widgets falls nötig
    _reorganizeWidgetsForGrid(widgets, gridColumns);
  }
  
  void _loadLandscapeState(List<AnalysisWidgetModel> widgets) {
    for (var widget in widgets) {
      final state = _landscapeWidgetStates[widget.id];
      if (state != null) {
        // Wiederherstellen der gespeicherten Position und Größe
        if (state['position'] != null) {
          widget.position = GridPosition.fromJson(state['position']);
        }
        widget.size = AnalysisWidgetSize.values[state['size']];
      }
    }
  }
  
  void _adjustWidgetForPortrait(AnalysisWidgetModel widget, int gridColumns) {
    // Passe Widget-Größe an, wenn es zu breit für Portrait ist
    if (widget.gridWidth > gridColumns) {
      // Verkleinere das Widget
      switch (widget.size) {
        case AnalysisWidgetSize.giant:
        case AnalysisWidgetSize.massive:
        case AnalysisWidgetSize.fullWidth:
          widget.size = AnalysisWidgetSize.largeSquare;
          break;
        case AnalysisWidgetSize.extraWide:
        case AnalysisWidgetSize.huge:
          widget.size = AnalysisWidgetSize.wideRectangle;
          break;
        default:
          // Andere Größen sind okay
          break;
      }
    }
  }
  
  void _reorganizeWidgetsForGrid(List<AnalysisWidgetModel> widgets, int gridColumns) {
    // Sortiere Widgets nach Position
    widgets.sort((a, b) {
      if (a.position == null || b.position == null) return 0;
      final posA = a.position!.y * 100 + a.position!.x;
      final posB = b.position!.y * 100 + b.position!.x;
      return posA.compareTo(posB);
    });
    
    // Reorganisiere Widgets, die außerhalb des Grids sind
    for (var widget in widgets) {
      if (widget.position != null && widget.position!.x + widget.gridWidth > gridColumns) {
        // Widget passt nicht, finde neue Position
        widget.position = _findNewPositionForWidget(widget, widgets, gridColumns);
      }
    }
  }
  
  GridPosition? _findNewPositionForWidget(AnalysisWidgetModel widget, List<AnalysisWidgetModel> allWidgets, int gridColumns) {
    // Erstelle Belegungsmatrix
    var occupiedCells = <String>{};
    
    for (var w in allWidgets) {
      if (w != widget && w.position != null) {
        for (int x = w.position!.x; x < w.position!.x + w.gridWidth && x < gridColumns; x++) {
          for (int y = w.position!.y; y < w.position!.y + w.gridHeight; y++) {
            occupiedCells.add('$x,$y');
          }
        }
      }
    }
    
    // Suche freie Position
    for (int y = 0; y < 100; y++) {
      for (int x = 0; x <= gridColumns - widget.gridWidth; x++) {
        bool canPlace = true;
        for (int dx = 0; dx < widget.gridWidth; dx++) {
          for (int dy = 0; dy < widget.gridHeight; dy++) {
            if (occupiedCells.contains('${x + dx},${y + dy}')) {
              canPlace = false;
              break;
            }
          }
          if (!canPlace) break;
        }
        if (canPlace) {
          return GridPosition(x: x, y: y);
        }
      }
    }
    
    return GridPosition(x: 0, y: 0);
  }
  
  String _getSizeLabel(AnalysisWidgetSize size) {
    switch (size) {
      case AnalysisWidgetSize.smallSquare:
        return '1×1';
      case AnalysisWidgetSize.tallRectangle:
        return '1×2';
      case AnalysisWidgetSize.wideRectangle:
        return '2×1';
      case AnalysisWidgetSize.largeSquare:
        return '2×2';
      case AnalysisWidgetSize.extraWide:
        return '3×1';
      case AnalysisWidgetSize.extraTall:
        return '1×3';
      case AnalysisWidgetSize.huge:
        return '3×2';
      case AnalysisWidgetSize.giant:
        return '4×2';
      case AnalysisWidgetSize.massive:
        return '4×3';
      case AnalysisWidgetSize.fullWidth:
        return '4×4';
    }
  }
  
  Widget _buildScaledWidgetContent({
    required AnalysisWidgetModel model,
    required List<SensorReading> data,
    required BoxConstraints constraints,
  }) {
    // Skaliere Content basierend auf verfügbarem Platz
    final isSmallWidget = model.gridWidth == 1 || model.gridHeight == 1;
    
    if (model is ChartWidgetModel) {
      return _buildChartContent(model, data, isSmallWidget);
    } else if (model is StatisticsWidgetModel) {
      return _buildStatisticsContent(model, data, isSmallWidget);
    } else if (model is FrequencyWidgetModel) {
      return _buildFrequencyContent(model, isSmallWidget);
    } else if (model is DutyCycleWidgetModel) {
      return _buildDutyCycleContent(model, isSmallWidget);
    }
    
    return Container();
  }
  
  Widget _buildChartContent(ChartWidgetModel model, List<SensorReading> data, bool isSmall) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'Keine Daten',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: isSmall ? 10 : 12,
          ),
        ),
      );
    }
    
    // Verwende die letzten Datenpunkte
    final displayRange = model.displayRange;
    final now = DateTime.now();
    final startTime = now.subtract(Duration(seconds: displayRange));
    
    // Filtere Daten basierend auf Zeitfenster
    final recentData = data.where((reading) => 
      reading.timestamp.isAfter(startTime)
    ).toList();
    
    if (recentData.isEmpty) {
      return Center(
        child: Text(
          'Keine aktuellen Daten',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: isSmall ? 10 : 12,
          ),
        ),
      );
    }
    
    // Konvertiere zu Zeitbasiertem Chart
    final spots = recentData.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(), // Index als X
        entry.value.y,        // Y-Wert des Sensors
      );
    }).toList();
    
    // Berechne Min/Max für beide Achsen
    final xSensorValues = recentData.map((r) => r.x).toList();
    final ySensorValues = recentData.map((r) => r.y).toList();
    
    final allValues = [...xSensorValues, ...ySensorValues];
    final minValue = allValues.isNotEmpty ? allValues.reduce(math.min) : 0;
    final maxValue = allValues.isNotEmpty ? allValues.reduce(math.max) : 100;
    final padding = (maxValue - minValue) * 0.1;
    
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: recentData.length.toDouble() - 1,
        minY: minValue - padding,
        maxY: maxValue + padding,
        gridData: FlGridData(
          show: model.showGrid,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: (maxValue - minValue) / 5,
          verticalInterval: recentData.length > 5 ? recentData.length / 5 : 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: CupertinoColors.systemGrey4.withOpacity(0.3),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: CupertinoColors.systemGrey4.withOpacity(0.3),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: !isSmall,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !isSmall,
              reservedSize: 40,
              interval: (maxValue - minValue) / 4,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: CupertinoColors.systemGrey,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: !isSmall,
              reservedSize: 30,
              interval: recentData.length > 4 ? recentData.length / 4 : 1,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: CupertinoColors.systemGrey4.withOpacity(0.5),
            width: 1,
          ),
        ),
        lineBarsData: [
          // X-Achse Daten (rot)
          LineChartBarData(
            spots: spots.map((spot) => FlSpot(
              spot.x,
              recentData[spot.x.toInt()].x.toDouble(),
            )).toList(),
            isCurved: true,
            color: CupertinoColors.systemRed,
            barWidth: isSmall ? 1.5 : 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
          // Y-Achse Daten (blau)
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: CupertinoColors.activeBlue,
            barWidth: isSmall ? 1.5 : 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: !isSmall,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index >= 0 && index < recentData.length) {
                  final reading = recentData[index];
                  final isXLine = spot.barIndex == 0;
                  return LineTooltipItem(
                    '${isXLine ? "X" : "Y"}: ${spot.y.toStringAsFixed(2)}',
                    TextStyle(
                      color: isXLine ? CupertinoColors.systemRed : CupertinoColors.activeBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }
                return null;
              }).whereType<LineTooltipItem>().toList();
            },
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsContent(StatisticsWidgetModel model, List<SensorReading> data, bool isSmall) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'Keine Daten',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: isSmall ? 10 : 12,
          ),
        ),
      );
    }
    
    final xValues = data.map((r) => r.x).toList();
    final yValues = data.map((r) => r.y).toList();
    
    final stats = {
      'Min X': xValues.reduce(math.min).toStringAsFixed(2),
      'Max X': xValues.reduce(math.max).toStringAsFixed(2),
      'Min Y': yValues.reduce(math.min).toStringAsFixed(2),
      'Max Y': yValues.reduce(math.max).toStringAsFixed(2),
    };
    
    return Padding(
      padding: EdgeInsets.all(isSmall ? 4 : 8),
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: isSmall ? 2 : 1.5,
        crossAxisSpacing: isSmall ? 4 : 8,
        mainAxisSpacing: isSmall ? 4 : 8,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        children: stats.entries.map((entry) {
          return Container(
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey6.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(isSmall ? 4 : 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: isSmall ? 8 : 10,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                  SizedBox(height: isSmall ? 2 : 4),
                  Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: isSmall ? 12 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildFrequencyContent(FrequencyWidgetModel model, bool isSmall) {
    return Padding(
      padding: EdgeInsets.all(isSmall ? 4 : 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (model.showBleFreq) _buildFrequencyItem('BLE', bleFrequency, isSmall),
          if (model.showLoopFreq) _buildFrequencyItem('Loop', loopFrequency, isSmall),
        ],
      ),
    );
  }
  
  Widget _buildFrequencyItem(String label, double frequency, bool isSmall) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmall ? 10 : 12,
            color: CupertinoColors.systemGrey,
          ),
        ),
        SizedBox(height: isSmall ? 2 : 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${frequency.toStringAsFixed(1)} Hz',
            style: TextStyle(
              fontSize: isSmall ? 16 : 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildDutyCycleContent(DutyCycleWidgetModel model, bool isSmall) {
    return Padding(
      padding: EdgeInsets.all(isSmall ? 4 : 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (model.showDuty1) _buildDutyCycleItem('PWM 1', lastDuty1, isSmall),
          if (model.showDuty2) _buildDutyCycleItem('PWM 2', lastDuty2, isSmall),
        ],
      ),
    );
  }
  
  Widget _buildDutyCycleItem(String label, int duty, bool isSmall) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmall ? 10 : 12,
            color: CupertinoColors.systemGrey,
          ),
        ),
        SizedBox(height: isSmall ? 2 : 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$duty%',
            style: TextStyle(
              fontSize: isSmall ? 16 : 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
  
  
  Widget _buildAnalysisWidget({
    required Key key,
    required AnalysisWidgetModel model,
    required int tabIndex,
    required int widgetIndex,
    required List<SensorReading> data,
    required bool isEditMode,
  }) {
    final activeTab = openTabs[tabIndex];
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemGrey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Widget Content
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Widget Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        model.title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.08,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ),
                    if (!isEditMode && model.type == 'chart')
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 28,
                        onPressed: () => _showWidgetSettings(tabIndex, widgetIndex),
                        child: Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 20,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Widget Content basierend auf Typ
                _buildWidgetContent(model, data),
              ],
            ),
          ),
          
          // Edit Mode Overlay
          if (isEditMode) ...[
            // Drag Handle
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.drag_handle,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            
            // Delete Button
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => _deleteWidget(tabIndex, widgetIndex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWidgetContent(AnalysisWidgetModel model, List<SensorReading> data) {
    switch (model.type) {
      case 'chart':
        final chartModel = model as ChartWidgetModel;
        final homeState = context.findAncestorStateOfType<_HomePageState>();
        
        // Finde den aktuellen Tab-Index und überprüfe ob es ein Live-Tab ist
        int? currentTabIndex;
        bool isLiveTab = false;
        
        // Suche nach dem Tab-Index über den Build-Context
        for (int i = 0; i < openTabs.length; i++) {
          if (openTabs[i].widgets.contains(model)) {
            currentTabIndex = i;
            isLiveTab = openTabs[i].isLive;
            break;
          }
        }
        
        return Column(
          children: [
            // Zeitkontrollen und Play-Button (nur bei Live-Tabs und wenn aktiviert)
            if (chartModel.showTimeControls && isLiveTab) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Zeitfenster-Auswahl
                    homeState?._buildTimeWindowSelector() 
                      ?? const Text('Zeitfenster'),
                    
                    // Play/Pause Button
                    IconButton(
                      icon: Icon(
                        widget.isRecording ? Icons.pause : Icons.play_arrow,
                        size: 28,
                      ),
                      onPressed: () => widget.onRecordingChanged(!widget.isRecording),
                      color: widget.isRecording ? Colors.orange : Colors.green,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            
            // Chart
            SizedBox(
              height: chartModel.showTimeControls && isLiveTab ? 200 : 250,
              child: homeState?._buildDualAxisChart(
                data: data,
              ) ?? const Center(child: Text('Chart nicht verfügbar')),
            ),
          ],
        );
        
      case 'statistics':
        final statsModel = model as StatisticsWidgetModel;
        final stats = _calculateStatistics(data);
        return Column(
          children: [
            if (statsModel.showXAxis) ...[
              Text(
                'X-ACHSE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  letterSpacing: 0.06,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (statsModel.selectedStats.contains('min'))
                      Expanded(child: _buildIOSStatCard('MIN', stats['xMin'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if (statsModel.selectedStats.contains('min') && statsModel.selectedStats.contains('max'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('max'))
                      Expanded(child: _buildIOSStatCard('MAX', stats['xMax'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if ((statsModel.selectedStats.contains('min') || statsModel.selectedStats.contains('max')) && statsModel.selectedStats.contains('avg'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('avg'))
                      Expanded(child: _buildIOSStatCard('AVG', stats['xAvg'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if (statsModel.selectedStats.contains('avg') && statsModel.selectedStats.contains('stdDev'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('stdDev'))
                      Expanded(child: _buildIOSStatCard('σ', stats['xStdDev'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                  ],
                ),
              ),
            ],
            if (statsModel.showXAxis && statsModel.showYAxis) const SizedBox(height: 16),
            if (statsModel.showYAxis) ...[
              Text(
                'Y-ACHSE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  letterSpacing: 0.06,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (statsModel.selectedStats.contains('min'))
                      Expanded(child: _buildIOSStatCard('MIN', stats['yMin'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if (statsModel.selectedStats.contains('min') && statsModel.selectedStats.contains('max'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('max'))
                      Expanded(child: _buildIOSStatCard('MAX', stats['yMax'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if ((statsModel.selectedStats.contains('min') || statsModel.selectedStats.contains('max')) && statsModel.selectedStats.contains('avg'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('avg'))
                      Expanded(child: _buildIOSStatCard('AVG', stats['yAvg'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                    if (statsModel.selectedStats.contains('avg') && statsModel.selectedStats.contains('stdDev'))
                      const SizedBox(width: 12),
                    if (statsModel.selectedStats.contains('stdDev'))
                      Expanded(child: _buildIOSStatCard('σ', stats['yStdDev'].toStringAsFixed(2), 'mT', CupertinoColors.label)),
                  ],
                ),
              ),
            ],
          ],
        );
        
      case 'frequency':
        final freqModel = model as FrequencyWidgetModel;
        final homePageState = context.findAncestorStateOfType<_HomePageState>();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (freqModel.showLoopFreq)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildFrequencyCard(
                    'Regelkreis',
                    '${homePageState?.loopFrequency.toStringAsFixed(1) ?? '0.0'} Hz',
                    CupertinoColors.label.resolveFrom(context),
                    CupertinoIcons.arrow_2_circlepath,
                  ),
                ),
              ),
            if (freqModel.showLoopFreq && freqModel.showBleFreq)
              const SizedBox(width: 8),
            if (freqModel.showBleFreq)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildFrequencyCard(
                    'BLE-Datenrate',
                    '${homePageState?.bleFrequency.toStringAsFixed(0) ?? '0'} Hz',
                    CupertinoColors.label.resolveFrom(context),
                    CupertinoIcons.antenna_radiowaves_left_right,
                  ),
                ),
              ),
          ],
        );
        
      case 'duty_cycle':
        final dutyModel = model as DutyCycleWidgetModel;
        final homePageState = context.findAncestorStateOfType<_HomePageState>();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (dutyModel.showDuty1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildDutyCard('Duty 1', homePageState?.duty1 ?? 0, CupertinoColors.label.resolveFrom(context), dutyModel.showAsGauge),
                  ),
                ),
              if (dutyModel.showDuty1 && dutyModel.showDuty2)
                const SizedBox(width: 8),
              if (dutyModel.showDuty2)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildDutyCard('Duty 2', homePageState?.duty2 ?? 0, CupertinoColors.label.resolveFrom(context), dutyModel.showAsGauge),
                  ),
                ),
            ],
          ),
        );
        
      default:
        return const Center(child: Text('Unbekannter Widget-Typ'));
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIOSStatCard(String label, String value, String unit, Color color) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIOSWidgetOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    iconColor.withOpacity(0.2),
                    iconColor.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: CupertinoColors.label,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5.resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: CupertinoColors.systemGrey.resolveFrom(context), size: 20),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                color: CupertinoColors.label.resolveFrom(context),
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDutyCard(String title, int value, Color color, bool showAsGauge) {
    if (showAsGauge) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: value / 1023,
                      strokeWidth: 12,
                      backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground.resolveFrom(context),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.systemGrey4.resolveFrom(context).withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          value.toString(),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.label.resolveFrom(context),
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          'PWM',
                          style: TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 36,
                    color: CupertinoColors.label.resolveFrom(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'PWM',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  void _showAddWidgetDialog(int tabIndex) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Handle Bar
                Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey3.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'WIDGET HINZUFÜGEN',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.08,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey5.resolveFrom(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 16,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Widget Options
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground.resolveFrom(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          _buildIOSWidgetOption(
                            icon: CupertinoIcons.chart_bar_square,
                            iconColor: CupertinoColors.systemGrey,
                            title: 'Sensor-Diagramm',
                            subtitle: 'Live X/Y Datenvisualisierung',
                            onTap: () {
                              Navigator.pop(context);
                              _showWidgetSizeSelector(
                                tabIndex: tabIndex,
                                widgetType: 'chart',
                                title: 'Sensor-Diagramm',
                              );
                            },
                          ),
                          _buildIOSWidgetOption(
                            icon: CupertinoIcons.chart_bar_alt_fill,
                            iconColor: CupertinoColors.systemGrey2,
                            title: 'Statistiken',
                            subtitle: 'Min, Max, Avg, Standardabweichung',
                            onTap: () {
                              Navigator.pop(context);
                              _showWidgetSizeSelector(
                                tabIndex: tabIndex,
                                widgetType: 'statistics',
                                title: 'Statistiken',
                              );
                            },
                          ),
                          _buildIOSWidgetOption(
                            icon: CupertinoIcons.speedometer,
                            iconColor: CupertinoColors.systemGrey,
                            title: 'Frequenz-Anzeige',
                            subtitle: 'BLE & Regelkreis-Frequenzen',
                            onTap: () {
                              Navigator.pop(context);
                              _showWidgetSizeSelector(
                                tabIndex: tabIndex,
                                widgetType: 'frequency',
                                title: 'Frequenzen',
                              );
                            },
                          ),
                          _buildIOSWidgetOption(
                            icon: CupertinoIcons.gauge,
                            iconColor: CupertinoColors.systemGrey2,
                            title: 'Duty Cycles',
                            subtitle: 'PWM Ausgangsleistung',
                            onTap: () {
                              Navigator.pop(context);
                              _showWidgetSizeSelector(
                                tabIndex: tabIndex,
                                widgetType: 'duty_cycle',
                                title: 'Duty Cycles',
                              );
                            },
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
      },
    );
  }

  void _showWidgetSizeSelector({
    required int tabIndex,
    required String widgetType,
    required String title,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Handle Bar
                Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey3.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'GRÖßE WÄHLEN',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.08,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Size Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children: [
                        _buildSizeOption(
                          size: AnalysisWidgetSize.smallSquare,
                          label: '1x1',
                          icon: Icons.crop_square,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.smallSquare),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.wideRectangle,
                          label: '2x1',
                          icon: Icons.crop_16_9,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.wideRectangle),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.extraWide,
                          label: '3x1',
                          icon: Icons.panorama_wide_angle,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.extraWide),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.tallRectangle,
                          label: '1x2',
                          icon: Icons.crop_portrait,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.tallRectangle),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.largeSquare,
                          label: '2x2',
                          icon: Icons.crop_din,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.largeSquare),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.huge,
                          label: '3x2',
                          icon: Icons.aspect_ratio,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.huge),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.extraTall,
                          label: '1x3',
                          icon: Icons.stay_primary_portrait,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.extraTall),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.giant,
                          label: '4x2',
                          icon: Icons.panorama_horizontal,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.giant),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.massive,
                          label: '4x3',
                          icon: Icons.grid_on,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.massive),
                        ),
                        _buildSizeOption(
                          size: AnalysisWidgetSize.fullWidth,
                          label: '4x4',
                          icon: Icons.fullscreen,
                          onTap: () => _createWidget(context, tabIndex, widgetType, title, AnalysisWidgetSize.fullWidth),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildSizeOption({
    required AnalysisWidgetSize size,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: CupertinoColors.systemGrey4.resolveFrom(context),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _createWidget(BuildContext context, int tabIndex, String widgetType, String title, AnalysisWidgetSize size) {
    Navigator.pop(context);
    
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    AnalysisWidgetModel widget;
    
    switch (widgetType) {
      case 'chart':
        widget = ChartWidgetModel(
          id: id,
          title: title,
          size: size,
        );
        break;
      case 'statistics':
        widget = StatisticsWidgetModel(
          id: id,
          title: title,
          size: size,
        );
        break;
      case 'frequency':
        widget = FrequencyWidgetModel(
          id: id,
          title: title,
          size: size,
        );
        break;
      case 'duty_cycle':
        widget = DutyCycleWidgetModel(
          id: id,
          title: title,
          size: size,
        );
        break;
      default:
        return;
    }
    
    _addWidget(tabIndex, widget);
  }
  
  void _addWidget(int tabIndex, AnalysisWidgetModel widget) {
    setState(() {
      // Finde eine freie Position für das neue Widget
      widget.position = WidgetGridManager.findFreePosition(openTabs[tabIndex].widgets, widget);
      openTabs[tabIndex].widgets.add(widget);
    });
  }

  void _deleteWidget(int tabIndex, int widgetIndex) {
    setState(() {
      openTabs[tabIndex].widgets.removeAt(widgetIndex);
    });
  }

  void _showWidgetSettings(int tabIndex, int widgetIndex) {
    final widget = openTabs[tabIndex].widgets[widgetIndex];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F2F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Column(
                children: [
                  // Handle Bar
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  
                  // Title
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${widget.title} - Einstellungen',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  // Settings Content
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: _buildWidgetSettingsContent(widget, tabIndex, widgetIndex, setModalState),
                    ),
                  ),
                  
                  // Close Button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Fertig',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildWidgetSettingsContent(AnalysisWidgetModel widget, int tabIndex, int widgetIndex, StateSetter setModalState) {
    switch (widget.type) {
      case 'chart':
        final chartModel = widget as ChartWidgetModel;
        return ListView(
          children: [
            // Zeitkontrollen-Toggle (nur für Live-Tabs)
            if (openTabs[tabIndex].isLive) ...[
              ListTile(
                title: const Text('Zeitkontrollen anzeigen'),
                subtitle: const Text('Play/Pause und Zeitfenster im Widget'),
                trailing: Switch(
                  value: chartModel.showTimeControls,
                  onChanged: (value) {
                    setState(() {
                      openTabs[tabIndex].widgets[widgetIndex] = ChartWidgetModel(
                        id: chartModel.id,
                        title: chartModel.title,
                        showGrid: chartModel.showGrid,
                        showLegend: chartModel.showLegend,
                        displayRange: chartModel.displayRange,
                        showTimeControls: value,
                      );
                    });
                    setModalState(() {});
                  },
                ),
              ),
              const Divider(),
            ],
            
            ListTile(
              title: const Text('Gitter anzeigen'),
              trailing: Switch(
                value: chartModel.showGrid,
                onChanged: (value) {
                  setState(() {
                    openTabs[tabIndex].widgets[widgetIndex] = ChartWidgetModel(
                      id: chartModel.id,
                      title: chartModel.title,
                      showGrid: value,
                      showLegend: chartModel.showLegend,
                      displayRange: chartModel.displayRange,
                      showTimeControls: chartModel.showTimeControls,
                    );
                  });
                  setModalState(() {});
                },
              ),
            ),
            const Divider(),
            
            ListTile(
              title: const Text('Legende anzeigen'),
              trailing: Switch(
                value: chartModel.showLegend,
                onChanged: (value) {
                  setState(() {
                    openTabs[tabIndex].widgets[widgetIndex] = ChartWidgetModel(
                      id: chartModel.id,
                      title: chartModel.title,
                      showGrid: chartModel.showGrid,
                      showLegend: value,
                      displayRange: chartModel.displayRange,
                      showTimeControls: chartModel.showTimeControls,
                    );
                  });
                  setModalState(() {});
                },
              ),
            ),
          ],
        );
        
      case 'statistics':
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Statistik-Einstellungen kommen bald...'),
          ),
        );
        
      case 'frequency':
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Frequenz-Einstellungen kommen bald...'),
          ),
        );
        
      case 'dutyCycle':
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Duty Cycle-Einstellungen kommen bald...'),
          ),
        );
        
      default:
        return const Center(
          child: Text('Unbekannter Widget-Typ'),
        );
    }
  }
  
  void _showEditWorkspaceScreen() async {
    final activeTab = openTabs[activeTabIndex];
    
    final List<AnalysisWidgetModel>? updatedWidgets = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditWorkspaceScreen(
          activeWidgets: List.from(activeTab.widgets),
          availableWidgets: _getAvailableWidgets(),
        ),
      ),
    );

    if (updatedWidgets != null) {
      setState(() {
        openTabs[activeTabIndex].widgets.clear();
        openTabs[activeTabIndex].widgets.addAll(updatedWidgets);
      });
    }
  }
  
  List<AnalysisWidgetModel> _getAvailableWidgets() {
    // Alle verfügbaren Widget-Typen
    return [
      ChartWidgetModel(
        id: 'chart_template',
        title: 'Sensor-Diagramm',
      ),
      StatisticsWidgetModel(
        id: 'stats_template',
        title: 'Statistiken',
      ),
      FrequencyWidgetModel(
        id: 'freq_template',
        title: 'Frequenzen',
      ),
      DutyCycleWidgetModel(
        id: 'duty_template',
        title: 'Duty Cycles',
      ),
    ];
  }
}

// iOS-Style Edit Workspace Screen
class EditWorkspaceScreen extends StatefulWidget {
  final List<AnalysisWidgetModel> activeWidgets;
  final List<AnalysisWidgetModel> availableWidgets;
  
  const EditWorkspaceScreen({
    Key? key,
    required this.activeWidgets,
    required this.availableWidgets,
  }) : super(key: key);
  
  @override
  State<EditWorkspaceScreen> createState() => _EditWorkspaceScreenState();
}

class _EditWorkspaceScreenState extends State<EditWorkspaceScreen> {
  late List<AnalysisWidgetModel> activeWidgets;
  late List<AnalysisWidgetModel> availableWidgets;
  
  @override
  void initState() {
    super.initState();
    activeWidgets = List.from(widget.activeWidgets);
    availableWidgets = List.from(widget.availableWidgets);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Abbrechen',
            style: TextStyle(fontSize: 16),
          ),
        ),
        leadingWidth: 100,
        title: const Text(
          'Widgets bearbeiten',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, activeWidgets),
            child: const Text(
              'Fertig',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Aktive Widgets
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Aktive Widgets',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (activeWidgets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                      child: Center(
                        child: Text(
                          'Keine aktiven Widgets',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activeWidgets.length,
                      itemBuilder: (context, index) {
                        final widget = activeWidgets[index];
                        return ListTile(
                          key: ValueKey(widget.id),
                          leading: GestureDetector(
                            onTap: () => _removeWidget(index),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.remove,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          title: Text(widget.title),
                          trailing: const Icon(
                            Icons.drag_handle,
                            color: Colors.grey,
                          ),
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final item = activeWidgets.removeAt(oldIndex);
                          activeWidgets.insert(newIndex, item);
                        });
                      },
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Verfügbare Widgets
            Expanded(
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Weitere Widgets',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: availableWidgets.length,
                        itemBuilder: (context, index) {
                          final widget = availableWidgets[index];
                          return ListTile(
                            leading: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            title: Text(widget.title),
                            subtitle: Text(_getWidgetDescription(widget.type)),
                            onTap: () => _addWidget(widget),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getWidgetDescription(String type) {
    switch (type) {
      case 'chart':
        return 'Live-Anzeige der X/Y Sensordaten';
      case 'statistics':
        return 'Min, Max, Durchschnitt der Messwerte';
      case 'frequency':
        return 'Regelkreis- und BLE-Frequenz';
      case 'duty_cycle':
        return 'PWM Duty Cycle Werte';
      default:
        return '';
    }
  }
  
  void _addWidget(AnalysisWidgetModel template) {
    setState(() {
      // Erstelle eine neue Instanz mit eindeutiger ID
      AnalysisWidgetModel newWidget;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      switch (template.type) {
        case 'chart':
          newWidget = ChartWidgetModel(id: id, title: template.title);
          break;
        case 'statistics':
          newWidget = StatisticsWidgetModel(id: id, title: template.title);
          break;
        case 'frequency':
          newWidget = FrequencyWidgetModel(id: id, title: template.title);
          break;
        case 'duty_cycle':
          newWidget = DutyCycleWidgetModel(id: id, title: template.title);
          break;
        default:
          return;
      }
      
      activeWidgets.add(newWidget);
    });
  }
  
  void _removeWidget(int index) {
    setState(() {
      activeWidgets.removeAt(index);
    });
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? pidCommandChar;
  BluetoothCharacteristic? statusDataChar;
  BluetoothCharacteristic? calibrationChar;
  StreamSubscription? scanSubscription;
  StreamSubscription? connectionSubscription;
  StreamSubscription? statusSubscription;
  StreamSubscription? calibrationSubscription;
  StreamSubscription? adapterSubscription;

  bool isScanning = false;
  bool isConnecting = false;
  String connectionStatus = "Getrennt";

  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;

  // PID-Parameter - ERWEITERT FÜR 4 QUADRANTEN
  // X-Achse
  double kpX_pos = 40.0, kiX_pos = 0.0, kdX_pos = 0.3;
  double kpX_neg = 40.0, kiX_neg = 0.0, kdX_neg = 0.3;
  // Y-Achse
  double kpY_pos = 40.0, kiY_pos = 0.0, kdY_pos = 0.3;
  double kpY_neg = 40.0, kiY_neg = 0.0, kdY_neg = 0.3;
  double dFilterTimeConstantS = 0.005; // NEUE ZEILE HINZUGEFÜGT
  double dTermCutoffHz = 0.0; // NEUE ZUSTANDSVARIABLE HINZUFÜGEN

  // Status-Daten
  double sensorX = 0.0;
  double sensorY = 0.0;
  int duty1 = 0;
  int duty2 = 0;
  double loopFrequency = 0.0;
  int currentFilter = 0;
  bool? isCalibrated;
  double bleFrequency = 0.0; // Neue Variable für BLE-Datenrate

  // Kalibrierungs-Status
  bool isCalibrating = false;
  int calibrationStep = 0;
  int calibrationTotalSteps = 6;
  CalibrationData? currentCalibrationData;

  // NEU: Kalibrierungskurven-Daten
  CalibrationCurves calibrationCurves = CalibrationCurves();
  bool isLoadingCalibCurves = false;
  
  // Erweiterte Kalibrierungs-Download-Verwaltung
  CalibUiState calibUiState = CalibUiState.idle;
  double calibDownloadProgress = 0.0;
  int calibDownloadChunksReceived = 0;
  
  // Mix-Matrix Auswahl-State
  String selectedMixAxis = 'X';
  String selectedMixQuadrant = 'PP';
  int calibDownloadTotalChunks = 0;
  Map<String, List<CalibrationPoint>> downloadedCurves = {};
  Map<String, List<List<double>>> downloadedMixGrids = {};
  Map<String, dynamic> downloadMetadata = {}; // Store metadata from download_start

  // NEU: Live-Kalibrierungsdaten
  LiveCalibrationData liveCalibrationData = LiveCalibrationData();
  bool showLiveCalibration = false;

  // Firmware Version
  String espFirmwareVersion = "";

  // Text Controller für direkte Eingabe - ERWEITERT FÜR 4 QUADRANTEN
  late TextEditingController kpXPosController, kiXPosController, kdXPosController;
  late TextEditingController kpXNegController, kiXNegController, kdXNegController;
  late TextEditingController kpYPosController, kiYPosController, kdYPosController;
  late TextEditingController kpYNegController, kiYNegController, kdYNegController;
  late TextEditingController dFilterTimeConstantController; // NEUE ZEILE HINZUGEFÜGT

  Timer? _debounceTimer;
  Timer? _autoScanTimer;

  // Tab Controller
  late TabController _tabController;

  // Sensor-Datenerfassung
  final List<SensorReading> sensorHistory = [];
  final int maxHistoryLength = 5000;  // Erhöht auf 5000 für längere Historie
  int _displayHistoryLength = 500;     // Anzahl der angezeigten Datenpunkte
  bool isRecording = true;
  
  // UI Update Timer
  Timer? _uiUpdateTimer;

  // Statistiken
  double xMin = 0, xMax = 0, xAvg = 0, xStdDev = 0;
  double yMin = 0, yMax = 0, yAvg = 0, yStdDev = 0;
  double noiseX = 0, noiseY = 0;

  // Frequenzanalyse
  double dominantFreqX = 0, dominantFreqY = 0;

  // Stream Controller für Kalibrierungs-Updates
  final StreamController<CalibrationUpdate> _calibrationStreamController = StreamController<CalibrationUpdate>.broadcast();
  
  // Cockpit-Panel für Analyse-View
  bool _showCockpitPanel = false;

  // NEU: Status-Panel einklappen
  bool isStatusPanelExpanded = false;
  
  // NEU: Zustand für die schwimmende Navigationsleiste
  bool _isNavExpanded = true;
  
  // NEU: Zustand für Widget-Touch in Analysis Tab
  bool _isAnalysisWidgetBeingTouched = false;
  
  // Draggable FAB State
  Offset _fabPosition = const Offset(20, 20); // Position from bottom-right
  bool _isDragging = false;
  bool _isDockedLeft = false;
  bool _isDockedRight = false;
  bool _isDockAnimating = false;
  double _dockProgress = 0.0;
  
  // Pre-built widgets for performance
  static const _expandMoreIcon = Icon(
    Icons.expand_more,
    color: Colors.white70,
    size: 20,
  );
  
  static const _appsIcon = Icon(
    Icons.apps,
    color: Colors.white,
    size: 24,
  );

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    // Listener für Tab-Änderungen hinzufügen mit sofortiger Reaktion
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    // Text Controller initialisieren - ERWEITERT FÜR 4 QUADRANTEN
    kpXPosController = TextEditingController(text: kpX_pos.toStringAsFixed(2));
    kiXPosController = TextEditingController(text: kiX_pos.toStringAsFixed(2));
    kdXPosController = TextEditingController(text: kdX_pos.toStringAsFixed(3));
    kpXNegController = TextEditingController(text: kpX_neg.toStringAsFixed(2));
    kiXNegController = TextEditingController(text: kiX_neg.toStringAsFixed(2));
    kdXNegController = TextEditingController(text: kdX_neg.toStringAsFixed(3));
    kpYPosController = TextEditingController(text: kpY_pos.toStringAsFixed(2));
    kiYPosController = TextEditingController(text: kiY_pos.toStringAsFixed(2));
    kdYPosController = TextEditingController(text: kdY_pos.toStringAsFixed(3));
    kpYNegController = TextEditingController(text: kpY_neg.toStringAsFixed(2));
    kiYNegController = TextEditingController(text: kiY_neg.toStringAsFixed(2));
    kdYNegController = TextEditingController(text: kdY_neg.toStringAsFixed(3));
    dFilterTimeConstantController = TextEditingController(text: dFilterTimeConstantS.toStringAsFixed(4)); // NEUE ZEILE HINZUGEFÜGT

    _loadPidValues(); // Load saved PID values
    _initBluetooth();
    
    // Starte UI Update Timer (10Hz für flüssige Updates)
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          // Leerer setState, um UI zu aktualisieren
        });
      }
    });
  }

  Future<void> _initBluetooth() async {
    adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        adapterState = state;
      });
    });

    await requestPermissions();

    if (Platform.isAndroid) {
      if (adapterState != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          print("Fehler beim Einschalten von Bluetooth: $e");
        }
      }
    }

    Future.delayed(const Duration(seconds: 1), () {
      startContinuousScan();
    });
  }

  // Methods for persistent storage of PID values
  Future<void> _loadPidValues() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Load X-axis PID values - ERWEITERT FÜR 4 QUADRANTEN
      kpX_pos = prefs.getDouble('kpxp') ?? 40.0;
      kiX_pos = prefs.getDouble('kixp') ?? 0.0;
      kdX_pos = prefs.getDouble('kdxp') ?? 0.3;
      kpX_neg = prefs.getDouble('kpxn') ?? 40.0;
      kiX_neg = prefs.getDouble('kixn') ?? 0.0;
      kdX_neg = prefs.getDouble('kdxn') ?? 0.3;

      // Load Y-axis PID values
      kpY_pos = prefs.getDouble('kpyp') ?? 40.0;
      kiY_pos = prefs.getDouble('kiyp') ?? 0.0;
      kdY_pos = prefs.getDouble('kdyp') ?? 0.3;
      kpY_neg = prefs.getDouble('kpyn') ?? 40.0;
      kiY_neg = prefs.getDouble('kiyn') ?? 0.0;
      kdY_neg = prefs.getDouble('kdyn') ?? 0.3;
      dFilterTimeConstantS = prefs.getDouble('dtc') ?? 0.005; // NEUE ZEILE (verwende 'dtc')

      // Update the text controllers with loaded values
      kpXPosController.text = kpX_pos.toStringAsFixed(2);
      kiXPosController.text = kiX_pos.toStringAsFixed(2);
      kdXPosController.text = kdX_pos.toStringAsFixed(3);
      kpXNegController.text = kpX_neg.toStringAsFixed(2);
      kiXNegController.text = kiX_neg.toStringAsFixed(2);
      kdXNegController.text = kdX_neg.toStringAsFixed(3);
      kpYPosController.text = kpY_pos.toStringAsFixed(2);
      kiYPosController.text = kiY_pos.toStringAsFixed(2);
      kdYPosController.text = kdY_pos.toStringAsFixed(3);
      kpYNegController.text = kpY_neg.toStringAsFixed(2);
      kiYNegController.text = kiY_neg.toStringAsFixed(2);
      kdYNegController.text = kdY_neg.toStringAsFixed(3);
      dFilterTimeConstantController.text = dFilterTimeConstantS.toStringAsFixed(4); // NEUE ZEILE
    });

    print('Quadrant PID values loaded from storage');
  }

  Future<void> _savePidValues() async {
    final prefs = await SharedPreferences.getInstance();

    // Save X-axis PID values - ERWEITERT FÜR 4 QUADRANTEN
    await prefs.setDouble('kpxp', kpX_pos);
    await prefs.setDouble('kixp', kiX_pos);
    await prefs.setDouble('kdxp', kdX_pos);
    await prefs.setDouble('kpxn', kpX_neg);
    await prefs.setDouble('kixn', kiX_neg);
    await prefs.setDouble('kdxn', kdX_neg);

    // Save Y-axis PID values
    await prefs.setDouble('kpyp', kpY_pos);
    await prefs.setDouble('kiyp', kiY_pos);
    await prefs.setDouble('kdyp', kdY_pos);
    await prefs.setDouble('kpyn', kpY_neg);
    await prefs.setDouble('kiyn', kiY_neg);
    await prefs.setDouble('kdyn', kdY_neg);
    await prefs.setDouble('dtc', dFilterTimeConstantS); // NEUE ZEILE (verwende 'dtc')

    print('Quadrant PID values saved to storage');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _autoScanTimer?.cancel();
    _uiUpdateTimer?.cancel();  // Stoppe UI Update Timer
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    statusSubscription?.cancel();
    calibrationSubscription?.cancel();
    adapterSubscription?.cancel();
    _tabController.dispose();
    _calibrationStreamController.close();

    kpXPosController.dispose();
    kiXPosController.dispose();
    kdXPosController.dispose();
    kpXNegController.dispose();
    kiXNegController.dispose();
    kdXNegController.dispose();
    kpYPosController.dispose();
    kiYPosController.dispose();
    kdYPosController.dispose();
    kpYNegController.dispose();
    kiYNegController.dispose();
    kdYNegController.dispose();
    dFilterTimeConstantController.dispose(); // NEUE ZEILE HINZUGEFÜGT

    super.dispose();
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      List<Permission> permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ];

      Map<Permission, PermissionStatus> statuses = await permissions.request();

      bool allGranted = statuses.values.every((status) => status == PermissionStatus.granted);
      if (!allGranted) {
        print("Nicht alle Berechtigungen wurden erteilt");
      }
    }
  }

  Future<void> startContinuousScan() async {
    if (connectedDevice != null) return;

    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (connectedDevice != null) {
        timer.cancel();
        return;
      }

      if (!isScanning && !isConnecting) {
        await startScan();
      }
    });

    if (!isScanning && !isConnecting) {
      await startScan();
    }
  }

  Future<void> startScan() async {
    if (isScanning || isConnecting || connectedDevice != null) return;

    if (adapterState != BluetoothAdapterState.on) {
      print('Bluetooth ist ausgeschaltet');
      return;
    }

    setState(() {
      scanResults.clear();
      isScanning = true;
    });

    try {
      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        androidScanMode: AndroidScanMode.lowLatency,
      );

      scanSubscription?.cancel();
      scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        setState(() {
          scanResults = results.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });

        if (!isConnecting && connectedDevice == null) {
          for (var result in results) {
            String deviceName = _getDeviceName(result);
            String macAddress = result.device.remoteId.toString();

            bool hasOurService = false;
            for (var uuid in result.advertisementData.serviceUuids) {
              String uuidStr = uuid.toString().toLowerCase();
              if (uuidStr.contains("19b10000")) {
                hasOurService = true;
                break;
              }
            }

            bool isOurDevice = deviceName.contains('ESP32_MagLev') ||
                deviceName.contains('ESP32') ||
                macAddress.contains('ESP32') ||
                hasOurService;

            if (isOurDevice) {
              print("ESP32 gefunden! Verbinde automatisch...");
              await connectToDevice(result.device);
              break;
            }
          }
        }
      });

      await FlutterBluePlus.isScanning.where((val) => val == false).first;

    } catch (e) {
      print("Scan-Fehler Details: $e");
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  String _getDeviceName(ScanResult result) {
    String name = result.advertisementData.advName;
    if (name.isEmpty) {
      name = result.device.advName;
    }
    if (name.isEmpty) {
      name = result.advertisementData.localName;
    }
    if (name.isEmpty) {
      name = 'Unbekannt';
    }
    return name;
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      connectionStatus = "Verbinde...";
      // NEU: Zustand der Live-Kalibrierungsanzeige beim Verbindungsaufbau zurücksetzen
      showLiveCalibration = false;
      liveCalibrationData.clear();
      // Die calibrationCurves werden hier nicht gelöscht, da sie evtl.
      // gültig sind oder über loadCalibrationCurves() neu geladen werden.
    });

    try {
      await FlutterBluePlus.stopScan();
      _autoScanTimer?.cancel();

      if (connectedDevice != null && connectedDevice!.isConnected) {
        await connectedDevice!.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      connectionSubscription?.cancel();
      connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            connectedDevice = null;
            connectionStatus = "Getrennt";
            pidCommandChar = null;
            statusDataChar = null;
            calibrationChar = null;
            isCalibrated = null;
            calibrationCurves.clear();
            // WICHTIG: Live-Daten nur löschen wenn gerade kalibriert wird

              liveCalibrationData.clear();
              showLiveCalibration = false;

            // Wenn Kalibrierung abgeschlossen war, Daten behalten für Anzeige!
          });
          statusSubscription?.cancel();
          calibrationSubscription?.cancel();
          showError("Verbindung verloren!");

          Future.delayed(const Duration(seconds: 2), () {
            startContinuousScan();
          });
        }
      });

      List<BluetoothService> services = await device.discoverServices();

      bool serviceFound = false;
      for (BluetoothService service in services) {
        if (service.uuid == serviceUuid) {
          serviceFound = true;
          for (BluetoothCharacteristic char in service.characteristics) {
            if (char.uuid == pidCommandUuid) {
              pidCommandChar = char;
              print("PID Command Charakteristik gefunden");
            } else if (char.uuid == statusDataUuid) {
              statusDataChar = char;
              print("Status Data Charakteristik gefunden");

              if (char.properties.notify) {
                await char.setNotifyValue(true);

                statusSubscription?.cancel();
                statusSubscription = char.lastValueStream.listen(
                      (value) {
                    processStatusData(value);
                  },
                  onError: (error) {
                    print("Notify Error: $error");
                  },
                );
              }
            } else if (char.uuid == calibrationUuid) {
              calibrationChar = char;
              print("Calibration Charakteristik gefunden");

              if (char.properties.notify) {
                await char.setNotifyValue(true);

                calibrationSubscription?.cancel();
                calibrationSubscription = char.lastValueStream.listen(
                      (value) {
                    processCalibrationData(value);
                  },
                  onError: (error) {
                    print("Calibration Notify Error: $error");
                  },
                );
              }
            }
          }
        }
      }

      if (!serviceFound) {
        throw Exception('MagLev Service nicht gefunden!');
      }

      if (pidCommandChar != null && statusDataChar != null) {
        setState(() {
          connectedDevice = device;
          connectionStatus = "Verbunden";
        });

        await Future.delayed(const Duration(milliseconds: 500));
        await sendAllCurrentValues();

        // NEU: Hole Version und Kalibrierungskurven
        await Future.delayed(const Duration(seconds: 1));
        await getVersion();
        await Future.delayed(const Duration(milliseconds: 500));
        await loadCalibrationCurves();

        showSuccess("Erfolgreich verbunden!");
      } else {
        throw Exception('Erforderliche Charakteristiken nicht gefunden');
      }

    } catch (e) {
      showError('Verbindungsfehler: ${e.toString()}');
      setState(() {
        connectionStatus = "Fehler";
      });

      try {
        await device.disconnect();
      } catch (_) {}

      Future.delayed(const Duration(seconds: 2), () {
        startContinuousScan();
      });
    } finally {
      setState(() {
        isConnecting = false;
      });
    }
  }

  Future<void> sendAllCurrentValues() async {
    // X-Achse positive Richtung
    await sendPidCommand('kpxp=$kpX_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kixp=$kiX_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kdxp=$kdX_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    
    // X-Achse negative Richtung
    await sendPidCommand('kpxn=$kpX_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kixn=$kiX_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kdxn=$kdX_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    
    // Y-Achse positive Richtung
    await sendPidCommand('kpyp=$kpY_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kiyp=$kiY_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kdyp=$kdY_pos');
    await Future.delayed(const Duration(milliseconds: 20));
    
    // Y-Achse negative Richtung
    await sendPidCommand('kpyn=$kpY_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kiyn=$kiY_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    await sendPidCommand('kdyn=$kdY_neg');
    await Future.delayed(const Duration(milliseconds: 20));
    
    // D-Filter Zeitkonstante
    await sendPidCommand('dtc=$dFilterTimeConstantS');
  }

  Future<void> disconnect() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        print("Disconnect error: $e");
      }
    }
  }

  void processStatusData(List<int> value) {
    // Unterscheide zwischen altem (12 Bytes) und neuem Container-Paket
    if (value.length > 12) {
      // --- NEUE LOGIK FÜR CONTAINER-PAKETE ---
      final byteData = ByteData.view(Uint8List.fromList(value).buffer);
      
      // Lies die Metadaten aus dem Paket-Header
      // uint8_t packet_type = byteData.getUint8(0); // Typ, falls benötigt
      int sampleCount = byteData.getUint8(1);
      
      // Lese Frequenzdaten
      final double parsedLoopFreq = byteData.getUint16(2, Endian.little) / 10.0;
      final double parsedBleFreq = byteData.getUint8(4).toDouble();
      
      // Wir starten das Auslesen der Samples nach dem Header (5 Bytes)
      int offset = 5;

      for (int i = 0; i < sampleCount; i++) {
        // Stelle sicher, dass wir nicht über das Ende der Daten hinauslesen
        if (offset + 4 <= value.length) {
          // Lese X und Y (jeweils 16-bit Integer) und skaliere zurück
          final double parsedX = byteData.getInt16(offset, Endian.little) / 1000.0;
          final double parsedY = byteData.getInt16(offset + 2, Endian.little) / 1000.0;
          
          // Verschiebe den Offset zum nächsten Sample
          offset += 4;
          
          // Füge die entpackten Daten dem Graphen hinzu
          sensorX = parsedX;
          sensorY = parsedY;
          isCalibrated = true;
          
          // Aktualisiere Frequenzdaten nur beim ersten Sample jedes Pakets
          if (i == 0) {
            loopFrequency = parsedLoopFreq;
            bleFrequency = parsedBleFreq;
          }
          
          final reading = SensorReading(
            timestamp: DateTime.now(), // Zeitstempel bei Empfang
            x: parsedX,
            y: parsedY,
            duty1: 0, // Duty-Cycle wird im neuen Paket nicht mehr gesendet
            duty2: 0,
          );

          if (isRecording) {
            sensorHistory.add(reading);
            if (sensorHistory.length > maxHistoryLength) {
              sensorHistory.removeAt(0);
            }
          }
        }
      }
      // Nach dem Verarbeiten aller Punkte die Statistik neu berechnen
      _calculateStatistics();

    } else if (value.length == 12) {
      // --- ALTE LOGIK FÜR EINZELPAKETE (als Fallback) ---
      final byteData = ByteData.view(Uint8List.fromList(value).buffer);
      int offset = 0;

      try {
        final double parsedX = byteData.getInt16(offset, Endian.little) / 1000.0;
        offset += 2;
        final double parsedY = byteData.getInt16(offset, Endian.little) / 1000.0;
        offset += 2;
        final int parsedDuty1 = byteData.getUint16(offset, Endian.little);
        offset += 2;
        final int parsedDuty2 = byteData.getUint16(offset, Endian.little);
        offset += 2;
        final double parsedLoopFreq = byteData.getUint16(offset, Endian.little) / 10.0;
        offset += 2;
        final int parsedFilter = byteData.getUint8(offset);
        offset += 1;
        final double parsedBleFreq = byteData.getUint8(offset).toDouble();

        sensorX = parsedX;
        sensorY = parsedY;
        duty1 = parsedDuty1;
        duty2 = parsedDuty2;
        loopFrequency = parsedLoopFreq;
        currentFilter = parsedFilter;
        bleFrequency = parsedBleFreq; // Neue Frequenz speichern
        isCalibrated = true; // Bei Binärformat immer kalibriert

        final reading = SensorReading(
          timestamp: DateTime.now(),
          x: sensorX,
          y: sensorY,
          duty1: duty1,
          duty2: duty2,
        );

        if (isRecording) {
          sensorHistory.add(reading);
          if (sensorHistory.length > maxHistoryLength) {
            sensorHistory.removeAt(0);
          }
        }
        _calculateStatistics();
      } catch (e) {
        print("Parse error in processStatusData: $e");
      }
    }
  }

  // Verarbeite Kalibrierungsdaten
  void processCalibrationData(List<int> value) {
    String jsonString;
    try {
      // Versuch, nur bis zum letzten schließenden Bracket zu dekodieren, wenn vorhanden
      int lastBracket = value.lastIndexOf(125); // 125 ist ASCII für '}'
      if (value.isNotEmpty && value[0] == 123 /* '{' */ && lastBracket != -1 && lastBracket < value.length) {
        jsonString = utf8.decode(value.sublist(0, lastBracket + 1));
      } else if (value.isNotEmpty && value[0] == 123) {
        // Fallback, wenn kein '}' gefunden wird oder das Format unerwartet ist
        print("WARNUNG: JSON-String unvollständig oder Format unerwartet empfangen. Vollständiger String wird versucht zu dekodieren.");
        jsonString = utf8.decode(value); // Versuche es trotzdem
      } else {
        print("ERROR: Empfangene Daten sind kein valides JSON-Fragment (beginnt nicht mit '{'). Ignoriere: $value");
        return;
      }

      // DEBUG: Log alle empfangenen BLE-Nachrichten
      if (jsonString.length > 100) {
        print('BLE DEBUG: Empfangen (gekürzt): ${jsonString.substring(0, 100)}...');
      } else {
        print('BLE DEBUG: Empfangen: $jsonString');
      }

      Map<String, dynamic> data = jsonDecode(jsonString);

      // NEU: Verarbeite Live-Kalibrierungsdaten
      if (data.containsKey('type')) {
        String type = data['type'];

        // LIVE-KALIBRIERUNGS-DATEN
        if (type == 'live_calib_start') {
          setState(() {
            liveCalibrationData.clear();
            liveCalibrationData.isCalibrating = true;
            liveCalibrationData.totalPoints = data['points'] ?? 41;
            liveCalibrationData.maxPwm = data['max_pwm'] ?? 1014;
            liveCalibrationData.firmwareVersion = data['version'] ?? "";
            showLiveCalibration = true;
          });
          print("Live-Kalibrierung gestartet! Punkte: ${liveCalibrationData.totalPoints}");

        } else if (type == 'live_calib_offset') {
          setState(() {
            liveCalibrationData.xOffset = (data['x_offset'] ?? 0.0).toDouble();
            liveCalibrationData.yOffset = (data['y_offset'] ?? 0.0).toDouble();
          });

        } else if (type == 'live_calib_point') {
          String curve = data['curve'] ?? '';
          int index = data['index'] ?? 0;
          int pwm = data['pwm'] ?? 0;
          double raw = (data['raw'] ?? 0.0).toDouble();
          double dev = (data['dev'] ?? 0.0).toDouble();
          int progress = data['progress'] ?? 0;

          // DEBUG: Log alle empfangenen Punkte für erste 5 Indizes
          if (index <= 4) {
            print('DEBUG: Empfangen $curve[Index $index]: PWM=$pwm, Dev=$dev, Raw=$raw');
          }

          // EXTRA DEBUG: Log alle PWM=0 Punkte unabhängig vom Index
          if (pwm == 0) {
            print('DEBUG PWM=0: Curve=$curve Index=$index PWM=$pwm Dev=$dev Raw=$raw');
          }

          setState(() {
            liveCalibrationData.currentProgress = progress;
            liveCalibrationData.currentCurve = curve;

            CalibrationPoint point = CalibrationPoint(pwm: pwm, mainAxis: dev, crossAxis: 0.0);

            // DEBUG: Log PWM=0 points to ensure they are received
            if (pwm == 0) {
              print('DEBUG: PWM=0 Punkt für $curve: dev=$dev, wird hinzugefügt');
            }

            switch (curve) {
              case 'x_pos':
                // Prüfe ob PWM=0 bereits existiert (doppelte Übertragung vom ESP32)
                bool pwm0Exists = index < liveCalibrationData.xPositiveLive.length &&
                                  liveCalibrationData.xPositiveLive[index].pwm == 0;

                if (index < liveCalibrationData.xPositiveLive.length) {
                  liveCalibrationData.xPositiveLive[index] = point;
                  if (pwm == 0 && !pwm0Exists) print('DEBUG: PWM=0 ersetzt in x_pos[Index $index]');
                } else {
                  liveCalibrationData.xPositiveLive.add(point);
                  if (pwm == 0) print('DEBUG: PWM=0 hinzugefügt zu x_pos[Index $index], Liste-Länge: ${liveCalibrationData.xPositiveLive.length}');
                }
                break;
              case 'x_neg':
                if (index < liveCalibrationData.xNegativeLive.length) {
                  liveCalibrationData.xNegativeLive[index] = point;
                } else {
                  liveCalibrationData.xNegativeLive.add(point);
                }
                break;
              case 'y_pos':
                if (index < liveCalibrationData.yPositiveLive.length) {
                  liveCalibrationData.yPositiveLive[index] = point;
                } else {
                  liveCalibrationData.yPositiveLive.add(point);
                }
                break;
              case 'y_neg':
                if (index < liveCalibrationData.yNegativeLive.length) {
                  liveCalibrationData.yNegativeLive[index] = point;
                } else {
                  liveCalibrationData.yNegativeLive.add(point);
                }
                break;
            }
          });

        } else if (type == 'live_calib_done') {
          setState(() {
            liveCalibrationData.isComplete = true;
            liveCalibrationData.isCalibrating = false;

            // Kopiere Live-Daten zu permanenten Kalibrierungskurven
            calibrationCurves.xPositive = List.from(liveCalibrationData.xPositiveLive);
            calibrationCurves.xNegative = List.from(liveCalibrationData.xNegativeLive);
            calibrationCurves.yPositive = List.from(liveCalibrationData.yPositiveLive);
            calibrationCurves.yNegative = List.from(liveCalibrationData.yNegativeLive);
            calibrationCurves.totalPoints = liveCalibrationData.totalPoints;
            calibrationCurves.maxPwm = liveCalibrationData.maxPwm;
            calibrationCurves.isComplete = true;

            // WICHTIG: Live-Chart weiter anzeigen mit fertigen Daten!
            // showLiveCalibration bleibt true damit User die Daten sieht
          });
          print("Live-Kalibrierung abgeschlossen! Daten bleiben sichtbar.");

        } else if (type == 'version') {
          setState(() {
            espFirmwareVersion = data['version'] ?? "";
          });
          print("ESP32 Firmware Version: $espFirmwareVersion");

          // NORMALE KALIBRIERUNGS-KURVEN
        } else if (type == 'calib_start') {
          calibrationCurves.clear();
          calibrationCurves.totalPoints = data['points'] ?? 0;
          calibrationCurves.maxPwm = data['max_pwm'] ?? 1014;
          print("Kalibrierungskurven-Empfang gestartet: ${calibrationCurves.totalPoints} Punkte");

        } else if (type == 'calib_data') {
          String curve = data['curve'] ?? '';
          List<dynamic> points = data['points'] ?? [];

          for (var point in points) {
            CalibrationPoint cp = CalibrationPoint(
              pwm: point['pwm'] ?? 0,
              mainAxis: (point['dev'] ?? 0.0).toDouble(),
              crossAxis: 0.0,
            );

            switch (curve) {
              case 'x_pos': calibrationCurves.xPositive.add(cp); break;
              case 'x_neg': calibrationCurves.xNegative.add(cp); break;
              case 'y_pos': calibrationCurves.yPositive.add(cp); break;
              case 'y_neg': calibrationCurves.yNegative.add(cp); break;
            }
          }

        } else if (type == 'calib_end') {
          calibrationCurves.isComplete = true;
          print("Kalibrierungskurven komplett empfangen");
          setState(() {
            isLoadingCalibCurves = false;
          });
          
        } else if (type == 'calib_complete_ready_for_download') {
          setState(() {
            calibUiState = CalibUiState.ready_for_download;
          });
          print("Kalibrierung abgeschlossen - bereit für Download");
          
        } else if (type == 'download_start') {
          // Capture metadata from download_start
          int calibSteps = data['calib_steps'] ?? 0;
          int mixGridSize = data['mix_grid_size'] ?? 0;
          double offsetX = (data['offset_x'] ?? 0.0).toDouble();
          double offsetY = (data['offset_y'] ?? 0.0).toDouble();
          
          setState(() {
            calibUiState = CalibUiState.downloading;
            calibDownloadTotalChunks = data['total_chunks'] ?? 0;
            calibDownloadChunksReceived = 1;  // download_start counts as chunk 0
            calibDownloadProgress = 1.0 / calibDownloadTotalChunks;
            downloadedCurves.clear();
            downloadedMixGrids.clear();
            // Store metadata for later use
            downloadMetadata['calib_steps'] = calibSteps;
            downloadMetadata['mix_grid_size'] = mixGridSize;
            downloadMetadata['offset_x'] = offsetX;
            downloadMetadata['offset_y'] = offsetY;
          });
          print("Download gestartet: $calibDownloadTotalChunks Chunks erwartet");
          print("Metadata - Steps: $calibSteps, Grid: $mixGridSize, Offset: ($offsetX, $offsetY)");
          
        } else if (type == 'calib_curve') {
          // Legacy single-point handler (keep for compatibility)
          int chunkIdx = data['chunk_idx'] ?? 0;
          String curveName = data['curve'] ?? '';
          int idx = data['idx'] ?? 0;
          int pwm = data['pwm'] ?? 0;
          double main = (data['main'] ?? 0.0).toDouble();
          double cross = (data['cross'] ?? 0.0).toDouble();
          
          if (!downloadedCurves.containsKey(curveName)) {
            downloadedCurves[curveName] = [];
          }
          
          // Ensure list is large enough
          while (downloadedCurves[curveName]!.length <= idx) {
            downloadedCurves[curveName]!.add(CalibrationPoint(pwm: 0, mainAxis: 0.0, crossAxis: 0.0));
          }
          
          downloadedCurves[curveName]![idx] = CalibrationPoint(pwm: pwm, mainAxis: main, crossAxis: 0.0);
          
          setState(() {
            calibDownloadChunksReceived = chunkIdx + 1;  // +1 because chunkIdx is 0-based
            calibDownloadProgress = calibDownloadTotalChunks > 0 
                ? (chunkIdx + 1) / calibDownloadTotalChunks 
                : 0.0;
          });
          
        } else if (type == 'calib_curve_chunk') {
          // New chunk handler for calibration curves
          int chunkIdx = data['chunk_idx'] ?? 0;
          String curveName = data['curve'] ?? '';
          int startIdx = data['start_idx'] ?? 0;
          List<dynamic> points = data['points'] ?? [];
          
          print('>>> [APP-LOG] Empfangen: Chunk $chunkIdx für Kurve "$curveName" mit ${points.length} Punkten.');
          
          if (!downloadedCurves.containsKey(curveName)) {
            downloadedCurves[curveName] = [];
          }
          
          // Ensure list is large enough
          while (downloadedCurves[curveName]!.length < startIdx + points.length) {
            downloadedCurves[curveName]!.add(CalibrationPoint(pwm: 0, mainAxis: 0.0, crossAxis: 0.0));
          }
          
          // Process all points in the chunk
          for (int i = 0; i < points.length; i++) {
            var point = points[i];
            int pwm = point['pwm'] ?? 0;
            double main = (point['main'] ?? 0.0).toDouble();
            double cross = (point['cross'] ?? 0.0).toDouble();
            downloadedCurves[curveName]![startIdx + i] = CalibrationPoint(pwm: pwm, mainAxis: main, crossAxis: cross);
          }
          
          setState(() {
            calibDownloadChunksReceived = chunkIdx + 1;  // +1 because chunkIdx is 0-based
            calibDownloadProgress = calibDownloadTotalChunks > 0 
                ? (chunkIdx + 1) / calibDownloadTotalChunks 
                : 0.0;
          });
          
        } else if (type == 'mix_grid') {
          // Legacy single-point handler (keep for compatibility)
          int chunkIdx = data['chunk_idx'] ?? 0;
          String axis = data['axis'] ?? '';
          String quadrant = data['quadrant'] ?? '';
          int i = data['i'] ?? 0;
          int j = data['j'] ?? 0;
          double value = (data['value'] ?? 0.0).toDouble();
          
          String key = '${axis}_$quadrant';
          if (!downloadedMixGrids.containsKey(key)) {
            int gridSize = downloadMetadata['mix_grid_size'] ?? 21;
            downloadedMixGrids[key] = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));
          }
          
          downloadedMixGrids[key]![i][j] = value;
          
          setState(() {
            calibDownloadChunksReceived = chunkIdx + 1;  // +1 because chunkIdx is 0-based
            calibDownloadProgress = calibDownloadTotalChunks > 0 
                ? (chunkIdx + 1) / calibDownloadTotalChunks 
                : 0.0;
          });
          
        } else if (type == 'mix_grid_chunk') {
          // New chunk handler for mix grid data
          int chunkIdx = data['chunk_idx'] ?? 0;
          String axis = data['axis'] ?? '';
          String quadrant = data['quadrant'] ?? '';
          List<dynamic> points = data['points'] ?? [];
          
          String key = '${axis}_$quadrant';
          if (!downloadedMixGrids.containsKey(key)) {
            int gridSize = downloadMetadata['mix_grid_size'] ?? 21;
            downloadedMixGrids[key] = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));
          }
          
          // Process all points in the chunk
          for (var point in points) {
            int i = point['i'] ?? 0;
            int j = point['j'] ?? 0;
            double value = (point['v'] ?? 0.0).toDouble();
            downloadedMixGrids[key]![i][j] = value;
          }
          
          setState(() {
            calibDownloadChunksReceived = chunkIdx + 1;  // +1 because chunkIdx is 0-based
            calibDownloadProgress = calibDownloadTotalChunks > 0 
                ? (chunkIdx + 1) / calibDownloadTotalChunks 
                : 0.0;
          });
          
        } else if (type == 'download_complete') {
          // download_complete is also a chunk!
          calibDownloadChunksReceived++;
          
          int totalSentByEsp = data['total_sent'] ?? 0;
          int expectedByEsp = data['expected'] ?? 0;

          print("[APP DOWNLOAD STATUS] ESP gesendet: $totalSentByEsp, ESP erwartet: $expectedByEsp, App empfangen: $calibDownloadChunksReceived, App erwartet gesamt: $calibDownloadTotalChunks");

          // Strenge Prüfung: Alle Chunks, die laut "download_start" erwartet wurden, müssen angekommen sein
          if (calibDownloadChunksReceived >= calibDownloadTotalChunks && calibDownloadTotalChunks > 0) {
            print("Download ERFOLGREICH abgeschlossen - alle $calibDownloadChunksReceived / $calibDownloadTotalChunks Chunks empfangen.");
            if (mounted) {
              showSuccess("Kalibrierungsdaten vollständig geladen!");
              setState(() {
                calibUiState = CalibUiState.download_complete;
                calibDownloadProgress = 1.0;
              });
            }
          } else {
            print("WARNUNG: Download abgeschlossen, aber App hat nur $calibDownloadChunksReceived von $calibDownloadTotalChunks Chunks empfangen (ESP Detail: $totalSentByEsp/$expectedByEsp).");
            if (mounted) {
              showError("Daten unvollständig: $calibDownloadChunksReceived/$calibDownloadTotalChunks empfangen!");
              setState(() {
                calibUiState = CalibUiState.download_aborted;
                if (calibDownloadTotalChunks > 0) {
                  calibDownloadProgress = calibDownloadChunksReceived / calibDownloadTotalChunks;
                }
              });
            }
          }
          
          // Debug logging for calibration data after download
          print("=== CALIBRATION DATA DEBUG INFO ===");
          print("Download complete. Debugging calibration data state:");
          print("- Total chunks received: $calibDownloadChunksReceived / $calibDownloadTotalChunks");
          print("- Downloaded curves count: ${downloadedCurves.length}");
          
          // Log metadata if available
          if (downloadMetadata.isNotEmpty) {
            print("- Calibration steps: ${downloadMetadata['calib_steps']}");
            print("- Mix grid size: ${downloadMetadata['mix_grid_size']}");
            print("- Basis offset X: ${downloadMetadata['offset_x']}");
            print("- Basis offset Y: ${downloadMetadata['offset_y']}");
          }
          
          // Log details about each downloaded curve
          downloadedCurves.forEach((curveName, points) {
            print("- Curve '$curveName': ${points.length} points");
            if (points.isNotEmpty) {
              print("  First point: PWM=${points.first.pwm}, main=${points.first.mainAxis}, cross=${points.first.crossAxis}");
              print("  Last point: PWM=${points.last.pwm}, main=${points.last.mainAxis}, cross=${points.last.crossAxis}");
              // Show a few sample points
              if (points.length > 2) {
                print("  Sample points:");
                for (int i = 0; i < math.min(5, points.length); i++) {
                  final p = points[i];
                  print("    [$i]: PWM=${p.pwm}, main=${p.mainAxis.toStringAsFixed(3)}");
                }
              }
            }
          });
          
          // Log details about downloaded mix grids
          downloadedMixGrids.forEach((gridName, gridData) {
            print("- Mix Grid '$gridName': ${gridData.length} rows");
            if (gridData.isNotEmpty && gridData.first.isNotEmpty) {
              print("  Grid dimensions: ${gridData.length} x ${gridData.first.length}");
              print("  Sample values: ${gridData.first.take(5).map((v) => v.toStringAsFixed(3)).toList()}");
            }
          });
          print("=== END CALIBRATION DATA DEBUG INFO ===");
          
          // Re-enable status notifications
          _reenableStatusNotifications();
          
        } else if (type == 'download_aborted') {
          setState(() {
            calibUiState = CalibUiState.download_aborted;
          });
          print("Download abgebrochen");
          
          // Re-enable status notifications
          _reenableStatusNotifications();
        }

        return; // Früher Return für Kurven-Daten
      }

      // Normale Positionierungs-Daten
      if (mounted) {
        setState(() {
          if (data.containsKey('positioning')) {
            var positioningValue = data['positioning'];
            if (positioningValue is bool) {
              isCalibrating = positioningValue;
            } else if (positioningValue is String) {
              isCalibrating = positioningValue == 'true';
            }

            // DEBUG: Log positioning status changes
            print('DEBUG POSITIONING: isCalibrating=$isCalibrating, step=${data['step'] ?? 0}');
          }

          if (data.containsKey('step')) {
            calibrationStep = data['step'] ?? 0;
          }

          // Setze default total_steps wenn nicht übertragen (für kompakte Version)
          calibrationTotalSteps = data['total_steps'] ?? 5;

          // DEBUG: Log all available positioning data fields
          if (data.containsKey('positioning') && data['positioning'] == true) {
            print('DEBUG POSITIONING DATA: ${data.keys.toList()}');
          }

          // VERWENDE DIREKT DIE KOMPENSIERTEN WERTE aus kompakter Nachricht
          if (data.containsKey('comp_x') && data.containsKey('comp_y')) {
            double compX = (data['comp_x'] ?? 0.0).toDouble();
            double compY = (data['comp_y'] ?? 0.0).toDouble();

            currentCalibrationData = CalibrationData(
              x: compX,
              y: compY,
              deviation: math.sqrt(compX * compX + compY * compY),
              quality: _calculateQuality(compX, compY),
              pwmX: data['pwm_x'],
              pwmY: data['pwm_y'],
            );

            print('✅ COMPENSATED DATA: comp_x=$compX, comp_y=$compY, deviation=${currentCalibrationData?.deviation}');
          }

          if (data.containsKey('positioning') && data['positioning'] == false) {
            isCalibrating = false;
            calibrationStep = 0;
          }
        });

        _sendCalibrationUpdate();
      }
    } catch (e) {
      print("JSON Decode Error in processCalibrationData: $e. Rohdaten: ${utf8.decode(value, allowMalformed: true)}");
      return; // Verhindert weitere Verarbeitung bei Fehler
    }
  }

  int _calculateQuality(double x, double y) {
    double deviation = math.sqrt(x * x + y * y);
    if (deviation < 0.05) return 5;
    if (deviation < 0.1) return 4;
    if (deviation < 0.2) return 3;
    if (deviation < 0.3) return 2;
    return 1;
  }

  void _calculateStatistics() {
    if (sensorHistory.length < 10) return;

    List<double> xValues = sensorHistory.map((r) => r.x).toList();
    xMin = xValues.reduce(math.min);
    xMax = xValues.reduce(math.max);
    xAvg = xValues.reduce((a, b) => a + b) / xValues.length;

    // Verbesserte Rauschberechnung nach TMAG5273 Datenblatt
    // RMS-Rauschen mit Moving Window für bessere Genauigkeit
    noiseX = _calculateRMSNoise(xValues, xAvg);
    xStdDev = noiseX; // Für Kompatibilität

    List<double> yValues = sensorHistory.map((r) => r.y).toList();
    yMin = yValues.reduce(math.min);
    yMax = yValues.reduce(math.max);
    yAvg = yValues.reduce((a, b) => a + b) / yValues.length;

    // Verbesserte Rauschberechnung nach TMAG5273 Datenblatt
    noiseY = _calculateRMSNoise(yValues, yAvg);
    yStdDev = noiseY; // Für Kompatibilität

    _estimateFrequency();
  }

  // Neue Methode für RMS-Rauschberechnung nach Datenblatt
  double _calculateRMSNoise(List<double> values, double mean) {
    if (values.length < 20) {
      // Zu wenige Samples für genaue Berechnung
      return _calculateSimpleStdDev(values, mean);
    }

    // Detrending: Entferne linearen Trend für genauere Rauschmessung
    List<double> detrended = _detrendData(values);
    
    // Berechne RMS des detrendierten Signals
    double sumSquares = 0;
    for (double val in detrended) {
      sumSquares += val * val;
    }
    double rms = math.sqrt(sumSquares / detrended.length);

    // Optional: Hochfrequenz-Filterung für echtes Sensorrauschen
    // (entfernt niederfrequente Störungen < 10 Hz)
    if (values.length > 100) {
      return _filterHighFrequencyNoise(values, rms);
    }
    
    return rms;
  }

  // Hilfsmethode: Einfache Standardabweichung
  double _calculateSimpleStdDev(List<double> values, double mean) {
    double variance = 0;
    for (double val in values) {
      variance += math.pow(val - mean, 2);
    }
    return math.sqrt(variance / values.length);
  }

  // Hilfsmethode: Linearen Trend entfernen
  List<double> _detrendData(List<double> values) {
    int n = values.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += values[i];
      sumXY += i * values[i];
      sumX2 += i * i;
    }
    
    // Lineare Regression: y = slope * x + intercept
    double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    double intercept = (sumY - slope * sumX) / n;
    
    // Trend subtrahieren
    List<double> detrended = [];
    for (int i = 0; i < n; i++) {
      detrended.add(values[i] - (slope * i + intercept));
    }
    
    return detrended;
  }

  // Hilfsmethode: Hochfrequenz-Rauschen filtern (> 10 Hz)
  double _filterHighFrequencyNoise(List<double> values, double baseRMS) {
    // Differenzen-Methode für Hochfrequenz-Komponenten
    double diffSum = 0;
    int count = 0;
    
    for (int i = 1; i < values.length; i++) {
      double diff = values[i] - values[i-1];
      diffSum += diff * diff;
      count++;
    }
    
    // Skalierung für 600 Hz Abtastrate
    double highFreqRMS = math.sqrt(diffSum / count) / math.sqrt(2);
    
    // Kombiniere mit Basis-RMS, gewichte Hochfrequenz stärker
    return math.sqrt(baseRMS * baseRMS * 0.3 + highFreqRMS * highFreqRMS * 0.7);
  }

  void _estimateFrequency() {
    if (sensorHistory.length < 50) return;

    int xCrossings = 0;
    int yCrossings = 0;

    for (int i = 1; i < sensorHistory.length; i++) {
      if ((sensorHistory[i-1].x - xAvg) * (sensorHistory[i].x - xAvg) < 0) {
        xCrossings++;
      }
      if ((sensorHistory[i-1].y - yAvg) * (sensorHistory[i].y - yAvg) < 0) {
        yCrossings++;
      }
    }

    double timeSpan = sensorHistory.last.timestamp.difference(sensorHistory.first.timestamp).inMilliseconds / 1000.0;

    dominantFreqX = (xCrossings / 2.0) / timeSpan;
    dominantFreqY = (yCrossings / 2.0) / timeSpan;
  }

  // Sende Kalibrierungs-Update über Stream
  void _sendCalibrationUpdate() {
    final update = CalibrationUpdate(
      isCalibrated: isCalibrated,
      isCalibrating: isCalibrating,
      calibrationStep: calibrationStep,
      currentCalibrationData: currentCalibrationData,
      hasCalibData: calibrationCurves.isComplete,
    );
    _calibrationStreamController.add(update);
  }

  Future<void> sendPidCommand(String command) async {
    if (pidCommandChar != null && connectedDevice != null && connectedDevice!.isConnected) {
      try {
        List<int> bytes = utf8.encode(command);
        await pidCommandChar!.write(bytes, withoutResponse: true);
        print("Gesendet: $command");
      } catch (e) {
        print("Sendefehler: $e");
        showError('Sendefehler: ${e.toString()}');
      }
    }
  }

  // Sende Kalibrierungs-Befehl
  Future<void> sendCalibrationCommand(String command) async {
    if (pidCommandChar != null && connectedDevice != null && connectedDevice!.isConnected) {
      try {
        List<int> bytes = utf8.encode(command);
        await pidCommandChar!.write(bytes, withoutResponse: true);
        print("Kalibrierung: $command");
      } catch (e) {
        print("Kalibrierungs-Fehler: $e");
        showError('Kalibrierungs-Fehler: ${e.toString()}');
      }
    }
  }

  // NEU: Hole Version
  Future<void> getVersion() async {
    await sendCalibrationCommand('GET_VERSION');
  }

  // NEU: Lade Kalibrierungskurven
  Future<void> loadCalibrationCurves() async {
    if (!calibrationCurves.isComplete) {
      setState(() {
        isLoadingCalibCurves = true;
      });
      await sendCalibrationCommand('GET_CALIB_DATA');

      // Warte max. 5 Sekunden auf Daten
      int waitCount = 0;
      while (!calibrationCurves.isComplete && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      setState(() {
        isLoadingCalibCurves = false;
      });
    }
  }

  Future<void> downloadAllCalibrationData() async {
    if (calibrationChar == null) {
      showError("Nicht verbunden");
      return;
    }
    
    setState(() {
      calibUiState = CalibUiState.downloading;
      calibDownloadProgress = 0.0;
      calibDownloadChunksReceived = 0;
      calibDownloadTotalChunks = 0;
    });
    
    // Disable status notifications during download
    await statusDataChar?.setNotifyValue(false);
    
    // Send download command
    await sendCalibrationCommand('GET_ALL_DATA');
  }
  
  Future<void> _reenableStatusNotifications() async {
    try {
      await statusDataChar?.setNotifyValue(true);
    } catch (e) {
      print("Fehler beim Reaktivieren der Status-Benachrichtigungen: $e");
    }
  }

  void _sendPidCommandDebounced(String command) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      sendPidCommand(command);
    });
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void exportSensorDataToCSV() async {
    if (sensorHistory.isEmpty) {
      showError('Keine Daten zum Exportieren vorhanden');
      return;
    }
    
    // Erstelle CSV-Daten
    String csv = 'Timestamp,X (mT),Y (mT),Duty1,Duty2\n';
    for (var reading in sensorHistory) {
      csv += '${reading.timestamp.toIso8601String()},${reading.x},${reading.y},${reading.duty1},${reading.duty2}\n';
    }
    
    // Speichere in temporäre Datei
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final file = File('${directory.path}/maglev_sensor_data_$timestamp.csv');
    await file.writeAsString(csv);
    
    // Teile die Datei
    Share.shareXFiles([XFile(file.path)], text: 'MagLev Sensor Data Export');
    showSuccess('Daten wurden exportiert');
  }

  String _getFilterName(int filter) {
    switch (filter) {
      case 0: return 'Keine';
      case 1: return 'Median';
      case 2: return 'Adaptiv';
      case 3: return 'Kalman';
      case 4: return 'Kombiniert';
      case 5: return 'Butterworth';
      case 6: return 'Super-Smooth';
      case 7: return 'Ultra-Light';
      case 8: return 'Spike-Only';
      case 9: return 'Noise-Only';
      default: return 'Unbekannt';
    }
  }

  // Kalibrierungs-Dialog
  void showCalibrationDialog() async {
    print("showCalibrationDialog aufgerufen");

    // Positionierungs-Dialog kann immer geöffnet werden

    final initialUpdate = CalibrationUpdate(
      isCalibrated: isCalibrated,
      isCalibrating: false,
      calibrationStep: 0,
      currentCalibrationData: null,
      hasCalibData: calibrationCurves.isComplete,
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return CalibrationDialog(
          initialUpdate: initialUpdate,
          calibrationStream: _calibrationStreamController.stream,
          onStartCalibration: () async {
            print("Starting calibration from dialog");
            setState(() {
              isCalibrating = true;
              calibrationStep = 1;
              currentCalibrationData = null;
            });
            _sendCalibrationUpdate();
            await sendCalibrationCommand('START_SENSOR_POSITIONING');
          },
          onConfirmStep: () async {
            print("Confirm step aufgerufen für Schritt $calibrationStep");
            setState(() {
              if (calibrationStep < 6) {
                calibrationStep++;
                currentCalibrationData = null;
                print("Lokal: Schritt erhöht auf $calibrationStep");
              }
            });
            _sendCalibrationUpdate();
            await sendCalibrationCommand('NEXT_POSITIONING_STEP');
          },
          onCancel: () async {
            print("Cancel calibration");
            setState(() {
              isCalibrating = false;
              calibrationStep = 0;
              currentCalibrationData = null;
            });
            _sendCalibrationUpdate();
            await sendCalibrationCommand('END_SENSOR_POSITIONING');
          },
          onSendCommand: (String command) async {
            await sendCalibrationCommand(command);
          },
        );
      },
    );

    setState(() {
      isCalibrating = false;
      calibrationStep = 0;
      currentCalibrationData = null;
    });
  }

  Color _getQualityColor(int quality) {
    switch (quality) {
      case 5: return Colors.green;
      case 4: return Colors.lightGreen;
      case 3: return Colors.yellow.shade700;
      case 2: return Colors.orange;
      default: return Colors.red;
    }
  }

  void showPresetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PID Presets'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Sanft (Niedrige Verstärkung)'),
              subtitle: const Text('Kp=30, Ki=0, Kd=0.2'),
              onTap: () {
                applyPreset(30, 0, 0.2, 30, 0, 0.2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Standard'),
              subtitle: const Text('Kp=40, Ki=0, Kd=0.3'),
              onTap: () {
                applyPreset(40, 0, 0.3, 40, 0, 0.3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Aggressiv'),
              subtitle: const Text('Kp=60, Ki=5, Kd=0.5'),
              onTap: () {
                applyPreset(60, 5, 0.5, 60, 5, 0.5);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Nur P-Regler'),
              subtitle: const Text('Kp=50, Ki=0, Kd=0'),
              onTap: () {
                applyPreset(50, 0, 0, 50, 0, 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Alles zurücksetzen'),
              subtitle: const Text('Alle Werte auf 0'),
              onTap: () {
                applyPreset(20, 0, 0, 20, 0, 0);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ESP32 Sensor-Filter'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Aktiv: ${_getFilterName(currentFilter)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Wähle einen neuen Filter:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Basis-Filter',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ListTile(
                title: const Text('Keine Filterung'),
                subtitle: const Text('Rohdaten ohne Glättung - Beste Performance!'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentFilter == 0) const Icon(Icons.check, color: Colors.green),
                    const SizedBox(width: 8),
                    const Icon(Icons.recommend, color: Colors.green),
                  ],
                ),
                onTap: () {
                  sendPidCommand('filter=0');
                  Navigator.pop(context);
                  showSuccess('Filter: Keine Filterung');
                },
              ),
              ListTile(
                title: const Text('Ultra-Light'),
                subtitle: const Text('Minimale Glättung (80/20 EMA)'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentFilter == 7) const Icon(Icons.check, color: Colors.green),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: Colors.orange),
                  ],
                ),
                onTap: () {
                  sendPidCommand('filter=7');
                  Navigator.pop(context);
                  showSuccess('Filter: Ultra-Light');
                },
              ),
              ListTile(
                title: const Text('Spike-Only'),
                subtitle: const Text('Entfernt nur extreme Ausreißer'),
                trailing: currentFilter == 8 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=8');
                  Navigator.pop(context);
                  showSuccess('Filter: Spike-Only');
                },
              ),
              ListTile(
                title: const Text('Noise-Only'),
                subtitle: const Text('Reduziert nur hochfrequentes Rauschen'),
                trailing: currentFilter == 9 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=9');
                  Navigator.pop(context);
                  showSuccess('Filter: Noise-Only');
                },
              ),

              const Divider(),
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Standard-Filter',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ListTile(
                title: const Text('Median-Filter'),
                subtitle: const Text('Entfernt Ausreißer effektiv'),
                trailing: currentFilter == 1 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=1');
                  Navigator.pop(context);
                  showSuccess('Filter: Median');
                },
              ),
              ListTile(
                title: const Text('Adaptiver LPF'),
                subtitle: const Text('Variable Glättung'),
                trailing: currentFilter == 2 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=2');
                  Navigator.pop(context);
                  showSuccess('Filter: Adaptiver LPF');
                },
              ),
              ListTile(
                title: const Text('Kalman-Filter'),
                subtitle: const Text('Mathematisch optimal'),
                trailing: currentFilter == 3 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=3');
                  Navigator.pop(context);
                  showSuccess('Filter: Kalman');
                },
              ),

              const Divider(),
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Starke Filter (mehr Latenz)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ListTile(
                title: const Text('Kombiniert'),
                subtitle: const Text('Median + Adaptiver LPF'),
                trailing: currentFilter == 4 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=4');
                  Navigator.pop(context);
                  showSuccess('Filter: Kombiniert');
                },
              ),
              ListTile(
                title: const Text('Butterworth'),
                subtitle: const Text('2. Ordnung, sehr glatt'),
                trailing: currentFilter == 5 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=5');
                  Navigator.pop(context);
                  showSuccess('Filter: Butterworth');
                },
              ),
              ListTile(
                title: const Text('Super-Smooth'),
                subtitle: const Text('Maximum Glättung'),
                trailing: currentFilter == 6 ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  sendPidCommand('filter=6');
                  Navigator.pop(context);
                  showSuccess('Filter: Super-Smooth');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void applyPreset(double kpx, double kix, double kdx, double kpy, double kiy, double kdy) {
    setState(() {
      // Apply preset values to all four quadrants
      kpX_pos = kpx;
      kiX_pos = kix;
      kdX_pos = kdx;
      kpX_neg = kpx;
      kiX_neg = kix;
      kdX_neg = kdx;
      
      kpY_pos = kpy;
      kiY_pos = kiy;
      kdY_pos = kdy;
      kpY_neg = kpy;
      kiY_neg = kiy;
      kdY_neg = kdy;

      // Update all controllers
      kpXPosController.text = kpX_pos.toStringAsFixed(2);
      kiXPosController.text = kiX_pos.toStringAsFixed(2);
      kdXPosController.text = kdX_pos.toStringAsFixed(3);
      kpXNegController.text = kpX_neg.toStringAsFixed(2);
      kiXNegController.text = kiX_neg.toStringAsFixed(2);
      kdXNegController.text = kdX_neg.toStringAsFixed(3);
      
      kpYPosController.text = kpY_pos.toStringAsFixed(2);
      kiYPosController.text = kiY_pos.toStringAsFixed(2);
      kdYPosController.text = kdY_pos.toStringAsFixed(3);
      kpYNegController.text = kpY_neg.toStringAsFixed(2);
      kiYNegController.text = kiY_neg.toStringAsFixed(2);
      kdYNegController.text = kdY_neg.toStringAsFixed(3);
    });

    _savePidValues(); // Save to persistent storage when preset is applied
    sendAllCurrentValues();
  }

  Widget buildScanView() {
    if (adapterState != BluetoothAdapterState.on) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Bluetooth ist ausgeschaltet',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (Platform.isAndroid) {
                  await FlutterBluePlus.turnOn();
                }
              },
              child: const Text('Bluetooth einschalten'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      isScanning ? 'Suche nach ESP32...' : 'Warte auf nächsten Scan...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (scanResults.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Suche läuft automatisch.\nDer ESP32 wird automatisch verbunden sobald er gefunden wird.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: scanResults.length,
            itemBuilder: (context, index) {
              ScanResult result = scanResults[index];
              String deviceName = _getDeviceName(result);
              String macAddress = result.device.remoteId.toString();

              bool hasOurService = false;
              for (var uuid in result.advertisementData.serviceUuids) {
                String uuidStr = uuid.toString().toLowerCase();
                if (uuidStr.contains("19b10000")) {
                  hasOurService = true;
                  break;
                }
              }

              bool isOurDevice = deviceName.contains('ESP32_MagLev') ||
                  deviceName.contains('ESP32') ||
                  macAddress.contains('ESP32') ||
                  hasOurService;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: isOurDevice ? 4 : 1,
                color: isOurDevice ? Colors.blue.shade50 : null,
                child: ListTile(
                  leading: Icon(
                    Icons.bluetooth,
                    color: isOurDevice ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    deviceName.isEmpty ? 'ESP32 (Unnamed)' : deviceName,
                    style: TextStyle(
                      fontWeight: isOurDevice ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAC: $macAddress'),
                      if (isOurDevice)
                        const Text(
                          'MagLev Controller (Verbinde automatisch...)',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${result.rssi} dBm'),
                      Icon(
                        _getRssiIcon(result.rssi),
                        size: 16,
                        color: _getRssiColor(result.rssi),
                      ),
                    ],
                  ),
                  onTap: isOurDevice ? () => connectToDevice(result.device) : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getRssiIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_wifi_4_bar;
    if (rssi >= -70) return Icons.network_wifi_3_bar;
    if (rssi >= -80) return Icons.network_wifi_2_bar;
    if (rssi >= -90) return Icons.network_wifi_1_bar;
    return Icons.signal_wifi_0_bar;
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -70) return Colors.lightGreen;
    if (rssi >= -80) return Colors.orange;
    if (rssi >= -90) return Colors.deepOrange;
    return Colors.red;
  }

  Widget buildImprovedPidControl({
    required String label,
    required String param,
    required double value,
    required double min,
    required double max,
    required double smallStep,
    required double largeStep,
    required TextEditingController controller,
    required Function(double) onChanged,
    Widget? secondaryInfo, // NEUER OPTIONALER PARAMETER
  }) {
    double step1 = largeStep;
    double step2 = (param.contains('kd')) ? 0.01 : 0.1;
    double step3 = smallStep;

    int decimals = 2;
    if (smallStep < 0.01) decimals = 3;
    if (smallStep < 0.001) decimals = 4;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Spalte für Label und sekundäre Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (secondaryInfo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: secondaryInfo, // Hier wird die Zusatzinfo angezeigt
                      ),
                  ],
                ),
              ),
              // Der große Wert rechts
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Text(
                  value.toStringAsFixed(decimals),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          double newValue = (value - step1).clamp(min, max);
                          controller.text = newValue.toStringAsFixed(decimals);
                          onChanged(newValue);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minimumSize: const Size(double.infinity, 0),
                        ),
                        child: Text(
                          '− $step1',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                double newValue = (value - step2).clamp(min, max);
                                controller.text = newValue.toStringAsFixed(decimals);
                                onChanged(newValue);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 0),
                              ),
                              child: Text(
                                '− $step2',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                double newValue = (value - step3).clamp(min, max);
                                controller.text = newValue.toStringAsFixed(decimals);
                                onChanged(newValue);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 0),
                              ),
                              child: Text(
                                '− $step3',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              SizedBox(
                width: 100,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Direkt',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  onSubmitted: (text) {
                    double? newValue = double.tryParse(text);
                    if (newValue != null) {
                      newValue = newValue.clamp(min, max);
                      controller.text = newValue.toStringAsFixed(decimals);
                      onChanged(newValue);
                    }
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          double newValue = (value + step1).clamp(min, max);
                          controller.text = newValue.toStringAsFixed(decimals);
                          onChanged(newValue);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minimumSize: const Size(double.infinity, 0),
                        ),
                        child: Text(
                          '+ $step1',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                double newValue = (value + step3).clamp(min, max);
                                controller.text = newValue.toStringAsFixed(decimals);
                                onChanged(newValue);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 0),
                              ),
                              child: Text(
                                '+ $step3',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                double newValue = (value + step2).clamp(min, max);
                                controller.text = newValue.toStringAsFixed(decimals);
                                onChanged(newValue);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                minimumSize: const Size(0, 0),
                              ),
                              child: Text(
                                '+ $step2',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.blue,
              inactiveTrackColor: Colors.blue.shade100,
              thumbColor: Colors.blue,
              overlayColor: Colors.blue.withOpacity(0.2),
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / step3).round(),
              onChanged: (newValue) {
                controller.text = newValue.toStringAsFixed(decimals);
                onChanged(newValue);
              },
            ),
          ),
          Text(
            'Bereich: $min - $max',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSensorAnalysisView() {
    return Stack(
      children: [
        // Haupt-Chart als Basis
        Container(
          color: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildDualAxisChart(),
          ),
        ),
        
        // Zeitfenster-Steuerung am unteren Rand
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: _buildTimeWindowSelector(),
          ),
        ),
        
        // FloatingActionButton für Cockpit-Panel
        Positioned(
          right: 24,
          bottom: 80,
          child: FloatingActionButton(
            onPressed: () {
              setState(() {
                _showCockpitPanel = !_showCockpitPanel;
              });
            },
            backgroundColor: Colors.blue,
            child: Icon(
              _showCockpitPanel ? Icons.close : Icons.analytics,
              color: Colors.white,
            ),
          ),
        ),
        
        // Seitliches Cockpit-Panel mit Animation
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: _showCockpitPanel ? 0 : -320,
          top: 0,
          bottom: 0,
          width: 320,
          child: _buildCockpitPanel(),
        ),
      ],
    );
  }

  Widget _buildCompactStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  // Neue Widget-Methoden für das Analyse-Cockpit
  Widget _buildTimeWindowSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeButton('0.5s', 500),
          _buildTimeButton('1s', 1000),
          _buildTimeButton('3s', 3000),
          _buildTimeButton('5s', 5000),
        ],
      ),
    );
  }
  
  Widget _buildTimeButton(String label, int value) {
    final isSelected = _displayHistoryLength == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _displayHistoryLength = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
  
  Widget _buildCockpitPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(-5, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.analytics, color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Analyse-Cockpit',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildLiveValuesWidget(),
                    const SizedBox(height: 20),
                    _buildControlWidget(),
                    const SizedBox(height: 20),
                    _buildFilterFrequencyWidget(),
                    const SizedBox(height: 20),
                    _buildDetailStatisticsWidget(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLiveValuesWidget() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.green.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live-Werte',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'X-Achse',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sensorX.toStringAsFixed(3)} mT',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.grey.shade300,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Y-Achse',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sensorY.toStringAsFixed(3)} mT',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Steuerung',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    sensorHistory.clear();
                    xMin = xMax = xAvg = xStdDev = 0;
                    yMin = yMax = yAvg = yStdDev = 0;
                    noiseX = noiseY = 0;
                    dominantFreqX = dominantFreqY = 0;
                  });
                },
                icon: const Icon(Icons.clear_all, size: 20),
                label: const Text('Löschen'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: sensorHistory.isEmpty ? null : _exportToCSV,
                icon: const Icon(Icons.file_download, size: 20),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildFilterFrequencyWidget() {
    return GestureDetector(
      onTap: showFilterDialog,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade50,
              Colors.grey.shade100,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter & Frequenz',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        _getFilterName(currentFilter),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: loopFrequency < 850 ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.speed,
                        size: 16,
                        color: loopFrequency < 850 ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${loopFrequency.toStringAsFixed(0)} Hz',
                        style: TextStyle(
                          fontSize: 14,
                          color: loopFrequency < 850 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailStatisticsWidget() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.all(16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.analytics, color: Colors.purple, size: 20),
          ),
          title: const Text(
            'Detail-Statistik',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: sensorHistory.length > 10
              ? Text(
                  'RMS: X=${(noiseX * 1000).toStringAsFixed(1)} µT, Y=${(noiseY * 1000).toStringAsFixed(1)} µT',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                )
              : null,
          initiallyExpanded: false,
          children: [
            if (sensorHistory.length > 10) ...[
              // RMS Rauschen
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RMS-Rauschen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNoiseStatCard(
                            'X-Achse',
                            '${(noiseX * 1000).toStringAsFixed(2)} µT',
                            Colors.blue,
                            _getNoiseQuality(noiseX),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildNoiseStatCard(
                            'Y-Achse',
                            '${(noiseY * 1000).toStringAsFixed(2)} µT',
                            Colors.green,
                            _getNoiseQuality(noiseY),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Weitere Statistiken
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weitere Metriken',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatRow('X Min/Max', '${xMin.toStringAsFixed(3)} / ${xMax.toStringAsFixed(3)} mT'),
                    const Divider(height: 16),
                    _buildStatRow('Y Min/Max', '${yMin.toStringAsFixed(3)} / ${yMax.toStringAsFixed(3)} mT'),
                    const Divider(height: 16),
                    _buildStatRow('X Frequenz', '${dominantFreqX.toStringAsFixed(1)} Hz'),
                    const Divider(height: 16),
                    _buildStatRow('Y Frequenz', '${dominantFreqY.toStringAsFixed(1)} Hz'),
                    const Divider(height: 16),
                    _buildStatRow('Datenpunkte', '${sensorHistory.length} / $maxHistoryLength'),
                  ],
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Nicht genügend Daten für Statistiken',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNoiseStatCard(String label, String value, Color color, String quality) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            quality,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getNoiseQuality(double noiseMT) {
    double noiseUT = noiseMT * 1000;
    if (noiseUT < 10) {
      return 'Exzellent';
    } else if (noiseUT < 20) {
      return 'Sehr gut';
    } else if (noiseUT < 50) {
      return 'Gut';
    } else if (noiseUT < 100) {
      return 'Akzeptabel';
    } else {
      return 'Verbesserung nötig';
    }
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Hilfsmethode für Rausch-Farbbewertung nach TMAG5273 Spezifikation
  Color _getNoiseColor(double noiseMT) {
    // Umrechnung in Mikrotesla für bessere Lesbarkeit
    double noiseUT = noiseMT * 1000;
    
    // Bewertung nach TMAG5273 Datenblatt:
    // - Typisch: 170 µG = 17 µT RMS bei 32x Averaging
    // - Gut: < 30 µT (grün)
    // - Akzeptabel: 30-100 µT (gelb/orange)
    // - Schlecht: > 100 µT (rot)
    
    if (noiseUT < 30) {
      return Colors.green;  // Sehr gut
    } else if (noiseUT < 50) {
      return Colors.lightGreen;  // Gut
    } else if (noiseUT < 100) {
      return Colors.orange;  // Akzeptabel
    } else {
      return Colors.red;  // Zu hoch
    }
  }

  // Berechne Signal-zu-Rausch-Verhältnis in dB
  double _calculateSNR(double signal, double noise) {
    if (noise <= 0 || signal.abs() <= noise) {
      return 0;
    }
    return 20 * math.log(signal.abs() / noise) / math.ln10;
  }

  // Qualitätsbewertung des Rauschens
  String _getNoiseQualityText(double noiseX, double noiseY) {
    double avgNoiseUT = (noiseX + noiseY) * 500;  // Durchschnitt in µT
    
    if (avgNoiseUT < 20) {
      return 'Exzellent';
    } else if (avgNoiseUT < 40) {
      return 'Sehr gut';
    } else if (avgNoiseUT < 70) {
      return 'Gut';
    } else if (avgNoiseUT < 100) {
      return 'Akzeptabel';
    } else {
      return 'Verbesserung nötig';
    }
  }

  Widget _buildDualAxisChart({List<SensorReading>? data}) {
    // Use provided data or fall back to sensorHistory
    final dataSource = data ?? sensorHistory;
    
    if (dataSource.isEmpty) {
      return const Center(
        child: Text(
          'Keine Daten vorhanden\nDrücke Start um die Aufnahme zu beginnen',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // Verwende nur die letzten _displayHistoryLength Datenpunkte
    final displayData = dataSource.length <= _displayHistoryLength
        ? dataSource
        : dataSource.sublist(dataSource.length - _displayHistoryLength);

    double xDataMin = displayData.map((r) => r.x).reduce(math.min);
    double xDataMax = displayData.map((r) => r.x).reduce(math.max);
    double yDataMin = displayData.map((r) => r.y).reduce(math.min);
    double yDataMax = displayData.map((r) => r.y).reduce(math.max);

    double xPadding = (xDataMax - xDataMin) * 0.1;
    double yPadding = (yDataMax - yDataMin) * 0.1;

    // Anpassung der Y-Achsen-Beschriftung
    double dataMin = math.min(xDataMin - xPadding, yDataMin - yPadding);
    double dataMax = math.max(xDataMax + xPadding, yDataMax + yPadding);
    double dataRange = dataMax - dataMin;

    // Dynamische Intervall-Berechnung basierend auf dem Wertebereich
    double horizontalInterval;
    int decimalPlaces;

    if (dataRange < 0.1) {
      horizontalInterval = 0.01;
      decimalPlaces = 3;
    } else if (dataRange < 0.5) {
      horizontalInterval = 0.05;
      decimalPlaces = 2;
    } else if (dataRange < 1) {
      horizontalInterval = 0.1;
      decimalPlaces = 2;
    } else if (dataRange < 5) {
      horizontalInterval = 0.5;
      decimalPlaces = 1;
    } else if (dataRange < 10) {
      horizontalInterval = 1;
      decimalPlaces = 1;
    } else if (dataRange < 50) {
      horizontalInterval = 5;
      decimalPlaces = 0;
    } else {
      horizontalInterval = 10;
      decimalPlaces = 0;
    }

    return LineChart(
      LineChartData(
        minY: dataMin,
        maxY: dataMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: horizontalInterval * 2, // Weniger Linien
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 0.5,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: false, // Keine X-Achse Beschriftung
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: horizontalInterval * 4, // Nur wenige Y-Werte
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(decimalPlaces),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: false, // Kein Rahmen
        ),
              lineBarsData: [
                LineChartBarData(
                  spots: displayData.asMap().entries.map((entry) => FlSpot(
                    entry.key.toDouble(),
                    entry.value.x,
                  )).toList(),
                  isCurved: false,
                  color: Colors.blue,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                LineChartBarData(
                  spots: displayData.asMap().entries.map((entry) => FlSpot(
                    entry.key.toDouble(),
                    entry.value.y,
                  )).toList(),
                  isCurved: false,
                  color: Colors.green,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
        ],
        lineTouchData: const LineTouchData(
          enabled: false,
        ),
      ),
    );
  }

  Widget _buildDutyChart() {
    if (sensorHistory.isEmpty) {
      return const Center(child: Text('Keine Daten vorhanden'));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1023,
        gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 100,
                verticalInterval: sensorHistory.length > 100 ? 20 : 10,
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: sensorHistory.length > 100 ? sensorHistory.length / 5 : 20,
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('Duty Cycle', style: TextStyle(fontSize: 12)),
                  axisNameSize: 20,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    interval: 200,
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: sensorHistory.asMap().entries.map((entry) => FlSpot(
                    entry.key.toDouble(),
                    entry.value.duty1.toDouble(),
                  )).toList(),
                  isCurved: false,
                  color: Colors.orange,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: sensorHistory.asMap().entries.map((entry) => FlSpot(
                    entry.key.toDouble(),
                    entry.value.duty2.toDouble(),
                  )).toList(),
                  isCurved: false,
                  color: Colors.purple,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                ),
        ],
        lineTouchData: const LineTouchData(
          enabled: false,
        ),
      ),
    );
  }

  Widget _buildDetailedStats() {
    if (sensorHistory.length < 10) {
      return const Center(child: Text('Nicht genug Daten für Statistik'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailStatCard(
          'X-Achse Statistik',
          Colors.blue,
          [
            StatRow('Minimum', '${xMin.toStringAsFixed(4)} mT'),
            StatRow('Maximum', '${xMax.toStringAsFixed(4)} mT'),
            StatRow('Mittelwert', '${xAvg.toStringAsFixed(4)} mT'),
            StatRow('RMS-Rauschen', '${(noiseX * 1000).toStringAsFixed(2)} µT',
                _getNoiseColor(noiseX)),
            StatRow('Peak-to-Peak', '${((xMax - xMin) * 1000).toStringAsFixed(1)} µT'),
            StatRow('SNR', '${_calculateSNR(xAvg, noiseX).toStringAsFixed(1)} dB',
                _calculateSNR(xAvg, noiseX) > 40 ? Colors.green : Colors.orange),
            StatRow('Frequenz', '${dominantFreqX.toStringAsFixed(2)} Hz'),
          ],
        ),
        const SizedBox(height: 16),
        _buildDetailStatCard(
          'Y-Achse Statistik',
          Colors.green,
          [
            StatRow('Minimum', '${yMin.toStringAsFixed(4)} mT'),
            StatRow('Maximum', '${yMax.toStringAsFixed(4)} mT'),
            StatRow('Mittelwert', '${yAvg.toStringAsFixed(4)} mT'),
            StatRow('RMS-Rauschen', '${(noiseY * 1000).toStringAsFixed(2)} µT',
                _getNoiseColor(noiseY)),
            StatRow('Peak-to-Peak', '${((yMax - yMin) * 1000).toStringAsFixed(1)} µT'),
            StatRow('SNR', '${_calculateSNR(yAvg, noiseY).toStringAsFixed(1)} dB',
                _calculateSNR(yAvg, noiseY) > 40 ? Colors.green : Colors.orange),
            StatRow('Frequenz', '${dominantFreqY.toStringAsFixed(2)} Hz'),
          ],
        ),
        const SizedBox(height: 16),
        _buildDetailStatCard(
          'Rausch-Analyse (TMAG5273)',
          Colors.purple,
          [
            StatRow('Sensor-Spec', '17 µT RMS @ 32x Avg', Colors.grey),
            StatRow('Gemessen X', '${(noiseX * 1000).toStringAsFixed(2)} µT RMS',
                _getNoiseColor(noiseX)),
            StatRow('Gemessen Y', '${(noiseY * 1000).toStringAsFixed(2)} µT RMS',
                _getNoiseColor(noiseY)),
            StatRow('Qualität', _getNoiseQualityText(noiseX, noiseY),
                _getNoiseColor((noiseX + noiseY) / 2)),
          ],
        ),
        const SizedBox(height: 16),
        _buildDetailStatCard(
          'Duty Cycle Statistik',
          Colors.orange,
          [
            StatRow('Duty 1 Avg', '${sensorHistory.map((r) => r.duty1).reduce((a, b) => a + b) ~/ sensorHistory.length}'),
            StatRow('Duty 2 Avg', '${sensorHistory.map((r) => r.duty2).reduce((a, b) => a + b) ~/ sensorHistory.length}'),
            StatRow('Duty 1 Max', '${sensorHistory.map((r) => r.duty1).reduce(math.max)}'),
            StatRow('Duty 2 Max', '${sensorHistory.map((r) => r.duty2).reduce(math.max)}'),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailStatCard(String title, Color color, List<StatRow> stats) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: stats.map((stat) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(stat.label, style: const TextStyle(fontSize: 14)),
                    Text(
                      stat.value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: stat.color,
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToCSV() async {
    try {
      StringBuffer csv = StringBuffer();
      csv.writeln('Timestamp,X (mT),Y (mT),Duty1,Duty2');

      for (var reading in sensorHistory) {
        csv.writeln('${reading.timestamp.toIso8601String()},${reading.x},${reading.y},${reading.duty1},${reading.duty2}');
      }

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/maglev_sensor_data_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(path);
      await file.writeAsString(csv.toString());

      await Share.shareXFiles(
        [XFile(path)],
        text: 'MagLev Sensor Daten - ${sensorHistory.length} Samples',
      );

      showSuccess('CSV Export erfolgreich!');
    } catch (e) {
      showError('Export fehlgeschlagen: $e');
    }
  }

  Widget _buildStatusIndicator(String label, String value, MaterialColor color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.shade300),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
        ),
      ],
    );
  }

  // NEU: Widget für Kalibrierungskurven-Anzeige
  Widget _buildCalibrationCurveChart() {
    // Prüfen, ob Kalibrierungsdaten vollständig sind.
    // Wenn nicht, zeige einen Lade-Indikator.
    if (!calibrationCurves.isComplete || calibrationCurves.totalPoints == 0) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Lade Kalibrierungsdaten...'),
            ],
          ),
        ),
      );
    }

    // Daten sind vollständig, fahre fort mit der Erstellung des Diagramms.

    // Schritt 1: Berechne Min/Max-Werte für die Y-Achse (deviation).
    double minDev = double.infinity;
    double maxDev = double.negativeInfinity;

    List<CalibrationPoint> allPointsForBounds = [];
    if (calibrationCurves.xPositive.isNotEmpty) allPointsForBounds.addAll(calibrationCurves.xPositive);
    if (calibrationCurves.xNegative.isNotEmpty) allPointsForBounds.addAll(calibrationCurves.xNegative);
    if (calibrationCurves.yPositive.isNotEmpty) allPointsForBounds.addAll(calibrationCurves.yPositive);
    if (calibrationCurves.yNegative.isNotEmpty) allPointsForBounds.addAll(calibrationCurves.yNegative);

    if (allPointsForBounds.isEmpty) {
      // Fallback, falls keine Datenpunkte vorhanden sind.
      minDev = -0.5;
      maxDev = 0.5;
    } else {
      for (var point in allPointsForBounds) {
        if (point.mainAxis < minDev) minDev = point.mainAxis;
        if (point.mainAxis > maxDev) maxDev = point.mainAxis;
      }
    }

    double yAxisRange = maxDev - minDev;
    double paddingValue;

    if (yAxisRange == 0) {
      paddingValue = 0.1;
      minDev -= paddingValue;
      maxDev += paddingValue;
    } else {
      paddingValue = yAxisRange.abs() * 0.1;
    }

    // Finale Y-Achsen-Grenzen deklarieren und initialisieren.
    // Diese sind jetzt korrekt im richtigen Scope.
    final double finalMinY = minDev - paddingValue;
    final double finalMaxY = maxDev + paddingValue;

    // Schritt 2: Erzeuge und SORTIERE die FlSpot-Listen für jede Kurve.
    // FIX: Stelle sicher, dass der erste Punkt bei PWM=0 existiert
    List<FlSpot> xPositiveSpots = calibrationCurves.xPositive
        .map((p) => FlSpot(p.pwm.toDouble(), p.mainAxis))
        .toList();
    xPositiveSpots.sort((a, b) => a.x.compareTo(b.x));

    // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten

    List<FlSpot> xNegativeSpots = calibrationCurves.xNegative
        .map((p) => FlSpot(p.pwm.toDouble(), p.mainAxis))
        .toList();
    xNegativeSpots.sort((a, b) => a.x.compareTo(b.x));

    // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten

    List<FlSpot> yPositiveSpots = calibrationCurves.yPositive
        .map((p) => FlSpot(p.pwm.toDouble(), p.mainAxis))
        .toList();
    yPositiveSpots.sort((a, b) => a.x.compareTo(b.x));

    // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten

    List<FlSpot> yNegativeSpots = calibrationCurves.yNegative
        .map((p) => FlSpot(p.pwm.toDouble(), p.mainAxis))
        .toList();
    yNegativeSpots.sort((a, b) => a.x.compareTo(b.x));

    // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten

    // Schritt 3: Erstelle das Diagramm-Widget.
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          minY: finalMinY, // Verwende die finalen Y-Achsen-Grenzen
          maxY: finalMaxY, // Verwende die finalen Y-Achsen-Grenzen
          minX: 0,
          maxX: calibrationCurves.maxPwm.toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: (finalMaxY - finalMinY).abs() / 5 > 0
                ? (finalMaxY - finalMinY).abs() / 5
                : 0.1,
            verticalInterval: calibrationCurves.maxPwm / 8 > 0
                ? calibrationCurves.maxPwm / 8
                : 50,
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('PWM Wert', style: TextStyle(fontSize: 12)),
              axisNameSize: 20,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: calibrationCurves.maxPwm / 6 > 0
                    ? calibrationCurves.maxPwm / 6
                    : 100,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('Abweichung (mT)', style: TextStyle(fontSize: 12)),
              axisNameSize: 30,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  String label;
                  double range = (finalMaxY - finalMinY).abs();
                  if (range < 0.1) label = value.toStringAsFixed(3);
                  else if (range < 1) label = value.toStringAsFixed(2);
                  else label = value.toStringAsFixed(1);
                  return Text(label, style: const TextStyle(fontSize: 10));
                },
                interval: (finalMaxY - finalMinY).abs() / 5 > 0
                    ? (finalMaxY - finalMinY).abs() / 5
                    : 0.1,
              ),
            ),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: xPositiveSpots, // Verwende die sortierte Liste
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            LineChartBarData(
              spots: xNegativeSpots, // Verwende die sortierte Liste
              isCurved: true,
              color: Colors.blue.shade300,
              barWidth: 2,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
              dashArray: [5, 5],
            ),
            LineChartBarData(
              spots: yPositiveSpots, // Verwende die sortierte Liste
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            LineChartBarData(
              spots: yNegativeSpots, // Verwende die sortierte Liste
              isCurved: true,
              color: Colors.green.shade300,
              barWidth: 2,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
              dashArray: [5, 5],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool dashed) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed ? Border.all(color: color, width: 1) : null,
          ),
          child: dashed ? CustomPaint(
            painter: DashedLinePainter(color: color),
          ) : null,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  // NEU: Widget für Live-Kalibrierungs-Anzeige
  Widget _buildLiveCalibrationView() {
    // Zeige "Warten" nur wenn wirklich keine Daten da sind
    if (liveCalibrationData.xPositiveLive.isEmpty &&
        liveCalibrationData.xNegativeLive.isEmpty &&
        liveCalibrationData.yPositiveLive.isEmpty &&
        liveCalibrationData.yNegativeLive.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Verbinde dich mit dem ESP32 VOR dem Neustart,\num die Live-Kalibrierung zu sehen!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  showLiveCalibration = false;
                });
              },
              icon: const Icon(Icons.close),
              label: const Text('Schließen'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade100,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LIVE STARTUP-KALIBRIERUNG',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Firmware: ${liveCalibrationData.firmwareVersion}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  if (liveCalibrationData.isComplete)
                    const Icon(Icons.check_circle, color: Colors.green, size: 32),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: liveCalibrationData.currentProgress / 100.0,
                backgroundColor: Colors.blue.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  liveCalibrationData.isComplete ? Colors.green : Colors.blue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                liveCalibrationData.isComplete
                    ? 'Kalibrierung abgeschlossen!'
                    : '${liveCalibrationData.currentProgress}% - ${_getCurrentStepName()}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),

        // Offsets anzeigen
        if (liveCalibrationData.xOffset != null && liveCalibrationData.yOffset != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Basis-Offset X', style: TextStyle(fontSize: 12)),
                    Text(
                      '${liveCalibrationData.xOffset!.toStringAsFixed(3)} mT',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(
                  width: 1,
                  height: 30,
                  child: Container(
                    color: Colors.grey,
                  ),
                ),
                Column(
                  children: [
                    const Text('Basis-Offset Y', style: TextStyle(fontSize: 12)),
                    Text(
                      '${liveCalibrationData.yOffset!.toStringAsFixed(3)} mT',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // Live-Chart
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildLiveCalibrationChart(),
          ),
        ),

        // Legende
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('X+', Colors.blue, false),
              _buildLegendItem('X-', Colors.blue.shade300, true),
              _buildLegendItem('Y+', Colors.green, false),
              _buildLegendItem('Y-', Colors.green.shade300, true),
            ],
          ),
        ),
      ],
    );
  }

  String _getCurrentStepName() {
    switch (liveCalibrationData.currentCurve) {
      case 'x_pos': return 'X-Achse Positiv';
      case 'x_neg': return 'X-Achse Negativ';
      case 'y_pos': return 'Y-Achse Positiv';
      case 'y_neg': return 'Y-Achse Negativ';
      default: return 'Initialisierung';
    }
  }

  Widget _buildLiveCalibrationChart() {
    // Sammle alle Punkte für Min/Max Berechnung
    List<CalibrationPoint> allPoints = [];
    allPoints.addAll(liveCalibrationData.xPositiveLive);
    allPoints.addAll(liveCalibrationData.xNegativeLive);
    allPoints.addAll(liveCalibrationData.yPositiveLive);
    allPoints.addAll(liveCalibrationData.yNegativeLive);

    if (allPoints.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Warte auf Kalibrierungsdaten...'),
          ],
        ),
      );
    }

    // Finde Min/Max für Y-Achse
    double minDev = 0;
    double maxDev = 0;

    for (var point in allPoints) {
      if (point.mainAxis < minDev) minDev = point.mainAxis;
      if (point.mainAxis > maxDev) maxDev = point.mainAxis;
    }

    double padding = (maxDev - minDev) * 0.1;
    if (padding == 0) padding = 0.1;

    return LineChart(
      LineChartData(
        minY: minDev - padding,
        maxY: maxDev + padding,
        minX: 0,
        maxX: liveCalibrationData.maxPwm.toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (maxDev - minDev) / 5,
          verticalInterval: liveCalibrationData.maxPwm / 8,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('PWM Wert', style: TextStyle(fontSize: 12)),
            axisNameSize: 20,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: liveCalibrationData.maxPwm / 6,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('Abweichung (mT)', style: TextStyle(fontSize: 12)),
            axisNameSize: 30,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          // X-Achse Positiv - DEBUG: Echte ESP32-Daten verwenden
          if (liveCalibrationData.xPositiveLive.isNotEmpty)
            LineChartBarData(
              spots: () {
                List<FlSpot> spots = liveCalibrationData.xPositiveLive.map((p) => FlSpot(
                  p.pwm.toDouble(),
                  p.mainAxis,
                )).toList();
                spots.sort((a, b) => a.x.compareTo(b.x));

                // DEBUG: Log erste 3 Spots für x_pos
                print('DEBUG Chart x_pos: Erste 3 Spots: ${spots.take(3).map((s) => 'PWM=${s.x}, Dev=${s.y}').join(', ')}');

                return spots;
              }(),
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.blue,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(show: false),
            ),
          // X-Achse Negativ - FIX: Stelle sicher, dass die Linie bei 0 beginnt
          if (liveCalibrationData.xNegativeLive.isNotEmpty)
            LineChartBarData(
              spots: () {
                List<FlSpot> spots = liveCalibrationData.xNegativeLive.map((p) => FlSpot(
                  p.pwm.toDouble(),
                  p.mainAxis,
                )).toList();
                spots.sort((a, b) => a.x.compareTo(b.x));

                // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten
                return spots;
              }(),
              isCurved: true,
              color: Colors.blue.shade300,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.blue.shade300,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(show: false),
              dashArray: [5, 5],
            ),
          // Y-Achse Positiv - FIX: Stelle sicher, dass die Linie bei 0 beginnt
          if (liveCalibrationData.yPositiveLive.isNotEmpty)
            LineChartBarData(
              spots: () {
                List<FlSpot> spots = liveCalibrationData.yPositiveLive.map((p) => FlSpot(
                  p.pwm.toDouble(),
                  p.mainAxis,
                )).toList();
                spots.sort((a, b) => a.x.compareTo(b.x));

                // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten
                return spots;
              }(),
              isCurved: true,
              color: Colors.green,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.green,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(show: false),
            ),
          // Y-Achse Negativ - FIX: Stelle sicher, dass die Linie bei 0 beginnt
          if (liveCalibrationData.yNegativeLive.isNotEmpty)
            LineChartBarData(
              spots: () {
                List<FlSpot> spots = liveCalibrationData.yNegativeLive.map((p) => FlSpot(
                  p.pwm.toDouble(),
                  p.mainAxis,
                )).toList();
                spots.sort((a, b) => a.x.compareTo(b.x));

                // Keine künstlichen Punkte hinzufügen - verwende nur echte ESP32-Daten
                return spots;
              }(),
              isCurved: true,
              color: Colors.green.shade300,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.green.shade300,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(show: false),
              dashArray: [5, 5],
            ),
        ],
      ),
    );
  }

  // Erweiterte Kalibrierungs-Seite
  Widget buildCalibrationView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Version Info
            if (espFirmwareVersion.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.memory, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'ESP32 Firmware: $espFirmwareVersion | App: $APP_VERSION',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),

            // Status-Karte
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCalibrated == true ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCalibrated == true ? Colors.green.shade300 : Colors.orange.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCalibrated == true ? Icons.check_circle : Icons.warning,
                    color: isCalibrated == true ? Colors.green : Colors.orange,
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCalibrated == true ? 'Kalibrierung OK' : isCalibrated == null ? 'Prüfe Kalibrierung...' : 'Kalibrierung erforderlich',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isCalibrated == true
                              ? 'Der Sensor ist optimal positioniert.'
                              : 'Bitte führe die Kalibrierung durch.',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Info-Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Automatische Kalibrierung',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• 101 Messpunkte (1% Schritte)\n'
                        '• SCHNELLE & KÜHLE Spulencharakterisierung\n'
                        '• 15 Messungen pro PWM-Stufe\n'
                        '• Batched-Kalibrierung gegen Überhitzung\n'
                        '• 99% PWM-Bereich ausgenutzt\n'
                        '• Kompensiert automatisch im Betrieb\n'
                        '\nERKLÄRUNG DER KURVEN:\n'
                        '• Hauptachsen-Kompensation: Zeigt Magnetfeldabweichung in X/Y-Achse\n'
                        '• Kreuzkopplung: Unerwünschte Beeinflussung der anderen Achse\n'
                        '• Up/Down: Hysterese beim Auf-/Absteigen der PWM-Rampe\n'
                        '• Die Kalibrierung kompensiert alle diese Effekte'
                        '• Läuft bei jedem ESP32-Start (~3 Min)',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // NEU: Live-Kalibrierungs-Button
            if (showLiveCalibration) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.play_circle_filled,
                                color: liveCalibrationData.isCalibrating ? Colors.purple : Colors.green,
                                size: 32),
                            const SizedBox(width: 12),
                            const Text(
                              'Live-Kalibrierung',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              showLiveCalibration = false;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 400,
                      child: _buildLiveCalibrationView(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Kalibrierungs-Download UI basierend auf calibUiState
            if (calibUiState == CalibUiState.ready_for_download) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Kalibrierung abgeschlossen!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Die kompletten Kalibrierungsdaten können jetzt heruntergeladen werden.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: downloadAllCalibrationData,
                      icon: const Icon(Icons.download),
                      label: const Text('Alle Kalibrierungsdaten laden'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ] else if (calibUiState == CalibUiState.downloading) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Lade komplette Kalibrierungsdaten...',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: calibDownloadProgress,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(calibDownloadProgress * 100).toStringAsFixed(1)}% - '
                      '$calibDownloadChunksReceived / $calibDownloadTotalChunks Pakete',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Heruntergeladene Kalibrierungsdaten anzeigen
            if (calibUiState == CalibUiState.download_complete && downloadedCurves.isNotEmpty) ...[
              SizedBox(
                height: 1000, // Viel mehr Platz
                child: _buildDownloadedDataView(),
              ),
              const SizedBox(height: 24),
            ],

            // Sensor-Positionierungs-Button
            ElevatedButton.icon(
              onPressed: () => showCalibrationDialog(),
              icon: const Icon(Icons.settings_input_antenna, size: 28),
              label: const Text('Sensor-Positionierungs-Assistent'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Anleitung
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Sensor-Positionierung:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  _InstructionStep(
                    number: '1',
                    text: 'Nutze den Assistenten zur optimalen Ausrichtung',
                    icon: Icons.assistant,
                  ),
                  SizedBox(height: 8),
                  _InstructionStep(
                    number: '2',
                    text: 'Beobachte Live-Werte während der Tests',
                    icon: Icons.visibility,
                  ),
                  SizedBox(height: 8),
                  _InstructionStep(
                    number: '3',
                    text: 'Justiere den Sensor für minimale Abweichung',
                    icon: Icons.tune,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTuningView() {
    return Stack(
      children: [
        // Die Hauptansicht mit den Tabs
        TabBarView(
          // Deaktiviere das Wischen, wenn die Navigationsleiste eingeklappt ist ODER wenn ein Widget berührt wird
          physics: (_isNavExpanded && !_isAnalysisWidgetBeingTouched)
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          controller: _tabController,
          children: [
            // PID Tuning Tab (bestehender Inhalt wird in eine neue Methode ausgelagert)
            _buildPidTuningTab(),
            // Sensor-Analyse Tab
            AnalysisWorkspacePage(
              sensorHistory: sensorHistory,
              isRecording: isRecording,
              onRecordingChanged: (value) {
                setState(() {
                  isRecording = value;
                });
              },
              displayHistoryLength: _displayHistoryLength,
              onDisplayHistoryLengthChanged: (value) {
                setState(() {
                  _displayHistoryLength = value;
                });
              },
              onExportToCSV: () => exportSensorDataToCSV(),
              onClearHistory: () {
                setState(() {
                  sensorHistory.clear();
                });
              },
              onWidgetTouchChanged: (isTouched) {
                setState(() {
                  _isAnalysisWidgetBeingTouched = isTouched;
                });
              },
            ),
            // Kalibrierungs-Tab
            buildCalibrationView(),
          ],
        ),
        // Pre-render all button states invisibly
        Offstage(
          offstage: true,
          child: Column(
            children: [
              _buildNavButton(Icons.tune, 'PID', 0),
              _buildNavButton(Icons.analytics, 'Analyse', 1),
              _buildNavButton(Icons.build_circle, 'Kalib.', 2),
              _buildNavButton(Icons.tune, 'PID', 1), // Non-selected state
              _buildNavButton(Icons.analytics, 'Analyse', 0), // Non-selected state
              _buildNavButton(Icons.build_circle, 'Kalib.', 0), // Non-selected state
            ],
          ),
        ),
        // Unsere neue, schwimmende und einklappbare Navigationsleiste
        _buildFloatingNavBar(),
      ],
    );
  }
  
  Widget _buildPidTuningTab() {
    // Dieser Code war vorher in der buildTuningView und wird nun hier gekapselt
    return Column(
      children: [
        // NEU: Einklappbarer Status-Bereich
        ExpansionTile(
                    title: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.bluetooth_connected, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'ESP32 Verbunden',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v$espFirmwareVersion',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    initiallyExpanded: isStatusPanelExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        isStatusPanelExpanded = expanded;
                      });
                    },
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Live Sensor-Daten
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStatusIndicator('X-Sensor', '${sensorX.toStringAsFixed(2)} mT', Colors.blue),
                                _buildStatusIndicator('Y-Sensor', '${sensorY.toStringAsFixed(2)} mT', Colors.green),
                                _buildStatusIndicator('Duty 1', duty1.toString(), Colors.orange),
                                _buildStatusIndicator('Duty 2', duty2.toString(), Colors.purple),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Frequenz und Filter
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: loopFrequency < 850 ? Colors.red.shade50 : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: loopFrequency < 850 ? Colors.red.shade300 : Colors.green.shade300,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.speed,
                                            color: loopFrequency < 850 ? Colors.red : Colors.green,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Regelkreis-Frequenz',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                '${loopFrequency.toStringAsFixed(1)} Hz',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: loopFrequency < 850 ? Colors.red : Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: Colors.grey.shade300,
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.bluetooth, color: Colors.blue, size: 20),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'BLE-Datenrate',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                '${bleFrequency.toStringAsFixed(0)} Hz',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: bleFrequency < 100 ? Colors.orange : Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: Colors.grey.shade300,
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.filter_alt, color: Colors.blue, size: 20),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Aktiver Filter',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                _getFilterName(currentFilter),
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (loopFrequency > 0 && loopFrequency < 850) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.warning, color: Colors.orange, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          'Frequenz unter Zielwert (900 Hz)',
                                          style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Buttons
                            Wrap(
                              alignment: WrapAlignment.spaceEvenly, // Behält eine ähnliche Verteilung bei
                              spacing: 8.0, // Horizontaler Abstand zwischen den Buttons
                              runSpacing: 4.0, // Vertikaler Abstand, wenn Buttons umbrechen
                              children: [
                                ElevatedButton.icon(
                                  onPressed: showPresetDialog,
                                  icon: const Icon(Icons.settings_suggest, size: 20),
                                  label: const Text('PID Presets'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Ggf. Padding beibehalten oder anpassen
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: showFilterDialog,
                                  icon: const Icon(Icons.filter_alt, size: 20),
                                  label: const Text('Sensor Filter'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Ggf. Padding beibehalten oder anpassen
                                  ),
                                ),
                                if (isCalibrated == false)
                                  Padding( // Optional: Padding um den IconButton für konsistenten Abstand
                                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                    child: IconButton(
                                      onPressed: () {
                                        _tabController.animateTo(2);
                                      },
                                      icon: const Icon(Icons.warning, color: Colors.orange),
                                      tooltip: 'Kalibrierung fehlt!',
                                    ),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: disconnect,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Ggf. Padding beibehalten oder anpassen
                                  ),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Trennen'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Expanded(
                    child: ListView(
                      children: [
                        // X-ACHSE QUADRANTEN-REGLER
                        ExpansionTile(
                          title: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: const Text(
                              'X-Achse Regler (Vier-Quadranten)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                          backgroundColor: Colors.blue.shade50,
                          collapsedBackgroundColor: Colors.blue.shade50,
                          initiallyExpanded: true,
                          children: [
                            // X-Achse Positive Richtung
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.blue.shade100,
                              child: const Text(
                                'X+ (Positive Richtung)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            buildImprovedPidControl(
                              label: 'Kp X+ (Proportional)',
                              param: 'kpxp',
                              value: kpX_pos,
                              min: 20,
                              max: 200,
                              smallStep: 0.05,
                              largeStep: 1,
                              controller: kpXPosController,
                              onChanged: (value) {
                                setState(() => kpX_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kpxp=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Ki X+ (Integral)',
                              param: 'kixp',
                              value: kiX_pos,
                              min: 0,
                              max: 100,
                              smallStep: 0.1,
                              largeStep: 1,
                              controller: kiXPosController,
                              onChanged: (value) {
                                setState(() => kiX_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kixp=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Kd X+ (Differential)',
                              param: 'kdxp',
                              value: kdX_pos,
                              min: 0,
                              max: 10,
                              smallStep: 0.001,
                              largeStep: 0.01,
                              controller: kdXPosController,
                              onChanged: (value) {
                                setState(() => kdX_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kdxp=$value');
                              },
                            ),
                            
                            // X-Achse Negative Richtung
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.blue.shade100,
                              child: const Text(
                                'X- (Negative Richtung)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            buildImprovedPidControl(
                              label: 'Kp X- (Proportional)',
                              param: 'kpxn',
                              value: kpX_neg,
                              min: 20,
                              max: 200,
                              smallStep: 0.05,
                              largeStep: 1,
                              controller: kpXNegController,
                              onChanged: (value) {
                                setState(() => kpX_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kpxn=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Ki X- (Integral)',
                              param: 'kixn',
                              value: kiX_neg,
                              min: 0,
                              max: 100,
                              smallStep: 0.1,
                              largeStep: 1,
                              controller: kiXNegController,
                              onChanged: (value) {
                                setState(() => kiX_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kixn=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Kd X- (Differential)',
                              param: 'kdxn',
                              value: kdX_neg,
                              min: 0,
                              max: 10,
                              smallStep: 0.001,
                              largeStep: 0.01,
                              controller: kdXNegController,
                              onChanged: (value) {
                                setState(() => kdX_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kdxn=$value');
                              },
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // Y-ACHSE QUADRANTEN-REGLER
                        ExpansionTile(
                          title: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: const Text(
                              'Y-Achse Regler (Vier-Quadranten)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ),
                          backgroundColor: Colors.green.shade50,
                          collapsedBackgroundColor: Colors.green.shade50,
                          initiallyExpanded: true,
                          children: [
                            // Y-Achse Positive Richtung
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.green.shade100,
                              child: const Text(
                                'Y+ (Positive Richtung)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            buildImprovedPidControl(
                              label: 'Kp Y+ (Proportional)',
                              param: 'kpyp',
                              value: kpY_pos,
                              min: 20,
                              max: 200,
                              smallStep: 0.05,
                              largeStep: 1,
                              controller: kpYPosController,
                              onChanged: (value) {
                                setState(() => kpY_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kpyp=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Ki Y+ (Integral)',
                              param: 'kiyp',
                              value: kiY_pos,
                              min: 0,
                              max: 100,
                              smallStep: 0.1,
                              largeStep: 1,
                              controller: kiYPosController,
                              onChanged: (value) {
                                setState(() => kiY_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kiyp=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Kd Y+ (Differential)',
                              param: 'kdyp',
                              value: kdY_pos,
                              min: 0,
                              max: 10,
                              smallStep: 0.001,
                              largeStep: 0.01,
                              controller: kdYPosController,
                              onChanged: (value) {
                                setState(() => kdY_pos = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kdyp=$value');
                              },
                            ),
                            
                            // Y-Achse Negative Richtung
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.green.shade100,
                              child: const Text(
                                'Y- (Negative Richtung)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            buildImprovedPidControl(
                              label: 'Kp Y- (Proportional)',
                              param: 'kpyn',
                              value: kpY_neg,
                              min: 20,
                              max: 200,
                              smallStep: 0.05,
                              largeStep: 1,
                              controller: kpYNegController,
                              onChanged: (value) {
                                setState(() => kpY_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kpyn=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Ki Y- (Integral)',
                              param: 'kiyn',
                              value: kiY_neg,
                              min: 0,
                              max: 100,
                              smallStep: 0.1,
                              largeStep: 1,
                              controller: kiYNegController,
                              onChanged: (value) {
                                setState(() => kiY_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kiyn=$value');
                              },
                            ),
                            buildImprovedPidControl(
                              label: 'Kd Y- (Differential)',
                              param: 'kdyn',
                              value: kdY_neg,
                              min: 0,
                              max: 10,
                              smallStep: 0.001,
                              largeStep: 0.01,
                              controller: kdYNegController,
                              onChanged: (value) {
                                setState(() => kdY_neg = value);
                                _savePidValues();
                                _sendPidCommandDebounced('kdyn=$value');
                              },
                            ),
                          ],
                        ),

                        // START: NEUE KARTE FÜR D-TERM FILTER
                        Container(
                          margin: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: buildImprovedPidControl(
                            label: 'D-Anteil Glättung (Zeitkonstante)',
                            param: 'dtc',
                            value: dFilterTimeConstantS,
                            min: 0.001,
                            max: 0.05,
                            smallStep: 0.0005,
                            largeStep: 0.001,
                            controller: dFilterTimeConstantController,
                            onChanged: (value) {
                              setState(() => dFilterTimeConstantS = value);
                              _savePidValues();
                              _sendPidCommandDebounced('dtc=$value');
                            },
                            // HIER IST DIE UI-VERBESSERUNG:
                            secondaryInfo: Text(
                              '≈ ${dTermCutoffHz.toStringAsFixed(1)} Hz Grenzfrequenz',
                              style: TextStyle(fontSize: 12, color: Colors.purple.shade400, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          child: const Text(
                            'Erhöhen für mehr Glättung (trägere Reaktion), verringern für schnellere Reaktion (mehr Rauschen). Empfehlung: 0.002 - 0.015 s.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        // ENDE: NEUE KARTE FÜR D-TERM FILTER

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              );
  }
  
  Widget _buildFloatingNavBar() {
    final screenSize = MediaQuery.of(context).size;
    final double expandedWidth = screenSize.width - 80;
    final dockThreshold = 50.0; // Pixels from edge to trigger docking
    
    // Handle expanded/collapsed positioning
    if (_isNavExpanded) {
      // When expanded, always show at original position
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 350),
        curve: Curves.fastOutSlowIn,
        bottom: 20,
        left: 40,
        right: 40,
        child: RepaintBoundary(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            clipBehavior: Clip.none,
            child: Container(
              width: expandedWidth,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavButton(Icons.tune, 'PID', 0),
                    _buildNavButton(Icons.analytics, 'Analyse', 1),
                    _buildNavButton(Icons.build_circle, 'Kalib.', 2),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.expand_more,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isNavExpanded = false;
                        });
                      },
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    // Collapsed state - draggable button
    double actualLeft = _fabPosition.dx;
    double actualBottom = _fabPosition.dy;
    
    // Only adjust position on orientation change, not during drag
    if (!_isDragging) {
      // Ensure button stays visible after orientation change
      if (actualLeft > screenSize.width - 60) {
        actualLeft = screenSize.width - 80;
        // Schedule position update after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _fabPosition = Offset(actualLeft, _fabPosition.dy);
            });
          }
        });
      }
      if (actualBottom > screenSize.height - 100) {
        actualBottom = screenSize.height - 120;
        // Schedule position update after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _fabPosition = Offset(_fabPosition.dx, actualBottom);
            });
          }
        });
      }
    }
    
    // Handle docked states
    if (_isDockedLeft) {
      actualLeft = -40 + (_dockProgress * 40); // Slide into edge
    } else if (_isDockedRight) {
      actualLeft = screenSize.width - 20 - (_dockProgress * 40);
    }
    
    return Stack(
      children: [
        // Main floating button
        AnimatedPositioned(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          left: actualLeft,
          bottom: actualBottom,
          child: RepaintBoundary(
            child: GestureDetector(
            onPanStart: (_) {
              _isDragging = true;
              _isDockedLeft = false;
              _isDockedRight = false;
              _dockProgress = 0.0;
            },
            onPanUpdate: (details) {
              // Update position without setState for smooth dragging
              final newX = (_fabPosition.dx + details.delta.dx).clamp(0.0, screenSize.width - 60);
              final newY = (_fabPosition.dy - details.delta.dy).clamp(20.0, screenSize.height - 100);
              
              // Only update if position actually changed
              if (newX != _fabPosition.dx || newY != _fabPosition.dy) {
                setState(() {
                  _fabPosition = Offset(newX, newY);
                });
              }
            },
            onPanEnd: (_) {
              setState(() {
                _isDragging = false;
                
                // Check for docking
                if (_fabPosition.dx < dockThreshold) {
                  _isDockedLeft = true;
                  _animateDocking();
                } else if (_fabPosition.dx > screenSize.width - 60 - dockThreshold) {
                  _isDockedRight = true;
                  _animateDocking();
                }
              });
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: (_isDockedLeft || _isDockedRight) ? 0.3 + (0.7 * (1 - _dockProgress)) : 1.0,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.apps,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    if (_isDockedLeft || _isDockedRight) {
                      setState(() {
                        _isDockedLeft = false;
                        _isDockedRight = false;
                        _dockProgress = 0.0;
                      });
                    } else {
                      setState(() {
                        _isNavExpanded = true;
                      });
                    }
                  },
                ),
              ),
            ),
            ),
          ),
        ),
        
        // Docked edge indicator (small tab)
        if ((_isDockedLeft || _isDockedRight) && _dockProgress > 0.5)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: _isDockedLeft ? 0 : null,
            right: _isDockedRight ? 0 : null,
            bottom: actualBottom.clamp(20.0, screenSize.height - 120) + 15,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isDockedLeft = false;
                  _isDockedRight = false;
                  _dockProgress = 0.0;
                });
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _dockProgress,
                child: Container(
                  width: 12,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(_isDockedRight ? 6 : 0),
                      right: Radius.circular(_isDockedLeft ? 6 : 0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: Offset(_isDockedLeft ? 2 : -2, 0),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isDockedLeft ? Icons.chevron_right : Icons.chevron_left,
                      color: Colors.white.withOpacity(0.5),
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  void _animateDocking() {
    if (_isDockAnimating) return;
    _isDockAnimating = true;
    
    // Animate dock progress
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _dockProgress += 0.05;
        if (_dockProgress >= 1.0) {
          _dockProgress = 1.0;
          _isDockAnimating = false;
          timer.cancel();
        }
      });
    });
  }

  Widget _buildNavButton(IconData icon, String label, int index) {
    bool isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          _tabController.animateTo(index);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 14,
          vertical: 10,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected 
                  ? Colors.white
                  : Colors.white70,
              size: 20,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  IconData _getIconForTab(int index) {
    switch (index) {
      case 0:
        return Icons.tune;
      case 1:
        return Icons.analytics;
      case 2:
        return Icons.build_circle;
      default:
        return Icons.menu;
    }
  }
  
  // Heatmap-Visualisierung für Mix-Grid
  Widget _buildMixGridHeatmap(String title, Map<String, List<List<double>>> mixGrids) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildQuadrantHeatmap('X Q_PP', mixGrids['X_Q_PP'] ?? []),
              _buildQuadrantHeatmap('X Q_NP', mixGrids['X_Q_NP'] ?? []),
              _buildQuadrantHeatmap('X Q_PN', mixGrids['X_Q_PN'] ?? []),
              _buildQuadrantHeatmap('X Q_NN', mixGrids['X_Q_NN'] ?? []),
              _buildQuadrantHeatmap('Y Q_PP', mixGrids['Y_Q_PP'] ?? []),
              _buildQuadrantHeatmap('Y Q_NP', mixGrids['Y_Q_NP'] ?? []),
              _buildQuadrantHeatmap('Y Q_PN', mixGrids['Y_Q_PN'] ?? []),
              _buildQuadrantHeatmap('Y Q_NN', mixGrids['Y_Q_NN'] ?? []),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuadrantHeatmap(String label, List<List<double>> data) {
    if (data.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    // Find min/max values for color mapping
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    for (var row in data) {
      for (var val in row) {
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
      }
    }
    
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: HeatmapPainter(data, minVal, maxVal),
          ),
        ),
      ],
    );
  }
  
  // Widget zur Anzeige der heruntergeladenen Kalibrierungsdaten
  Widget _buildDownloadedDataView() {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kalibrierungsdaten-Analyse',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _exportCalibrationData,
                    icon: const Icon(Icons.save_alt),
                    tooltip: 'Daten exportieren',
                  ),
                ],
              ),
            ),
            
            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: TabBar(
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
                tabs: const [
                  Tab(text: 'Kennlinien', icon: Icon(Icons.show_chart)),
                  Tab(text: 'Mix-Matrix', icon: Icon(Icons.grid_on)),
                ],
              ),
            ),
            
            // Tab Views mit fester Höhe
            SizedBox(
              height: 750, // Viel mehr Höhe für die Diagramme
              child: TabBarView(
                children: [
                  // Tab 1: Kennlinien-Graphen
                  Column(
                    children: [
                      // Legende oben
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildLegendItem('X+ Up', Colors.blue, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('X+ Down', Colors.blue.shade300, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('X- Up', Colors.red, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('X- Down', Colors.red.shade300, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('Y+ Up', Colors.green, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('Y+ Down', Colors.green.shade300, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('Y- Up', Colors.orange, false),
                              const SizedBox(width: 12),
                              _buildLegendItem('Y- Down', Colors.orange.shade300, false),
                            ],
                          ),
                        ),
                      ),
                      // Charts
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            children: [
                              // Hauptachsen-Kennlinien
                              Expanded(
                                child: _buildMainAxisChart(),
                              ),
                              const SizedBox(height: 4),
                              // Kreuzkopplungs-Kennlinien
                              Expanded(
                                child: _buildCrossTalkChart(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Tab 2: Mix-Matrix Heatmaps
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildInteractiveMixMatrixView(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Interaktive Mix-Matrix-Ansicht mit Auswahl-Buttons
  Widget _buildInteractiveMixMatrixView() {
    return StatefulBuilder(
      builder: (context, setState) {
        // Bestimme welche Heatmap angezeigt werden soll
        String heatmapKey = '${selectedMixAxis}_Q_$selectedMixQuadrant';
        List<List<double>> selectedData = downloadedMixGrids[heatmapKey] ?? [];
        
        return Column(
          children: [
            // Auswahlbereich
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Achsenauswahl
                  Row(
                    children: [
                      const Text(
                        'Korrektur-Achse:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: ToggleButtons(
                        isSelected: [selectedMixAxis == 'X', selectedMixAxis == 'Y'],
                        onPressed: (int index) {
                          setState(() {
                            selectedMixAxis = index == 0 ? 'X' : 'Y';
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        selectedBorderColor: Colors.blue,
                        selectedColor: Colors.white,
                        fillColor: Colors.blue,
                        color: Colors.black87,
                        constraints: const BoxConstraints(
                          minHeight: 36.0,
                          minWidth: 60.0,
                        ),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('X-Korr.'),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('Y-Korr.'),
                          ),
                        ],
                      ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Quadrantenauswahl
                  Row(
                    children: [
                      const Text(
                        'Quadrant:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: ToggleButtons(
                          isSelected: [
                            selectedMixQuadrant == 'PP',
                            selectedMixQuadrant == 'NP',
                            selectedMixQuadrant == 'PN',
                            selectedMixQuadrant == 'NN',
                          ],
                          onPressed: (int index) {
                            setState(() {
                              selectedMixQuadrant = ['PP', 'NP', 'PN', 'NN'][index];
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          selectedBorderColor: Colors.blue,
                          selectedColor: Colors.white,
                          fillColor: Colors.blue,
                          color: Colors.black87,
                          constraints: const BoxConstraints(
                            minHeight: 36.0,
                            minWidth: 35.0,
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text('+/+', style: TextStyle(fontSize: 13)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text('+/-', style: TextStyle(fontSize: 13)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text('-/+', style: TextStyle(fontSize: 13)),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text('-/-', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Große Heatmap
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      '$selectedMixAxis-Korrektur Quadrant ${selectedMixQuadrant.replaceAll('P', '+').replaceAll('N', '-')}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (selectedData.isNotEmpty)
                      Column(
                        children: [
                          Text(
                            'Grid-Größe: ${selectedData.length} x ${selectedData.isNotEmpty ? selectedData[0].length : 0}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const Text(
                            'Tippe auf ein Kästchen für Details',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: selectedData.isEmpty
                          ? Center(
                              child: Text(
                                'Keine Daten für $heatmapKey',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  onTapDown: (TapDownDetails details) {
                                    // Berechne welche Zelle angeklickt wurde
                                    final rows = selectedData.length;
                                    final cols = selectedData[0].length;
                                    final cellWidth = constraints.maxWidth / cols;
                                    final cellHeight = constraints.maxHeight / rows;
                                    
                                    final col = (details.localPosition.dx / cellWidth).floor();
                                    final row = (details.localPosition.dy / cellHeight).floor();
                                    
                                    if (row >= 0 && row < rows && col >= 0 && col < cols) {
                                      final value = selectedData[row][col];
                                      final xPwm = (col * 1023 / (cols - 1)).round();
                                      final yPwm = (row * 1023 / (rows - 1)).round();
                                      
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: Text('Grid-Punkt [$row, $col]'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Position: Zeile $row, Spalte $col'),
                                                Text('PWM X: ~$xPwm'),
                                                Text('PWM Y: ~$yPwm'),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Korrekturwert: ${value.toStringAsFixed(3)} mT',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  value > 0 
                                                    ? 'Positive Korrektur (Rot)' 
                                                    : value < 0 
                                                      ? 'Negative Korrektur (Blau)'
                                                      : 'Neutral (Weiß)',
                                                  style: TextStyle(
                                                    color: value > 0 
                                                      ? Colors.red 
                                                      : value < 0 
                                                        ? Colors.blue 
                                                        : Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('OK'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }
                                  },
                                  child: CustomPaint(
                                    size: const Size(double.infinity, double.infinity),
                                    painter: HeatmapPainter(
                                      selectedData,
                                      _getMinValue(selectedData),
                                      _getMaxValue(selectedData),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Legende
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Negativ', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 16),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Neutral', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 16),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.red.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Positiv', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  double _getMinValue(List<List<double>> data) {
    double minVal = double.infinity;
    for (var row in data) {
      for (var val in row) {
        if (val < minVal) minVal = val;
      }
    }
    return minVal;
  }
  
  double _getMaxValue(List<List<double>> data) {
    double maxVal = double.negativeInfinity;
    for (var row in data) {
      for (var val in row) {
        if (val > maxVal) maxVal = val;
      }
    }
    return maxVal;
  }

  // Hauptachsen-Chart (zeigt mainAxis-Werte)
  Widget _buildMainAxisChart() {
    return _buildAxisChart(
      'Hauptachsen-Kompensation',
      ['x_pos_up', 'x_pos_down', 'x_neg_up', 'x_neg_down', 'y_pos_up', 'y_pos_down', 'y_neg_up', 'y_neg_down'],
      'Magnetfeld-Abweichung [mT]',
      true, // mainAxis verwenden
    );
  }
  
  // Kreuzkopplungs-Chart (zeigt crossAxis-Werte)
  Widget _buildCrossTalkChart() {
    return _buildAxisChart(
      'Kreuzkopplung',
      ['x_pos_up', 'x_pos_down', 'x_neg_up', 'x_neg_down', 'y_pos_up', 'y_pos_down', 'y_neg_up', 'y_neg_down'],
      'Störfeld [mT]',
      false, // crossAxis verwenden
    );
  }
  
  // Generische Chart-Funktion für beide Achsen
  Widget _buildAxisChart(String title, List<String> curveNames, String yAxisLabel, bool useMainAxis) {
    // --- START DEBUG-LOG ---
    // Debug output removed - graphs are working correctly now
    
    final List<LineChartBarData> lineBarsData = [];
    final colors = [
      Colors.blue, Colors.blue.shade300, Colors.red, Colors.red.shade300,
      Colors.green, Colors.green.shade300, Colors.orange, Colors.orange.shade300
    ];
    
    for (int i = 0; i < curveNames.length; i++) {
      final curveName = curveNames[i];
      if (downloadedCurves.containsKey(curveName)) {
        final curvePointsList = downloadedCurves[curveName]!;
        
        // Schritt 1: Konvertiere zu FlSpot und filtere PWM=0 (außer dem allerersten Punkt)
        List<FlSpot> spots = [];
        for (int pointIdx = 0; pointIdx < curvePointsList.length; pointIdx++) {
          final p = curvePointsList[pointIdx];
          bool isFirstPoint = pointIdx == 0;
          bool hasValidPwm = p.pwm != 0;
          bool hasValidYValue = useMainAxis ? p.mainAxis.abs() > 1e-6 : p.crossAxis.abs() > 1e-6; // Toleranz für Fließkomma

          if (isFirstPoint || hasValidPwm || hasValidYValue) { // Ersten Punkt immer behalten, oder wenn PWM nicht 0 oder Y-Wert nicht 0
            spots.add(FlSpot(
              p.pwm.toDouble(),
              useMainAxis ? p.mainAxis : p.crossAxis,
            ));
          }
        }
        
        // Schritt 2: Entferne aufeinanderfolgende Duplikate basierend auf X-Wert (PWM)
        // Behalte den LETZTEN Punkt bei gleichem X-Wert
        if (spots.isNotEmpty) {
          Map<double, FlSpot> uniqueXSpots = {};
          for (var spot in spots) {
            uniqueXSpots[spot.x] = spot; // Überschreibt frühere Einträge mit demselben X
          }
          spots = uniqueXSpots.values.toList();
        }
        
        // Schritt 3: Sortiere die bereinigten Spots nach X-Wert (PWM)
        spots.sort((a, b) => a.x.compareTo(b.x));
        
        // Debug output removed - data processing working correctly
        
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: false, // Exakte Geraden für präzise Analyse
            color: colors[i % colors.length],
            barWidth: 3,  // Dickere Linien für bessere Sichtbarkeit
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),  // Keine Datenpunkte für sauberere Darstellung
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 600,  // Viel höher für bessere Analyse!
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Container(
              width: 1800,  // Breiter für bessere Analyse
              height: 600,  // Volle Höhe nutzen
              padding: const EdgeInsets.all(10),
              child: LineChart(
                LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: 0.5,   // Weniger Linien
                      verticalInterval: 100,     // Nur bei 100er Schritten
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.shade300,
                          strokeWidth: 1,
                        );
                      },
                      getDrawingVerticalLine: (value) {
                        return FlLine(
                          color: Colors.grey.shade300,
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 35,
                          interval: 100,  // Weniger aber klarere Beschriftungen
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        axisNameWidget: const Text('PWM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        axisNameSize: 18,
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 0.5,  // Weniger Beschriftungen
                          reservedSize: 50,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        axisNameWidget: Text(
                          yAxisLabel, 
                          style: const TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        axisNameSize: 20,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: Colors.grey.shade600,
                        width: 2,
                      ),
                    ),
                    backgroundColor: Colors.grey.shade50,
                    lineBarsData: lineBarsData,
                    lineTouchData: const LineTouchData(
                      enabled: false,
                    ),
                    // Bereich-Highlights für wichtige Zonen
                    rangeAnnotations: RangeAnnotations(
                      horizontalRangeAnnotations: [
                        HorizontalRangeAnnotation(
                          y1: -0.1,
                          y2: 0.1,
                          color: Colors.green.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Hilfsfunktion für Kennlinien-Charts
  Widget _buildCurvesChart(String title, List<String> curveNames, String yAxisLabel) {
    final List<LineChartBarData> lineBarsData = [];
    final colors = [Colors.blue, Colors.blue.shade300, Colors.red, Colors.red.shade300];
    
    for (int i = 0; i < curveNames.length; i++) {
      final curveName = curveNames[i];
      if (downloadedCurves.containsKey(curveName)) {
        final curve = downloadedCurves[curveName]!;
        final spots = curve.asMap().entries.map((entry) {
          return FlSpot(
            entry.value.pwm.toDouble(),
            entry.value.mainAxis,
          );
        }).toList();
        
        lineBarsData.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: colors[i % colors.length],
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 600,  // Viel höher für bessere Analyse!
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Container(
                width: 1800,  // Breiter für bessere Analyse
                height: 600,  // Volle Höhe nutzen
                padding: const EdgeInsets.all(10),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: 0.5,   // Weniger Linien
                      verticalInterval: 100,     // Nur bei 100er Schritten
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.shade300,
                          strokeWidth: 1,
                        );
                      },
                      getDrawingVerticalLine: (value) {
                        return FlLine(
                          color: Colors.grey.shade300,
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 35,
                          interval: 100,  // Weniger aber klarere Beschriftungen
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        axisNameWidget: const Text('PWM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        axisNameSize: 18,
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 0.5,  // Weniger Beschriftungen
                          reservedSize: 50,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        axisNameWidget: Text(
                          yAxisLabel, 
                          style: const TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        axisNameSize: 20,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: Colors.grey.shade600,
                        width: 2,
                      ),
                    ),
                    backgroundColor: Colors.grey.shade50,
                    lineBarsData: lineBarsData,
                    lineTouchData: const LineTouchData(
                      enabled: false,
                    ),
                    // Bereich-Highlights für wichtige Zonen
                    rangeAnnotations: RangeAnnotations(
                      horizontalRangeAnnotations: [
                        HorizontalRangeAnnotation(
                          y1: -0.1,
                          y2: 0.1,
                          color: Colors.green.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Kompakte Legende
        SizedBox(
          height: 30,
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: curveNames.asMap().entries.map((entry) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 2,
                    color: colors[entry.key % colors.length],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    entry.value,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
      ),
    );
  }
  
  Future<void> _exportCalibrationData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/calibration_data_${DateTime.now().millisecondsSinceEpoch}.json');
      
      final exportData = {
        'timestamp': DateTime.now().toIso8601String(),
        'curves': downloadedCurves.map((key, value) => MapEntry(key, 
          value.map((p) => {'pwm': p.pwm, 'mainAxis': p.mainAxis, 'crossAxis': p.crossAxis}).toList()
        )),
        'mixGrids': downloadedMixGrids,
      };
      
      await file.writeAsString(jsonEncode(exportData));
      
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Kalibrierungsdaten Export',
      );
    } catch (e) {
      showError('Export fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: connectedDevice == null ? buildScanView() : buildTuningView(),
      ),
    );
  }
}

// Hilfs-Widget für Anleitung
class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;
  final IconData icon;

  const _InstructionStep({
    Key? key,
    required this.number,
    required this.text,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// Custom Painter für Gitter
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    // Vertikale Linien
    for (int i = 1; i < 5; i++) {
      double x = size.width * (i / 5);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontale Linien
    for (int i = 1; i < 5; i++) {
      double y = size.height * (i / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Mittellinie stärker
    paint.strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// NEU: Custom Painter für gestrichelte Linie
class DashedLinePainter extends CustomPainter {
  final Color color;

  DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;

    double dashWidth = 5;
    double dashSpace = 3;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Heatmap Painter für Mix-Grid Visualisierung
class HeatmapPainter extends CustomPainter {
  final List<List<double>> data;
  final double minValue;
  final double maxValue;
  
  HeatmapPainter(this.data, this.minValue, this.maxValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || data[0].isEmpty) return;
    
    final rows = data.length;
    final cols = data[0].length;
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;
    
    // Find the maximum absolute value for better color scaling
    double maxAbsValue = 0;
    for (var row in data) {
      for (var val in row) {
        if (val.abs() > maxAbsValue) {
          maxAbsValue = val.abs();
        }
      }
    }
    
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        final value = data[i][j];
        
        Color color;
        if (maxAbsValue == 0) {
          // Everything is zero, use neutral color
          color = Colors.grey.shade200;
        } else {
          // Normalize value from -1 to +1 based on max absolute value
          final normalizedValue = value / maxAbsValue;
          
          if (value.abs() < 0.01 * maxAbsValue) {
            // Very close to zero - use white/neutral color (good calibration)
            color = Colors.white;
          } else if (value > 0) {
            // Positive values: White -> Red
            // Use more gradual transition for better visualization
            final intensity = value.abs() / maxAbsValue;
            color = Color.lerp(Colors.white, Colors.red, intensity * 0.8)!;
          } else {
            // Negative values: White -> Blue
            // Use more gradual transition for better visualization
            final intensity = value.abs() / maxAbsValue;
            color = Color.lerp(Colors.white, Colors.blue, intensity * 0.8)!;
          }
        }
        
        final rect = Rect.fromLTWH(
          j * cellWidth,
          i * cellHeight,
          cellWidth,
          cellHeight,
        );
        
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        
        canvas.drawRect(rect, paint);
        
        // Draw grid lines
        final gridPaint = Paint()
          ..color = Colors.grey.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        
        canvas.drawRect(rect, gridPaint);
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant HeatmapPainter oldDelegate) => 
      oldDelegate.data != data || 
      oldDelegate.minValue != minValue || 
      oldDelegate.maxValue != maxValue;
}

// =============================================================
// APP VERSION: v12.1
// =============================================================
// NEUE FEATURES & ANPASSUNGEN:
//
// 1. EINKLAPPBARER STATUS-BEREICH:
//    - Status-Panel im PID Tuning Screen kann eingeklappt werden
//    - Spart Bildschirmplatz für die PID-Regler
//    - Zeigt kompakt Verbindungsstatus und Version
//
// 2. VERBESSERTE Y-ACHSEN-BESCHRIFTUNG:
//    - Dynamische Anpassung der Intervalle je nach Wertebereich
//    - Automatische Dezimalstellen-Anpassung
//    - Mehr Platz für Y-Achsen-Labels (60px)
//    - Verhindert Überlappung bei großen/kleinen Werten
//
// 3. VERSIONSANZEIGE IN APP-BAR:
//    - App-Version und ESP-Firmware-Version immer sichtbar
//    - Kompakte Darstellung in der Titelleiste
//    - Zeigt "App vX.X | ESP vX.X" wenn verbunden
//
// 4. OPTIMIERTE UI:
//    - Kleinere Buttons im Status-Bereich
//    - Bessere Platznutzung
//    - Responsive Layout-Anpassungen
// =============================================================



