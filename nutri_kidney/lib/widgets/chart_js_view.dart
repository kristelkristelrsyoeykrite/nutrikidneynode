import 'dart:convert';

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
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    _loadChart();
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
    return _controller.loadHtmlString(_buildHtml());
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
    return SizedBox(
      height: widget.height,
      child: WebViewWidget(controller: _controller),
    );
  }
}
