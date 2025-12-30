import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 凭证存储服务：管理账号密码和 JSESSIONID 的本地存储
class CredentialStorageService {
  static const String _adminFileName = 'admin.ini';
  static const String _jsessionFileName = 'jsession.json';
  static const String _ytokenFileName = 'ytoken.json';

  /// 获取存储目录
  Future<Directory> _getStorageDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/flutter_demo_data');
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    return storageDir;
  }

  /// 保存账号密码到 admin.ini
  Future<void> saveCredentials(String username, String password) async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_adminFileName');

      // 简单的 INI 格式
      final content =
          '''[credentials]
username=$username
password=$password
saved_at=${DateTime.now().toIso8601String()}
''';

      await file.writeAsString(content);
      print('[凭证存储] 账号密码已保存到: ${file.path}');
    } catch (e) {
      print('[凭证存储] 保存账号密码失败: $e');
      rethrow;
    }
  }

  /// 从 admin.ini 读取账号密码
  Future<Map<String, String>?> loadCredentials() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_adminFileName');

      if (!await file.exists()) {
        print('[凭证存储] admin.ini 文件不存在');
        return null;
      }

      final content = await file.readAsString();
      final lines = content.split('\n');

      String? username;
      String? password;

      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('username=')) {
          username = line.substring('username='.length);
        } else if (line.startsWith('password=')) {
          password = line.substring('password='.length);
        }
      }

      if (username != null &&
          password != null &&
          username.isNotEmpty &&
          password.isNotEmpty) {
        print('[凭证存储] 成功读取账号: $username');
        return {'username': username, 'password': password};
      }

      return null;
    } catch (e) {
      print('[凭证存储] 读取账号密码失败: $e');
      return null;
    }
  }

  /// 清除账号密码
  Future<void> clearCredentials() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_adminFileName');

      if (await file.exists()) {
        await file.delete();
        print('[凭证存储] 账号密码已清除');
      }
    } catch (e) {
      print('[凭证存储] 清除账号密码失败: $e');
    }
  }

  /// 保存 JSESSIONID 到 jsession.json
  Future<void> saveJSessionId(String jsessionId) async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_jsessionFileName');

      final data = {
        'jsessionId': jsessionId,
        'savedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 2))
            .toIso8601String(), // 假设2小时过期
      };

      await file.writeAsString(jsonEncode(data));
      print('[凭证存储] JSESSIONID 已保存: ${jsessionId.substring(0, 16)}...');
    } catch (e) {
      print('[凭证存储] 保存 JSESSIONID 失败: $e');
      rethrow;
    }
  }

  /// 从 jsession.json 读取 JSESSIONID
  Future<String?> loadJSessionId() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_jsessionFileName');

      if (!await file.exists()) {
        print('[凭证存储] jsession.json 文件不存在');
        return null;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final jsessionId = data['jsessionId'] as String?;
      final expiresAtStr = data['expiresAt'] as String?;

      if (jsessionId == null || jsessionId.isEmpty) {
        return null;
      }

      // 检查是否过期
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          print('[凭证存储] JSESSIONID 已过期');
          await clearJSessionId();
          return null;
        }
      }

      print('[凭证存储] 成功读取 JSESSIONID: ${jsessionId.substring(0, 16)}...');
      return jsessionId;
    } catch (e) {
      print('[凭证存储] 读取 JSESSIONID 失败: $e');
      return null;
    }
  }

  /// 保存 Ytoken 到 ytoken.json
  Future<void> saveYtoken(String ytoken) async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_ytokenFileName');

      final data = {
        'ytoken': ytoken,
        'savedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 24))
            .toIso8601String(), // JWT 通常24小时过期
      };

      await file.writeAsString(jsonEncode(data));
      print('[凭证存储] Ytoken 已保存: ${ytoken.substring(0, 20)}...');
    } catch (e) {
      print('[凭证存储] 保存 Ytoken 失败: $e');
      rethrow;
    }
  }

  /// 从 ytoken.json 读取 Ytoken
  Future<String?> loadYtoken() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_ytokenFileName');

      if (!await file.exists()) {
        print('[凭证存储] ytoken.json 文件不存在');
        return null;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final ytoken = data['ytoken'] as String?;
      final expiresAtStr = data['expiresAt'] as String?;

      if (ytoken == null || ytoken.isEmpty) {
        return null;
      }

      // 检查是否过期
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          print('[凭证存储] Ytoken 已过期');
          await clearYtoken();
          return null;
        }
      }

      print('[凭证存储] 成功读取 Ytoken: ${ytoken.substring(0, 20)}...');
      return ytoken;
    } catch (e) {
      print('[凭证存储] 读取 Ytoken 失败: $e');
      return null;
    }
  }

  /// 清除 Ytoken
  Future<void> clearYtoken() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_ytokenFileName');

      if (await file.exists()) {
        await file.delete();
        print('[凭证存储] Ytoken 已清除');
      }
    } catch (e) {
      print('[凭证存储] 清除 Ytoken 失败: $e');
    }
  }

  /// 清除 JSESSIONID
  Future<void> clearJSessionId() async {
    try {
      final dir = await _getStorageDirectory();
      final file = File('${dir.path}/$_jsessionFileName');

      if (await file.exists()) {
        await file.delete();
        print('[凭证存储] JSESSIONID 已清除');
      }
    } catch (e) {
      print('[凭证存储] 清除 JSESSIONID 失败: $e');
    }
  }

  /// 清除所有凭证
  Future<void> clearAll() async {
    await clearCredentials();
    await clearJSessionId();
    await clearYtoken();
    print('[凭证存储] 所有凭证已清除');
  }
}
