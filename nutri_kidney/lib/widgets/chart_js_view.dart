import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ChartJsView extends StatefulWidget {
  final String chartType;
  final Map<String, dynamic> data;
  final Map<String, dynamic> options;
  final double height;

  const ChartJsView({
    super.key,
    required this.chartType,
    required this.data,
    required this.options,
    this.height = 220,
  });

  @override
  State<ChartJsView> createState() => _ChartJsViewState();
}

class _ChartJsViewState extends State<ChartJsView> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000));
      _loadChart();
    }
  }

  @override
  void didUpdateWidget(covariant ChartJsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chartType != widget.chartType ||
        jsonEncode(oldWidget.data) != jsonEncode(widget.data) ||
        jsonEncode(oldWidget.options) != jsonEncode(widget.options)) {
      _loadChart();
    }
  }

  Future<void> _loadChart() {
    if (kIsWeb) return Future.value();
    return _controller!.loadHtmlString(_buildHtml());
  }

  String _buildHtml() {
    final config = jsonEncode({
      'type': widget.chartType,
      'data': widget.data,
      'options': widget.options,
    });

    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent;
        overflow: hidden;
      }
      #chart-wrap {
        width: 100%;
        height: 100vh;
      }
      #chart {
        width: 100%;
        height: 100%;
      }
    </style>
  </head>
  <body>
    <div id="chart-wrap">
      <canvas id="chart"></canvas>
    </div>
    <script>
      const config = $config;
      const ctx = document.getElementById('chart').getContext('2d');
      new Chart(ctx, config);
    </script>
  </body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _NativeChartPainter(
            chartType: widget.chartType,
            data: widget.data,
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: WebViewWidget(controller: _controller!),
    );
  }
}

class _NativeChartPainter extends CustomPainter {
  final String chartType;
  final Map<String, dynamic> data;

