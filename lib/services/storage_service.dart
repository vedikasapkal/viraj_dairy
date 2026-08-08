// =============================================================================
// STORAGE SERVICE (lib/services/storage_service.dart)
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';

class StorageService {
  /// Converts captured image bytes directly into a cross-platform base64 data URI 
  /// so that it renders instantly and reliably on both the Delivery and Admin dashboards.
  static Future<String> uploadBytesDeliveryProof({
    required String orderId,
    required Uint8List imageBytes,
  }) async {
    try {
      final String base64Image = base64Encode(imageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';
      return dataUri;
    } catch (e) {
      debugPrint('Storage Service error: $e');
      return '';
    }
  }

  /// Fallback compatibility method if a local file path string is passed instead of bytes
  static Future<String> uploadDeliveryProof({
    required String orderId,
    required String localFilePath,
  }) async {
    return localFilePath;
  }
}