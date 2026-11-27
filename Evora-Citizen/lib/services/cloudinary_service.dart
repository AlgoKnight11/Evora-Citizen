import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import 'logging_service.dart';

/// Service for uploading photos directly to Cloudinary using an unsigned preset.
/// Automatically strips EXIF/GPS metadata and delivers optimized images via CDN.
class CloudinaryService {
  static final http.Client _client = http.Client();

  /// Uploads an image file to Cloudinary.
  ///
  /// [imageFile] - The local file to upload.
  /// [folder] - Optional subfolder tag (e.g. 'civic_reports', 'missions').
  ///
  /// Returns the secure HTTPS URL of the uploaded image.
  static Future<UploadResult> uploadImage(
    File imageFile, {
    String folder = 'civic_evidence',
  }) async {
    final correlationId = LoggingService.generateCorrelationId();
    LoggingService.logBreadcrumb(
      'Uploading image to Cloudinary (size: ${await imageFile.length()} bytes, tag: $folder)',
      correlationId: correlationId,
    );

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConstants.cloudinaryUploadUrl),
      );

      // Unsigned upload parameters
      request.fields['upload_preset'] = AppConstants.cloudinaryUploadPreset;
      request.fields['folder'] = folder;

      // Attach file
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
      );
      request.files.add(multipartFile);

      final streamedResponse = await _client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Image upload timed out after 30 seconds.');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final String secureUrl = responseData['secure_url'] as String;
        final String publicId = responseData['public_id'] as String;

        LoggingService.logBreadcrumb(
          'Image uploaded successfully: $publicId',
          correlationId: correlationId,
        );

        return UploadResult.success(
          url: secureUrl,
          publicId: publicId,
          correlationId: correlationId,
        );
      } else {
        LoggingService.logError(
          'Cloudinary upload failed: ${response.statusCode} - ${response.body}',
          correlationId: correlationId,
        );
        return UploadResult.failure(
          'Upload failed (${response.statusCode}): ${response.reasonPhrase}',
          correlationId: correlationId,
        );
      }
    } catch (e, stackTrace) {
      LoggingService.logError(
        'Cloudinary upload exception: $e',
        stackTrace: stackTrace,
        correlationId: correlationId,
      );
      return UploadResult.failure(
        'Failed to upload image. Please check your internet connection.',
        correlationId: correlationId,
      );
    }
  }

  /// Extracts the Cloudinary public_id from a secure URL or path.
  /// Handles formats such as:
  /// - `https://res.cloudinary.com/.../image/upload/v12345/civic_flow_cases/sample.jpg` -> `civic_flow_cases/sample`
  /// - `https://res.cloudinary.com/.../image/upload/civic_flow_cases/sample.png` -> `civic_flow_cases/sample`
  /// - Raw public ID: `civic_flow_cases/sample` -> `civic_flow_cases/sample`
  static String? extractPublicId(String urlOrPublicId) {
    final trimmed = urlOrPublicId.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      // Already a public_id (strip extension if present)
      final dotIndex = trimmed.lastIndexOf('.');
      return dotIndex != -1 ? trimmed.substring(0, dotIndex) : trimmed;
    }

    try {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      final path = uri.path;
      final uploadMarker = '/upload/';
      final uploadIndex = path.indexOf(uploadMarker);
      if (uploadIndex == -1) return null;

      var segment = path.substring(uploadIndex + uploadMarker.length);
      // Strip optional version prefix e.g. "v1731678910/"
      if (RegExp(r'^v\d+/').hasMatch(segment)) {
        segment = segment.substring(segment.indexOf('/') + 1);
      }
      // Strip file extension
      final dotIndex = segment.lastIndexOf('.');
      if (dotIndex != -1) {
        segment = segment.substring(0, dotIndex);
      }
      return segment.isNotEmpty ? segment : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes an image from Cloudinary given its public_id or full URL.
  /// When CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET are present, executes
  /// a signed destroy call to Cloudinary.
  /// Returns `true` if deletion succeeds or is gracefully disassociated.
  static Future<bool> deleteImage(String imageUrlOrPublicId) async {
    final publicId = extractPublicId(imageUrlOrPublicId) ?? imageUrlOrPublicId.trim();
    if (publicId.isEmpty) return false;

    final correlationId = LoggingService.generateCorrelationId();
    LoggingService.logBreadcrumb(
      'Attempting Cloudinary image deletion for: $publicId',
      correlationId: correlationId,
    );

    final apiKey = AppConstants.cloudinaryApiKey;
    final apiSecret = AppConstants.cloudinaryApiSecret;

    try {
      if (apiKey != null && apiKey.isNotEmpty && apiSecret != null && apiSecret.isNotEmpty) {
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        // SHA-1 signature format: public_id=<public_id>&timestamp=<timestamp><api_secret>
        final toSign = 'public_id=$publicId&timestamp=$timestamp$apiSecret';
        final signature = sha1.convert(utf8.encode(toSign)).toString();

        final response = await _client.post(
          Uri.parse(AppConstants.cloudinaryDestroyUrl),
          body: {
            'public_id': publicId,
            'timestamp': timestamp,
            'api_key': apiKey,
            'signature': signature,
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final Map<String, dynamic> data = json.decode(response.body);
          final result = data['result'] == 'ok';
          LoggingService.logBreadcrumb(
            'Cloudinary asset deleted successfully: $publicId (result: ${data["result"]})',
            correlationId: correlationId,
          );
          return result;
        } else {
          LoggingService.logError(
            'Cloudinary destroy endpoint responded with ${response.statusCode}: ${response.body}',
            correlationId: correlationId,
          );
          return false;
        }
      } else {
        // Without secret, media reference is unlinked from grievance record
        LoggingService.logBreadcrumb(
          'Cloudinary secret not configured client-side; asset reference $publicId disassociated from civic records.',
          correlationId: correlationId,
        );
        return true;
      }
    } catch (e, stackTrace) {
      LoggingService.logError(
        'Cloudinary deletion exception for $publicId: $e',
        stackTrace: stackTrace,
        correlationId: correlationId,
      );
      return false;
    }
  }
}

/// Result envelope for Cloudinary uploads
class UploadResult {
  final bool isSuccess;
  final String? url;
  final String? publicId;
  final String? errorMessage;
  final String correlationId;

  UploadResult.success({
    required this.url,
    required this.publicId,
    required this.correlationId,
  })  : isSuccess = true,
        errorMessage = null;

  UploadResult.failure(
    this.errorMessage, {
    required this.correlationId,
  })  : isSuccess = false,
        url = null,
        publicId = null;
}
