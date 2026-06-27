import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GitHubSyncHelper {
  final String repoUrl; // e.g., "https://github.com/ELATTAROBOUR/OBOURDIST"
  final String branchName;
  final String githubToken;
  final String dbName;

  GitHubSyncHelper({
    required this.repoUrl,
    required this.branchName,
    required this.githubToken,
    required this.dbName,
  });

  // Extract owner and repo from URL
  String get _repoPath {
    var cleanUrl = repoUrl.trim();
    if (cleanUrl.endsWith('.git')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 4);
    }
    // Expected formats:
    // https://github.com/owner/repo
    // git@github.com:owner/repo
    final parts = cleanUrl.split('github.com/');
    if (parts.length > 1) {
      return parts[1];
    }
    final colonParts = cleanUrl.split('github.com:');
    if (colonParts.length > 1) {
      return colonParts[1];
    }
    return ''; // Fallback
  }

  Map<String, String> get _headers {
    final headers = {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Flutter-MobileApp-Sync',
    };
    if (githubToken.trim().isNotEmpty) {
      headers['Authorization'] = 'token ${githubToken.trim()}';
    }
    return headers;
  }

  // Get SHA of the remote database file
  Future<String?> getRemoteFileSha() async {
    final path = _repoPath;
    if (path.isEmpty) return null;

    final url = Uri.parse(
      'https://api.github.com/repos/$path/contents/$dbName?ref=$branchName',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['sha'] as String?;
      } else if (response.statusCode == 404) {
        debugPrint('GitHub Sync: File $dbName not found on GitHub.');
        return null;
      } else {
        debugPrint(
          'GitHub Sync: Failed to get SHA: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('GitHub Sync: Error fetching file SHA: $e');
      return null;
    }
  }

  // Download raw file content from GitHub to local path
  Future<bool> downloadDatabase(String localPath) async {
    final path = _repoPath;
    if (path.isEmpty) return false;

    final url = Uri.parse(
      'https://api.github.com/repos/$path/contents/$dbName?ref=$branchName',
    );
    final downloadHeaders = Map<String, String>.from(_headers);
    downloadHeaders['Accept'] = 'application/vnd.github.v3.raw';

    try {
      final response = await http.get(url, headers: downloadHeaders);
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint(
          'GitHub Sync: Downloaded database successfully to $localPath',
        );
        return true;
      } else {
        debugPrint('GitHub Sync: Download failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('GitHub Sync: Error downloading database: $e');
      return false;
    }
  }

  // Upload file to GitHub (requires GitHub token)
  Future<bool> uploadDatabase(String localPath, String? currentSha) async {
    final path = _repoPath;
    if (path.isEmpty) {
      debugPrint('GitHub Sync: Invalid repository path.');
      return false;
    }

    if (githubToken.trim().isEmpty) {
      debugPrint(
        'GitHub Sync: Cannot upload without a GitHub Personal Access Token.',
      );
      return false;
    }

    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint('GitHub Sync: Local database file not found at $localPath');
      return false;
    }

    final bytes = await file.readAsBytes();
    final base64Content = base64Encode(bytes);

    final url = Uri.parse(
      'https://api.github.com/repos/$path/contents/$dbName',
    );
    final body = {
      'message':
          'Automatic sync & merge from Android client [${DateTime.now().toLocal()}]',
      'content': base64Content,
      'branch': branchName,
    };
    if (currentSha != null) {
      body['sha'] = currentSha;
    }

    try {
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'token ${githubToken.trim()}',
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Flutter-MobileApp-Sync',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('GitHub Sync: Uploaded database successfully.');
        return true;
      } else {
        debugPrint(
          'GitHub Sync: Upload failed: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('GitHub Sync: Error uploading database: $e');
      return false;
    }
  }
}
