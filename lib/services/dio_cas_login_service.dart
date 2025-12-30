import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' show Document;

const String CAS_LOGIN_URL =
    'https://cas.swjtu.edu.cn/authserver/login'
    '?service=http%3A%2F%2Fjwc.swjtu.edu.cn%2Fvatuu%2FUserLoginForWiseduAction';
const String BASE = 'http://jwc.swjtu.edu.cn';
const String USERFRAMEWORK_PATH = '/vatuu/UserFramework';
const String STUDENTINFO_PATH =
    '/vatuu/StudentInfoAction?setAction=studentInfoQuery';
const String AJAX_USERMSG = '/vatuu/AjaxXML?selectType=UserMessageNum';

const String AES_CHARS = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

const Map<String, String> BROWSER_LIKE_HEADERS = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Upgrade-Insecure-Requests': '1',
};

class LoginResult {
  final bool success;
  final String message;
  final String? jsessionId;
  const LoginResult({
    required this.success,
    required this.message,
    this.jsessionId,
  });
}

class DioCasLoginService {
  late final Dio _dio;
  late final CookieJar _cookieJar;
  final List<String> _logs = [];
  bool _disposed = false;

  DioCasLoginService() {
    _cookieJar = CookieJar();
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true, // 自动跟随重定向
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 500,
        headers: BROWSER_LIKE_HEADERS,
      ),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));

    // 添加日志拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _addLog('[→ 请求] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _addLog(
            '[← 响应] ${response.statusCode} ${response.requestOptions.uri}',
          );
          return handler.next(response);
        },
        onError: (error, handler) {
          _addLog('[✗ 错误] ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  void _addLog(String line) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $line');
    if (_logs.length > 1000) _logs.removeAt(0);
    print(line);
  }

  List<String> get logs => List.unmodifiable(_logs);

  String _safeFilename(String input, {int maxLen = 80}) {
    var s = input.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (s.length > maxLen) s = s.substring(0, maxLen);
    if (s.isEmpty) s = 'empty';
    return s;
  }

  bool _isStudentInfoLoggedIn(String html) {
    final hasUnauthorized =
        html.contains('您还未登陆') || html.contains('非常抱歉，您还未登陆');
    final hasBothLoginFields =
        html.contains('name="username"') && html.contains('name="password"');
    return !(hasUnauthorized || hasBothLoginFields);
  }

  Future<String?> _fetchStudentInfoHtml() async {
    final resp = await _dio.get(
      '$BASE$STUDENTINFO_PATH',
      options: Options(headers: {'Referer': '$BASE$USERFRAMEWORK_PATH'}),
    );
    return resp.data?.toString();
  }

  Future<void> _saveDebugText(String filename, String content) async {
    try {
      final file = File(
        'C:\\Users\\cookies\\Desktop\\flutter\\flutter_demo\\$filename',
      );
      await file.writeAsString(content);
    } catch (e) {
      _addLog('[!] 保存调试文件失败($filename): $e');
    }
  }

  Future<void> _saveResponseDump(String prefix, Response<dynamic> resp) async {
    final code = resp.statusCode ?? 0;
    final uri = resp.realUri.toString();
    final safePrefix = _safeFilename(prefix, maxLen: 40);
    final safeUri = _safeFilename(uri, maxLen: 60);

    // headers/status/url
    final headerBuf = StringBuffer();
    headerBuf.writeln('status=$code');
    headerBuf.writeln('realUri=$uri');
    headerBuf.writeln('requestUri=${resp.requestOptions.uri}');
    headerBuf.writeln('method=${resp.requestOptions.method}');
    headerBuf.writeln('headers:');
    resp.headers.map.forEach((k, v) {
      headerBuf.writeln('  $k: ${v.join('; ')}');
    });
    await _saveDebugText(
      'debug_dio_${safePrefix}_${code}_headers_${safeUri}.txt',
      headerBuf.toString(),
    );

    // body (best-effort)
    final body = resp.data?.toString() ?? '';
    if (body.isNotEmpty) {
      // Heuristic: most steps are HTML/text
      await _saveDebugText(
        'debug_dio_${safePrefix}_${code}_body_${safeUri}.html',
        body,
      );
    }
  }

  Future<void> _dumpCookies(String label, Uri uri) async {
    try {
      final cookies = await _cookieJar.loadForRequest(uri);
      final buf = StringBuffer();
      buf.writeln('uri=$uri');
      buf.writeln('count=${cookies.length}');
      for (final c in cookies) {
        buf.writeln(
          '${c.name}=${c.value} ; domain=${c.domain} ; path=${c.path} ; secure=${c.secure} ; httpOnly=${c.httpOnly}',
        );
      }
      await _saveDebugText(
        'debug_dio_cookies_${_safeFilename(label)}.txt',
        buf.toString(),
      );
    } catch (e) {
      _addLog('[!] dump cookies failed($label): $e');
    }
  }

  Uri _resolveRedirectUri(Uri current, String location) {
    try {
      final loc = Uri.parse(location);
      if (loc.hasScheme) return loc;
      return current.resolveUri(loc);
    } catch (_) {
      return current;
    }
  }

  /// 手动跟随 HTTP 302/301/303/307/308，确保每一步 Set-Cookie 都能被 CookieManager 捕获。
  Future<Response<dynamic>> _getFollowRedirectsManually(
    String startUrl, {
    String? initialReferer,
    String debugPrefix = 'redirect',
    int maxSteps = 12,
  }) async {
    var current = Uri.parse(startUrl);
    String? referer = initialReferer;
    for (var i = 0; i < maxSteps; i++) {
      final resp = await _dio.get(
        current.toString(),
        options: Options(
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (status) => status != null && status < 500,
          headers: referer == null ? null : {'Referer': referer},
        ),
      );

      await _saveResponseDump('$debugPrefix.step$i', resp);

      final code = resp.statusCode ?? 0;
      if (code == 301 ||
          code == 302 ||
          code == 303 ||
          code == 307 ||
          code == 308) {
        final location = resp.headers.value('location');
        if (location == null || location.isEmpty) {
          return resp;
        }
        current = _resolveRedirectUri(current, location);
        _addLog('[*] 跟随重定向(${code}): $current');
        referer = resp.requestOptions.uri.toString();
        continue;
      }

      return resp;
    }

    throw StateError('重定向次数超过限制($maxSteps)');
  }

  Future<String?> _extractJSessionId() async {
    try {
      final uri = Uri.parse(BASE);
      final cookies = await _cookieJar.loadForRequest(uri);

      for (final cookie in cookies) {
        if (cookie.name.toUpperCase() == 'JSESSIONID') {
          return cookie.value;
        }
      }
    } catch (e) {
      _addLog('[!] 获取 JSESSIONID 失败: $e');
    }
    return null;
  }

  Future<LoginResult> login(String username, String password) async {
    if (_disposed) {
      return const LoginResult(success: false, message: '服务已释放');
    }

    try {
      _addLog('========== 开始登录流程 ==========');
      _addLog('[*] 用户名: $username');

      // 步骤1: 获取 CAS 登录页面和表单参数
      _addLog('[1/4] 获取 CAS 登录页面...');
      final response1 = await _dio.get(
        CAS_LOGIN_URL,
        options: Options(headers: {'Referer': '$BASE/vatuu/UserFramework'}),
      );

      await _saveResponseDump('01_cas_login_page', response1);
      await _dumpCookies(
        '00_after_cas_login_page',
        Uri.parse('https://cas.swjtu.edu.cn/'),
      );

      final html = response1.data as String;
      final fields = _parseHiddenFields(html);
      String salt = fields['pwdEncryptSalt'] ?? '';
      String lt = fields['lt'] ?? '';
      String execution = fields['execution'] ?? '';

      _addLog(
        '[*] 表单参数: salt=${salt.length}字符, lt=${lt.length}字符, execution=${execution.length}字符',
      );

      if (salt.isEmpty) {
        return const LoginResult(
          success: false,
          message: '无法获取加密盐值（pwdEncryptSalt），可能需要验证码',
        );
      }

      if (execution.isEmpty) {
        return const LoginResult(
          success: false,
          message: '无法获取 execution 参数，页面结构可能已变化',
        );
      }

      // lt 可以为空
      if (lt.isEmpty) {
        _addLog('[*] lt 参数为空（正常现象）');
      }

      // 步骤2: 加密密码
      _addLog('[2/4] 加密密码...');
      final encryptedPassword = _encryptPassword(password, salt);

      // 步骤3: 提交登录表单
      _addLog('[3/5] 提交登录表单...');
      final loginResponse = await _dio.post(
        CAS_LOGIN_URL,
        data: {
          'username': username,
          'password': encryptedPassword,
          'captcha': '',
          '_eventId': 'submit',
          'cllt': 'userNameLogin',
          'dllt': 'generalLogin',
          'lt': lt,
          'execution': execution,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false, // 手动处理重定向
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'Referer': CAS_LOGIN_URL,
            'Origin': 'https://cas.swjtu.edu.cn',
          },
        ),
      );

      _addLog('[*] 登录响应状态: ${loginResponse.statusCode}');

      await _saveResponseDump('02_cas_post_response', loginResponse);
      await _dumpCookies(
        '01_after_cas_post',
        Uri.parse('https://cas.swjtu.edu.cn/'),
      );

      // 步骤4: 跟随 CAS 的重定向（访问带 ticket 的 URL）
      if (loginResponse.statusCode == 302 || loginResponse.statusCode == 301) {
        final redirectUrl = loginResponse.headers.value('location');
        _addLog('[4/6] 跟随重定向: $redirectUrl');
        if (redirectUrl == null || redirectUrl.isEmpty) {
          return const LoginResult(success: false, message: '登录重定向缺少 Location');
        }

        // 手动跟随 302 链，确保每一步 Set-Cookie 都被记录
        final ticketResponse = await _getFollowRedirectsManually(
          redirectUrl,
          initialReferer: CAS_LOGIN_URL,
          debugPrefix: '03_ticket_chain',
          maxSteps: 12,
        );
        _addLog('[*] Ticket 交换完成，最终 URL: ${ticketResponse.realUri}');
        await _dumpCookies(
          '02_after_ticket_chain_http',
          Uri.parse('http://jwc.swjtu.edu.cn/'),
        );
        await _dumpCookies(
          '02_after_ticket_chain_https',
          Uri.parse('https://jwc.swjtu.edu.cn/'),
        );

        // 解析 meta refresh 并跟随跳转到 UserLoginForCAS
        final ticketHtml = ticketResponse.data?.toString() ?? '';
        if (ticketHtml.isNotEmpty) {
          await _saveDebugText('debug_ticket_response.html', ticketHtml);
        }

        final metaRefreshRegex = RegExp(
          r'content="?\d+;\s*url=([^">\s]+)"?',
          caseSensitive: false,
        );
        final match = metaRefreshRegex.firstMatch(ticketHtml);
        if (match != null) {
          var nextUrl = match.group(1)!;
          if (nextUrl.startsWith('../')) {
            nextUrl = '$BASE${nextUrl.substring(2)}';
          } else if (nextUrl.startsWith('/')) {
            nextUrl = '$BASE$nextUrl';
          }
          _addLog('[5/6] 跟随 meta refresh: $nextUrl');
          await Future.delayed(const Duration(seconds: 3));

          final casResponse = await _getFollowRedirectsManually(
            nextUrl,
            initialReferer: ticketResponse.realUri.toString(),
            debugPrefix: '04_userloginforcas_chain',
            maxSteps: 12,
          );
          _addLog('[*] 跳转链完成，最终 URL: ${casResponse.realUri}');

          final casHtml = casResponse.data?.toString() ?? '';
          if (casHtml.isNotEmpty) {
            await _saveDebugText('debug_cas_response.html', casHtml);
          }

          // 检查是否还有 meta refresh（某些情况下会有第二次跳转）
          final secondMeta = metaRefreshRegex.firstMatch(casHtml);
          if (secondMeta != null) {
            var secondUrl = secondMeta.group(1)!;
            if (secondUrl.startsWith('../')) {
              secondUrl = '$BASE${secondUrl.substring(2)}';
            } else if (!secondUrl.startsWith('http')) {
              if (secondUrl.startsWith('/')) {
                secondUrl = '$BASE$secondUrl';
              } else {
                secondUrl = '$BASE/$secondUrl';
              }
            }
            _addLog('[*] 检测到第二个 meta refresh: $secondUrl');
            await Future.delayed(const Duration(seconds: 3));
            await _getFollowRedirectsManually(
              secondUrl,
              initialReferer: casResponse.realUri.toString(),
              debugPrefix: '05_userloading_chain',
              maxSteps: 12,
            );
            _addLog('[*] 第二段跳转链完成');
            await _dumpCookies(
              '03_after_userloading_chain_http',
              Uri.parse('http://jwc.swjtu.edu.cn/'),
            );
            await _dumpCookies(
              '03_after_userloading_chain_https',
              Uri.parse('https://jwc.swjtu.edu.cn/'),
            );

            // 关键：第5步页面通常会在 JS 中 setTimeout 跳转到 UserFramework。
            // 不访问 UserFramework 时，部分接口（如 StudentInfo）可能仍会判定未登录。
            _addLog('[*] 等待并访问 UserFramework (模拟 timed redirect)...');
            await Future.delayed(const Duration(seconds: 3));
            await _getFollowRedirectsManually(
              '$BASE$USERFRAMEWORK_PATH',
              initialReferer: secondUrl,
              debugPrefix: '06_userframework_chain',
              maxSteps: 8,
            );
            await _dumpCookies(
              '04_after_userframework_http',
              Uri.parse('http://jwc.swjtu.edu.cn/'),
            );
            await _dumpCookies(
              '04_after_userframework_https',
              Uri.parse('https://jwc.swjtu.edu.cn/'),
            );
          }
        } else {
          _addLog('[!] 未找到 meta refresh URL，尝试直接访问 UserFramework');
          await Future.delayed(const Duration(seconds: 2));
          final uf = await _dio.get('$BASE$USERFRAMEWORK_PATH');
          await _saveResponseDump('04_fallback_userframework', uf);
        }
      }

      // 最终校验：必须能访问 StudentInfo 且判定为已登录（带重试，避免“刚登录未生效”）
      bool studentInfoOk = false;
      String? lastStudentInfo;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
        await _dumpCookies(
          '05_before_studentinfo_attempt${attempt}_http',
          Uri.parse('http://jwc.swjtu.edu.cn/'),
        );
        await _dumpCookies(
          '05_before_studentinfo_attempt${attempt}_https',
          Uri.parse('https://jwc.swjtu.edu.cn/'),
        );
        final resp = await _dio.get(
          '$BASE$STUDENTINFO_PATH',
          options: Options(headers: {'Referer': '$BASE$USERFRAMEWORK_PATH'}),
        );
        await _saveResponseDump('07_studentinfo_attempt$attempt', resp);
        final html = resp.data?.toString() ?? '';
        lastStudentInfo = html;
        if (html.isNotEmpty && _isStudentInfoLoggedIn(html)) {
          studentInfoOk = true;
          break;
        }
      }

      if (!studentInfoOk) {
        if (lastStudentInfo != null && lastStudentInfo.isNotEmpty) {
          await _saveDebugText(
            'debug_studentinfo_response.html',
            lastStudentInfo,
          );
        }
        _addLog('[*] StudentInfo 登录态校验: 未登录');
        return const LoginResult(
          success: false,
          message: 'CAS流程完成但教务仍未登录（StudentInfo 返回未登录）',
        );
      }

      _addLog('[*] StudentInfo 登录态校验: 已登录');

      // 提取 JSESSIONID（此时应为“已登录会话”的 JSESSIONID）
      final jsessionId = await _extractJSessionId();
      if (jsessionId == null || jsessionId.isEmpty) {
        _addLog('[✗] 未找到 JSESSIONID');
        return const LoginResult(
          success: false,
          message: '已登录但未获取到 JSESSIONID',
        );
      }

      _addLog(
        '[✓] JSESSIONID: ${jsessionId.substring(0, min(16, jsessionId.length))}... (${jsessionId.length}字符)',
      );
      _addLog('========== 登录成功！ ==========');
      return LoginResult(
        success: true,
        message: '登录成功',
        jsessionId: jsessionId,
      );
    } catch (e, stackTrace) {
      _addLog('[✗] 登录异常: $e');
      _addLog('[✗] 堆栈: $stackTrace');
      return LoginResult(success: false, message: '登录异常: $e');
    }
  }

  Map<String, String> _parseHiddenFields(String html) {
    final Document doc = parse(html);

    String getInput(String nameOrId) {
      final elById = doc.querySelector('#$nameOrId');
      if (elById != null && elById.attributes.containsKey('value')) {
        return elById.attributes['value'] ?? '';
      }
      final elByName = doc.querySelector('input[name="$nameOrId"]');
      if (elByName != null && elByName.attributes.containsKey('value')) {
        return elByName.attributes['value'] ?? '';
      }
      return '';
    }

    return {
      'execution': getInput('execution'),
      'lt': getInput('lt'),
      'pwdEncryptSalt': getInput('pwdEncryptSalt').isNotEmpty
          ? getInput('pwdEncryptSalt')
          : (getInput('pwdSalt').isNotEmpty
                ? getInput('pwdSalt')
                : getInput('pwdEncryptKey')),
    };
  }

  String _randomString(int n) {
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (int i = 0; i < n; i++) {
      buf.write(AES_CHARS[rnd.nextInt(AES_CHARS.length)]);
    }
    return buf.toString();
  }

  String _encryptPassword(String plain, String keySalt) {
    if (keySalt.isEmpty) return plain;

    final prefix = _randomString(64);
    final ivStr = _randomString(16);
    final full = prefix + plain;

    final blockSize = 16;
    final bytes = utf8.encode(full);
    final padLen = blockSize - (bytes.length % blockSize);
    final padded = List<int>.from(bytes)
      ..addAll(List<int>.filled(padLen, padLen));

    List<int> keyBytes = utf8.encode(keySalt);
    if (!(keyBytes.length == 16 ||
        keyBytes.length == 24 ||
        keyBytes.length == 32)) {
      keyBytes = md5.convert(keyBytes).bytes;
    }

    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromUtf8(ivStr);
    final cipher = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: null),
    );
    final encrypted = cipher.encryptBytes(padded, iv: iv);

    return base64.encode(encrypted.bytes);
  }

  Future<String?> getStudentInfo() async {
    if (_disposed) return null;
    try {
      final response = await _dio.get(
        '$BASE$STUDENTINFO_PATH',
        options: Options(headers: {'Referer': '$BASE$USERFRAMEWORK_PATH'}),
      );
      return response.data as String;
    } catch (e) {
      _addLog('[!] 获取学生信息失败: $e');
      return null;
    }
  }

  Future<String?> getUserFramework() async {
    if (_disposed) return null;
    try {
      final response = await _dio.get('$BASE$USERFRAMEWORK_PATH');
      return response.data as String;
    } catch (e) {
      _addLog('[!] 获取 UserFramework 失败: $e');
      return null;
    }
  }

  Future<String?> getJSessionId() async {
    return await _extractJSessionId();
  }

  void dispose() {
    _disposed = true;
    _dio.close(force: true);
    _logs.clear();
  }
}