  const _NativeChartPainter({
    required this.chartType,
    required this.data,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final datasets = _datasets;
    if (datasets.isEmpty || size.width <= 0 || size.height <= 0) return;

    if (chartType == 'doughnut') {
      _paintDoughnut(canvas, size, datasets.first);
      return;
    }

    _paintCartesian(canvas, size, datasets);
  }

  void _paintCartesian(
    Canvas canvas,
    Size size,
    List<Map<String, dynamic>> datasets,
  ) {
    final allValues = datasets
        .expand((dataset) => _numbers(dataset['data']))
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (allValues.isEmpty) return;

    final maxValue = math.max(1.0, allValues.reduce(math.max));
    final chartRect = Rect.fromLTWH(30, 8, size.width - 36, size.height - 34);
    final gridPaint = Paint()
      ..color = const Color(0xFFE6ECEF)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFFE0E7EA)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i += 1) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }
    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      axisPaint,
    );

    final barDatasets = datasets
        .where((dataset) => dataset['type'] != 'line' && chartType == 'bar')
        .toList(growable: false);
    final lineDatasets = datasets
        .where((dataset) => chartType == 'line' || dataset['type'] == 'line')
        .toList(growable: false);

    if (barDatasets.isNotEmpty) {
      _paintBars(canvas, chartRect, barDatasets, maxValue);
    }
    if (lineDatasets.isNotEmpty) {
      for (final dataset in lineDatasets) {
        _paintLine(canvas, chartRect, dataset, maxValue);
      }
    }
  }

  void _paintBars(
    Canvas canvas,
    Rect rect,
    List<Map<String, dynamic>> datasets,
    double maxValue,
  ) {
    final pointCount = datasets
        .map((dataset) => _numbers(dataset['data']).length)
        .fold<int>(0, math.max);
    if (pointCount == 0) return;

    final groupWidth = rect.width / pointCount;
    final barWidth = math.min(18.0, (groupWidth * 0.72) / datasets.length);

    for (var datasetIndex = 0; datasetIndex < datasets.length; datasetIndex += 1) {
      final dataset = datasets[datasetIndex];
      final values = _numbers(dataset['data']);
      final colors = _colors(dataset['backgroundColor'], values.length);
      for (var i = 0; i < values.length; i += 1) {
        final value = values[i].clamp(0, maxValue);
        final height = rect.height * value / maxValue;
        final centerX = rect.left + groupWidth * i + groupWidth / 2;
        final x = centerX -
            (barWidth * datasets.length) / 2 +
            datasetIndex * barWidth;
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, rect.bottom - height, barWidth * 0.82, height),
          const Radius.circular(5),
        );
        canvas.drawRRect(
          barRect,
          Paint()..color = colors[i],
        );
      }
    }
  }

  void _paintLine(
    Canvas canvas,
    Rect rect,
    Map<String, dynamic> dataset,
    double maxValue,
  ) {
    final values = _numbers(dataset['data']);
    if (values.isEmpty) return;

    final color = _color(dataset['borderColor'] ?? dataset['backgroundColor']);
    final fill = dataset['fill'] == true;
    final pointCount = math.max(1, values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i += 1)
        Offset(
          rect.left + rect.width * i / pointCount,
          rect.bottom - rect.height * values[i].clamp(0, maxValue) / maxValue,
        ),
    ];

    if (fill && points.length > 1) {
      final fillPath = Path()..moveTo(points.first.dx, rect.bottom);
      for (final point in points) {
        fillPath.lineTo(point.dx, point.dy);
      }
      fillPath
        ..lineTo(points.last.dx, rect.bottom)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = color.withOpacity(0.16));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    if ((dataset['pointRadius'] ?? 3) != 0) {
      final pointPaint = Paint()..color = color;
      for (final point in points) {
        canvas.drawCircle(point, 3, pointPaint);
      }
    }
  }

  void _paintDoughnut(Canvas canvas, Size size, Map<String, dynamic> dataset) {
    final values = _numbers(dataset['data']);
    if (values.isEmpty) return;

    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final colors = _colors(dataset['backgroundColor'], values.length);
    final shortest = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: shortest * 0.72,
      height: shortest * 0.72,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i += 1) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..strokeWidth = shortest * 0.16
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  List<Map<String, dynamic>> get _datasets {
    final raw = data['datasets'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((dataset) => Map<String, dynamic>.from(dataset))
        .toList(growable: false);
  }

  List<double> _numbers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) {
          if (value is num) return value.toDouble();
          return double.tryParse(value?.toString() ?? '') ?? 0;
        })
        .toList(growable: false);
  }

  List<Color> _colors(dynamic raw, int count) {
    if (raw is List) {
      final parsed = raw.map(_color).toList(growable: false);
      if (parsed.isNotEmpty) {
        return [
          for (var i = 0; i < count; i += 1) parsed[i % parsed.length],
        ];
      }
    }
    final color = _color(raw);
    return List<Color>.filled(count, color);
  }

  Color _color(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (value != null) return Color(value);
    }
    final rgba = RegExp(r'rgba?\(([^)]+)\)').firstMatch(text);
    if (rgba != null) {
      final parts = rgba
          .group(1)!
          .split(',')
          .map((part) => part.trim())
          .toList(growable: false);
      if (parts.length >= 3) {
        final r = int.tryParse(parts[0]) ?? 0;
        final g = int.tryParse(parts[1]) ?? 0;
        final b = int.tryParse(parts[2]) ?? 0;
        final a = parts.length >= 4
            ? ((double.tryParse(parts[3]) ?? 1) * 255).round()
            : 255;
        return Color.fromARGB(a.clamp(0, 255), r, g, b);
      }
    }
    return const Color(0xFF42A5F5);
  }

  @override
  bool shouldRepaint(covariant _NativeChartPainter oldDelegate) {
    return oldDelegate.chartType != chartType ||
        jsonEncode(oldDelegate.data) != jsonEncode(data);
  }
}
