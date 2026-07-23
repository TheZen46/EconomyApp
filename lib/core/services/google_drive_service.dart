// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
// For ClientId, AuthClient
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveService {
  
  // Mobile/Web Auth
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  // Common API Client
  drive.DriveApi? _cachedDriveApi;
  
  // Error Tracking
  String? lastError;

  /// Authenticate using the appropriate method for the platform
  Future<bool> authenticate() async {
    // Return true if we already have a client
    if (_cachedDriveApi != null) return true;

    lastError = null;
    
    // Check if we have cached credentials or need to sign in


    if (Platform.isWindows) {
      return _authenticateWindows();
    } else {
      return _authenticateMobile();
    }
  }



  /// Mobile Authentication (Android/iOS) using google_sign_in plugin
  Future<bool> _authenticateMobile() async {
    try {
      debugPrint('Google Drive (Mobile): Starting Sign In...');
      final user = await _googleSignIn.signIn();
      if (user == null) {
        lastError = 'Sign In cancelled by user';
        return false;
      }
      
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        lastError = 'Failed to get authenticated client';
        return false;
      }
      
      
      _cachedDriveApi = drive.DriveApi(client);
      debugPrint('Google Drive (Mobile): Authenticated as ${user.email}');
      return true;
    } catch (e) {
      lastError = 'Mobile Auth Error: $e';
      debugPrint(lastError);
      return false;
    }
  }

  /// Windows Authentication using googleapis_auth (Loopback/Manual)
  Future<bool> _authenticateWindows() async {
    try {
      debugPrint('Google Drive (Windows): Loading credentials...');
      final jsonString = await rootBundle.loadString('assets/credentials.json');
      final json = jsonDecode(jsonString);
      
      // Support 'installed' or 'web' structure
      final data = json['installed'] ?? json['web'];
      final clientId = data?['client_id'];
      final clientSecret = data?['client_secret']; // client_secret is needed for 'installed' apps

      if (clientId == null) {
        lastError = 'No client_id in assets/credentials.json';
        return false;
      }

      debugPrint('Google Drive (Windows): Using Client ID $clientId');
      final id = ClientId(clientId, clientSecret);
      final scopes = [drive.DriveApi.driveFileScope];

      // This spawns the browser and creates a local server to listen for the code
      final client = await clientViaUserConsent(id, scopes, (url) {
        debugPrint('Google Drive (Windows): Opening User Consent URL: $url');
        // Force account selection so it doesn't auto-use the developer's account
        final newUrl = "$url&prompt=select_account"; 
        launchUrl(Uri.parse(newUrl));
      });

      
      _cachedDriveApi = drive.DriveApi(client);
      debugPrint('Google Drive (Windows): Authenticated Successfully!');
      return true;

    } catch (e) {
      lastError = 'Windows Auth Error: $e\nEnsure credentials.json is valid and type is Desktop.';
      debugPrint(lastError);
      return false;
    }
  }

  Future<String?> _getFolderId(String folderName, {String? parentId}) async {
    if (_cachedDriveApi == null) return null;
    
    String query = "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false";
    if (parentId != null) {
      query += " and '$parentId' in parents";
    }

    
    final fileList = await _cachedDriveApi!.files.list(q: query);
    
    if (fileList.files != null && fileList.files!.isNotEmpty) {
      return fileList.files!.first.id;
    }
    return null;
  }

  Future<String?> _createFolder(String folderName, {String? parentId}) async {
    if (_cachedDriveApi == null) return null;

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    
    if (parentId != null) {
      folder.parents = [parentId];
    }

    final result = await _cachedDriveApi!.files.create(folder);
    return result.id;
  }

  Future<void> uploadFile(File file, String destinationName, {String? folderId}) async {
    if (_cachedDriveApi == null) throw Exception('Not authenticated');

    final driveFile = drive.File()..name = destinationName;
    if (folderId != null) {
      driveFile.parents = [folderId];
    }

    final media = drive.Media(file.openRead(), file.lengthSync());
    await _cachedDriveApi!.files.create(driveFile, uploadMedia: media);
    debugPrint('Google Drive: Uploaded $destinationName');
  }

  Future<void> archiveAllData() async {
    // 1. Authenticate
    final success = await authenticate();
    if (!success) throw Exception(lastError ?? 'Authentication failed');

    // 2. Find or Create Folder "tAIdy_Backups"
    final folderName = "tAIdy_Backups";
    String? folderId = await _getFolderId(folderName);
    
    if (folderId == null) {
      debugPrint('Creating folder: $folderName');
      folderId = await _createFolder(folderName);
    } else {
      debugPrint('Found existing folder: $folderName ($folderId)');
    }

    // 3. Create a dummy backup file (Text for now)
    final dir = await getApplicationDocumentsDirectory();
    final backupFile = File('${dir.path}/backup_temp.txt');
    await backupFile.writeAsString('tAIdy Backup Data\nTimestamp: ${DateTime.now()}\nVersion: 0.3.0');

    // 4. Upload
    debugPrint('Google Drive: Archiving...');
    final fileName = "tAIdy_Backup_${DateTime.now().millisecondsSinceEpoch}.txt";
    await uploadFile(backupFile, fileName, folderId: folderId);
    
    debugPrint('Google Drive: Backup successful!');
  }

  /// Uploads Receipt Image and JSON Label to Google Drive
  /// Structure:
  /// tAIdy_Data/
  ///   images/
  ///     {id}.jpg
  ///   labels/
  ///     {id}.json
  Future<void> uploadReceiptData(Map<String, dynamic> jsonData, String receiptId, String imagePath) async {
     // 1. Authenticate
    final success = await authenticate();
    if (!success) throw Exception(lastError ?? 'Authentication failed');

    // 2. Root Folder
    final rootName = "tAIdy_Data";
    String? rootId = await _getFolderId(rootName);
    rootId ??= await _createFolder(rootName);

    if (rootId == null) throw Exception('Could not create root folder');

    // 3. Subfolders
    String? imagesId = await _getFolderId('images', parentId: rootId);
    imagesId ??= await _createFolder('images', parentId: rootId);
    
    String? labelsId = await _getFolderId('labels', parentId: rootId);
    labelsId ??= await _createFolder('labels', parentId: rootId);

    // 4. Upload Image
    final file = File(imagePath);
    if (file.existsSync()) {
      // Use ID as filename to match label
      final fileName = "$receiptId.jpg"; 
      debugPrint('Google Drive: Uploading image $fileName...');
      await uploadFile(file, fileName, folderId: imagesId);
    }

    // 5. Create and Upload JSON
    try {
      final jsonContent = jsonEncode(jsonData);
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/$receiptId.json');
      await tempFile.writeAsString(jsonContent);
      
      debugPrint('Google Drive: Uploading label $receiptId.json...');
      await uploadFile(tempFile, "$receiptId.json", folderId: labelsId);
      
      // Cleanup
      if (tempFile.existsSync()) tempFile.deleteSync();
    } catch (e) {
      debugPrint('Google Drive: Error creating JSON: $e');
    }
  }


}

final googleDriveService = GoogleDriveService();
