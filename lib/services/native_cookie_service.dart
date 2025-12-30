import 'package:flutter/services.dart';

/// 原生 Cookie 服务 - 通过 Platform Channel 调用 WebView2 CookieManager
class NativeCookieService {
  static const platform = MethodChannel('com.flutter.demo/native_cookie');

  /// 获取指定 URL 的 Cookie（包括 HttpOnly）
  ///
  /// 参数:
  /// - url: 目标 URL，例如 "https://jwc.swjtu.edu.cn"
  ///
  /// 返回: Cookie 列表，每个 Cookie 是一个 Map，包含 name, value, domain 等字段
  static Future<List<Map<String, dynamic>>> getCookies(String url) async {
    try {
      final result = await platform.invokeMethod('getCookies', {'url': url});
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } on PlatformException catch (e) {
      print('获取 Cookie 失败: ${e.message}');
      return [];
    }
  }

  /// 获取指定名称的 Cookie 值
  ///
  /// 参数:
  /// - url: 目标 URL
  /// - name: Cookie 名称，例如 "JSESSIONID"
  ///
  /// 返回: Cookie 值，如果不存在则返回 null
  static Future<String?> getCookie(String url, String name) async {
    try {
      final result = await platform.invokeMethod('getCookie', {
        'url': url,
        'name': name,
      });
      return result as String?;
    } on PlatformException catch (e) {
      print('获取 Cookie 失败: ${e.message}');
      return null;
    }
  }

  /// 设置 Cookie
  static Future<bool> setCookie({
    required String url,
    required String name,
    required String value,
    String? domain,
    String path = '/',
    int? expires,
    bool httpOnly = false,
    bool secure = false,
  }) async {
    try {
      final result = await platform.invokeMethod('setCookie', {
        'url': url,
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires,
        'httpOnly': httpOnly,
        'secure': secure,
      });
      return result as bool? ?? false;
    } on PlatformException catch (e) {
      print('设置 Cookie 失败: ${e.message}');
      return false;
    }
  }

  /// 删除指定名称的 Cookie
  static Future<bool> deleteCookie(String url, String name) async {
    try {
      final result = await platform.invokeMethod('deleteCookie', {
        'url': url,
        'name': name,
      });
      return result as bool? ?? false;
    } on PlatformException catch (e) {
      print('删除 Cookie 失败: ${e.message}');
      return false;
    }
  }

  /// 删除所有 Cookie
  static Future<bool> deleteAllCookies(String url) async {
    try {
      final result = await platform.invokeMethod('deleteAllCookies', {
        'url': url,
      });
      return result as bool? ?? false;
    } on PlatformException catch (e) {
      print('删除所有 Cookie 失败: ${e.message}');
      return false;
    }
  }
}
