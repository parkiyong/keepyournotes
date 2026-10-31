import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/note_model.dart';

class DrawingCanvasResult {
  final String filePath;
  final List<DrawingStroke> strokes;
  final String gridType;

  const DrawingCanvasResult({
    required this.filePath,
    required this.strokes,
    required this.gridType,
  });
}

class DrawingCanvasScreen extends StatefulWidget {
  final List<DrawingStroke> initialStrokes;
  final String initialGrid;

  const DrawingCanvasScreen({
    super.key,
    this.initialStrokes = const [],
    this.initialGrid = 'dots',
  });

  @override
  State<DrawingCanvasScreen> createState() => _DrawingCanvasScreenState();
}

class _DrawingCanvasScreenState extends State<DrawingCanvasScreen> {
  static const _uuid = Uuid();
  late List<DrawingStroke> _strokes;
  final List<DrawingStroke> _redoStack = [];
  List<Offset> _activePoints = [];

  String _selectedTool = 'pen'; // 'pen', 'marker', 'highlighter', 'eraser'
  Color _selectedColor = const Color(0xFF202124);
  double _strokeWidth = 4.0;
  late String _gridType; // 'none', 'dots', 'lines', 'grid'
  Size _canvasSize = const Size(800, 1000);
  bool _isSaving = false;

  static const List<Color> _brushColors = [
    Color(0xFF202124),
    Color(0xFFD93025),
    Color(0xFFF29900),
    Color(0xFFFBBC04),
    Color(0xFF1E8E3E),
    Color(0xFF1A73E8),
    Color(0xFF9334E6),
    Color(0xFFE52592),
    Color(0xFF795548),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _strokes = List<DrawingStroke>.from(widget.initialStrokes);
    _gridType = widget.initialGrid;
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _redoStack.clear();
      _activePoints = [details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _activePoints = [..._activePoints, details.localPosition];
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activePoints.isEmpty) return;
    setState(() {
      _strokes.add(
        DrawingStroke(
          points: _activePoints,
          colorValue: _selectedTool == 'eraser'
              ? const Color(0xFFFFFFFF).toARGB32()
              : _selectedColor.toARGB32(),
          strokeWidth: _effectiveWidth(),
          tool: _selectedTool,
        ),
      );
      _activePoints = [];
    });
  }

