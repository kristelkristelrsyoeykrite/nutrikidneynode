import 'dart:async';
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'analytics.dart';
import 'dashboard.dart';
import 'health_metrics.dart';
import 'profile.dart'; // Ensure Profile is imported
import 'responsive_navigation.dart';
import '../services/api_service.dart';

part 'food_log/food_item.dart';
part 'food_log/food_log_page.dart';