  double _effectiveWidth() {
    switch (_selectedTool) {
      case 'marker':
        return _strokeWidth * 2.0;
      case 'highlighter':
        return _strokeWidth * 3.8;
      case 'eraser':
        return _strokeWidth * 4.5;
      default:
        return _strokeWidth;
    }
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStack.add(_strokes.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _strokes.add(_redoStack.removeLast());
    });
  }

  void _clearCanvas() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStack.clear();
      _strokes.clear();
    });
  }

  Future<void> _saveDrawing() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final recorder = ui.PictureRecorder();
      final width = _canvasSize.width.clamp(400.0, 2000.0);
      final height = _canvasSize.height.clamp(400.0, 2400.0);
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      final painter = _KeepDrawingPainter(
        strokes: _strokes,
        activePoints: const [],
        activeColor: _selectedColor,
        activeWidth: _effectiveWidth(),
        activeTool: _selectedTool,
        gridType: _gridType,
      );
      painter.paint(canvas, Size(width, height));

      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      Directory targetDir;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        targetDir = Directory(p.join(appDir.path, 'keep_media'));
      } catch (_) {
        targetDir = Directory.systemTemp;
      }
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final file = File(p.join(targetDir.path, 'drawing_${_uuid.v4()}.png'));
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      Navigator.of(context).pop(
        DrawingCanvasResult(
          filePath: file.path,
          strokes: _strokes,
          gridType: _gridType,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text('Drawing'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _strokes.isNotEmpty ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            icon: const Icon(Icons.redo),
          ),
          PopupMenuButton<String>(
            tooltip: 'Canvas Grid & Options',
            onSelected: (value) {
              if (value == 'clear') {
                _clearCanvas();
              } else {
                setState(() => _gridType = value);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'dots',
                child: Text('Dots grid'),
              ),
              const PopupMenuItem(
                value: 'lines',
                child: Text('Ruled lines'),
              ),
              const PopupMenuItem(
                value: 'grid',
                child: Text('Square grid'),
              ),
              const PopupMenuItem(
                value: 'none',
                child: Text('Blank canvas'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear canvas'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              key: const Key('save_drawing_button'),
              onPressed: _isSaving ? null : _saveDrawing,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  key: const Key('drawing_gesture_area'),
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _KeepDrawingPainter(
                        strokes: _strokes,
                        activePoints: _activePoints,
                        activeColor: _selectedColor,
                        activeWidth: _effectiveWidth(),
                        activeTool: _selectedTool,
                        gridType: _gridType,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildBottomToolBar(),
        ],
      ),
    );
  }

  Widget _buildBottomToolBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tool selector row + width slider
            Row(
              children: [
                _ToolButton(
                  icon: Icons.edit_outlined,
                  label: 'Pen',
                  isSelected: _selectedTool == 'pen',
                  onTap: () => setState(() => _selectedTool = 'pen'),
                ),
                _ToolButton(
                  icon: Icons.brush_outlined,
                  label: 'Marker',
                  isSelected: _selectedTool == 'marker',
                  onTap: () => setState(() => _selectedTool = 'marker'),
                ),
                _ToolButton(
                  icon: Icons.border_color_outlined,
                  label: 'Highlight',
                  isSelected: _selectedTool == 'highlighter',
                  onTap: () => setState(() => _selectedTool = 'highlighter'),
                ),
                _ToolButton(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Eraser',
                  isSelected: _selectedTool == 'eraser',
                  onTap: () => setState(() => _selectedTool = 'eraser'),
                ),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 1.5,
                    max: 12.0,
                    onChanged: (val) => setState(() => _strokeWidth = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Color palette row
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _brushColors.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final color = _brushColors[index];
                  final isSelected = _selectedColor == color &&
                      _selectedTool != 'eraser';
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                        if (_selectedTool == 'eraser') {
                          _selectedTool = 'pen';
                        }
                      });
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.grey.shade400,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFE8F0FE)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? const Color(0xFF1A73E8)
                    : Colors.black87,
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFF1A73E8)
                      : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepDrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset> activePoints;
  final Color activeColor;
  final double activeWidth;
  final String activeTool;
  final String gridType;

  _KeepDrawingPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.activeWidth,
    required this.activeTool,
    required this.gridType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. White paper background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // 2. Grid pattern
    _paintGrid(canvas, size);

    // 3. Committed strokes
    for (final stroke in strokes) {
      _paintStroke(
        canvas,
        stroke.points,
        Color(stroke.colorValue),
        stroke.strokeWidth,
        stroke.tool,
      );
    }

    // 4. Active stroke in progress
    if (activePoints.isNotEmpty) {
      _paintStroke(
        canvas,
        activePoints,
        activeTool == 'eraser' ? Colors.white : activeColor,
        activeWidth,
        activeTool,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (gridType == 'none') return;
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1.0;

    const step = 28.0;
    if (gridType == 'lines' || gridType == 'grid') {
      for (double y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
    if (gridType == 'grid') {
      for (double x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
    }
    if (gridType == 'dots') {
      final dotPaint = Paint()
        ..color = const Color(0xFFBDBDBD)
        ..style = PaintingStyle.fill;
      for (double y = step; y < size.height; y += step) {
        for (double x = step; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 1.4, dotPaint);
        }
      }
    }
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
    String tool,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = tool == 'highlighter'
          ? color.withValues(alpha: 0.35)
          : (tool == 'marker' ? color.withValues(alpha: 0.82) : color)
      ..strokeWidth = width
      ..strokeCap = tool == 'highlighter' ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _KeepDrawingPainter oldDelegate) => true;
}
