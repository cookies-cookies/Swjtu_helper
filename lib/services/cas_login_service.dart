import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' show Document;

const String CAS_LOGIN_URL =
    'https://cas.swjtu.edu.cn/authserver/login'
    '?service=http%3A%2F%2Fjwc.swjtu.edu.cn%2Fvatuu%2FUserLoginForWiseduAction';
const String BASE = 'https://jwc.swjtu.edu.cn';
const String USERFRAMEWORK_PATH = '/vatuu/UserFramework';
const String STUDENTINFO_PATH =
    '/vatuu/StudentInfoAction?setAction=studentInfoQuery';
const String AJAX_USERMSG = '/vatuu/AjaxXML?selectType=UserMessageNum';

const String CAS_PAGE_HTML = 'cas_login_page.html';
const String CAS_PAGE_RETRY_HTML = 'cas_login_page_retry.html';
const String CAS_POST_RESP = 'cas_login_post_response.html';
const String OUT_USERFRAME = 'output_userframework.html';
const String OUT_USERLOADING = 'output_userloading.html';
const String OUT_AJAX = 'ajax_user_message_num.xml';
const String OUT_STUDENTINFO = 'student_info.html';
const String COOKIES_FILE = 'cookies.json';

const String NODE_RUNNER = 'immediate_node_login.js';
const String AES_CHARS = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

String _resolveNodeRunnerPath() {
  final local = File(NODE_RUNNER);
  if (local.existsSync()) return NODE_RUNNER;
  final parentPath = Platform.isWindows
      ? '..\\' + NODE_RUNNER
      : '../' + NODE_RUNNER;
  final parent = File(parentPath);
  if (parent.existsSync()) return parent.path;
  return NODE_RUNNER; // fallback (will fail later if truly missing)
}

const Map<String, String> BROWSER_LIKE_HEADERS = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Upgrade-Insecure-Requests': '1',
  'Sec-Fetch-Site': 'cross-site',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Dest': 'document',
};

class _CookieItem {
  final String name;
  String value;
  final String? domain; // may be null (host-only)
  _CookieItem(this.name, this.value, this.domain);
}

class SimpleCookieJar {
  final List<_CookieItem> _cookies = [];

  void updateFromSetCookie(Iterable<String>? setCookieHeaders) {
    if (setCookieHeaders == null) return;
    for (final header in setCookieHeaders) {
      final parts = header.split(';');
      if (parts.isEmpty) continue;
      final nv = parts[0].trim();
      final idx = nv.indexOf('=');
      if (idx <= 0) continue;
      final name = nv.substring(0, idx);
      final value = nv.substring(idx + 1);
      String? domain;
      for (int i = 1; i < parts.length; i++) {
        final p = parts[i].trim();
        final lower = p.toLowerCase();
        if (lower.startsWith('domain=')) {
          domain = p.substring(7).trim();
        }
      }
      // replace existing same name+domain
      final existingIndex = _cookies.indexWhere((c) => c.name == name && c.domain == domain);
      if (existingIndex >= 0) {
        _cookies[existingIndex].value = value;
      } else {
        _cookies.add(_CookieItem(name, value, domain));
      }
    }
  }

  void set(String name, String value, {String? domain}) {
    final idx = _cookies.indexWhere((c) => c.name == name && c.domain == domain);
    if (idx >= 0) {
      _cookies[idx].value = value;
    } else {
      _cookies.add(_CookieItem(name, value, domain));
    }
  }

  String getCookieHeaderForRequest(Uri uri) {
    if (_cookies.isEmpty) return '';
    final host = uri.host.toLowerCase();
    final send = <_CookieItem>[];
    for (final c in _cookies) {
      if (c.domain == null) {
        // host-only: always send
        send.add(c);
      } else {
        final d = c.domain!.toLowerCase();
        // domain match rules: exact or host ends with domain (handling leading dot)
        final dom = d.startsWith('.') ? d.substring(1) : d;
        if (host == dom || host.endsWith('.' + dom)) {
          send.add(c);
        }
      }
    }
    if (send.isEmpty) return '';
    return send.map((e) => '${e.name}=${e.value}').join('; ');
  }

  Map<String, String> toMap() {
    final m = <String, String>{};
    for (final c in _cookies) {
      // if duplicates (different domain) keep first encountered
      m.putIfAbsent(c.name, () => c.value);
    }
    return m;
  }

  void clear() => _cookies.clear();
}

Future<void> saveText(String path, String content) async {
  await File(path).writeAsString(content, encoding: utf8);
}

Map<String, String> parseHiddenFields(String html) {
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

Future<Map<String, dynamic>> runNodeRunner(
  String pageHtmlPath,
  String password, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final runnerPath = _resolveNodeRunnerPath();
  if (!File(runnerPath).existsSync()) {
    throw FileSystemException('Node runner not found', runnerPath);
  }
  final proc = await Process.run(
    'node',
    [runnerPath, pageHtmlPath, password],
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (proc.exitCode != 0) {
    throw Exception('node-runner failed: ${proc.stderr}');
  }
  final out = proc.stdout?.toString().trim() ?? '';
  if (out.isEmpty) {
    throw Exception('node-runner produced no stdout');
  }
  try {
    final jsonOut = json.decode(out) as Map<String, dynamic>;
    return jsonOut;
  } catch (e) {
    throw Exception('Failed to parse node-runner JSON: $e\nstdout:\n$out');
  }
}

Future<HttpClientResponse> httpGet(
  HttpClient client,
  Uri uri,
  SimpleCookieJar jar, {
  Map<String, String>? extraHeaders,
}) async {
  final req = await client.getUrl(uri);
  // set headers
  BROWSER_LIKE_HEADERS.forEach((k, v) => req.headers.set(k, v));
  extraHeaders?.forEach((k, v) => req.headers.set(k, v));
  final cookieHeader = jar.getCookieHeaderForRequest(uri);
  if (cookieHeader.isNotEmpty)
    req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
  return await req.close();
}

Future<HttpClientResponse> httpPostForm(
  HttpClient client,
  Uri uri,
  Map<String, String> form,
  SimpleCookieJar jar, {
  Map<String, String>? extraHeaders,
  bool followRedirects = false,
}) async {
  final req = await client.postUrl(uri);
  BROWSER_LIKE_HEADERS.forEach((k, v) => req.headers.set(k, v));
  extraHeaders?.forEach((k, v) => req.headers.set(k, v));
  req.headers.contentType = ContentType(
    'application',
    'x-www-form-urlencoded',
    charset: 'utf-8',
  );
  final cookieHeader = jar.getCookieHeaderForRequest(uri);
  if (cookieHeader.isNotEmpty)
    req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
  final body = form.entries
      .map(
        (e) =>
            Uri.encodeQueryComponent(e.key) +
            '=' +
            Uri.encodeQueryComponent(e.value),
      )
      .join('&');
  req.write(body);
  return await req.close();
}

Future<String> responseToString(HttpClientResponse resp) async {
  final body = await resp.transform(utf8.decoder).join();
  return body;
}

Future<bool> casLoginAndFollow(
  SimpleCookieJar jar,
  String username,
  String password,
) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);

  try {
    // Pre-warm JWC
    try {
      final pre1 = await httpGet(
        client,
        Uri.parse('$BASE/vatuu/UserLoadingAction'),
        jar,
      );
      jar.updateFromSetCookie(pre1.headers[HttpHeaders.setCookieHeader]);
      await responseToString(pre1);
    } catch (_) {}
    try {
      final pre2 = await httpGet(
        client,
        Uri.parse('$BASE/vatuu/UserFramework'),
        jar,
      );
      jar.updateFromSetCookie(pre2.headers[HttpHeaders.setCookieHeader]);
      await responseToString(pre2);
    } catch (_) {}

    // GET CAS login page
    final headers1 = {'Referer': '$BASE/vatuu/UserFramework'};
    final r = await httpGet(
      client,
      Uri.parse(CAS_LOGIN_URL),
      jar,
      extraHeaders: headers1,
    );
    jar.updateFromSetCookie(r.headers[HttpHeaders.setCookieHeader]);
    final text = await responseToString(r);
    await saveText(CAS_PAGE_HTML, text);

    final fields = parseHiddenFields(text);
    String salt = fields['pwdEncryptSalt'] ?? '';
    String lt = fields['lt'] ?? '';
    String execution = fields['execution'] ?? '';
    print('[*] initial saltLen=${salt.length} ltLen=${lt.length} execLen=${execution.length}');

    if (salt.isEmpty || lt.isEmpty) {
      // retry once with alternate headers
      final headers2 = {
        'Referer': '$BASE/vatuu/UserLoadingAction',
        'Origin': 'https://cas.swjtu.edu.cn',
      };
      final r2 = await httpGet(
        client,
        Uri.parse(CAS_LOGIN_URL),
        jar,
        extraHeaders: headers2,
      );
      jar.updateFromSetCookie(r2.headers[HttpHeaders.setCookieHeader]);
      final text2 = await responseToString(r2);
      await saveText(CAS_PAGE_RETRY_HTML, text2);
      final f2 = parseHiddenFields(text2);
      salt = salt.isNotEmpty ? salt : (f2['pwdEncryptSalt'] ?? '');
      lt = lt.isNotEmpty ? lt : (f2['lt'] ?? '');
      execution = execution.isNotEmpty ? execution : (f2['execution'] ?? '');
      print('[*] after retry saltLen=${salt.length} ltLen=${lt.length} execLen=${execution.length}');
    }

    if (salt.isEmpty) {
      print(
        '[!] No pwdEncryptSalt found; login may require JS/captcha. Saved CAS HTML for inspection.',
      );
      return false;
    }

    String encPassword = '';
    if (lt.isEmpty) {
      print(
        '[*] lt empty in HTML — attempting node-runner to execute page JS and derive lt/encrypted password.',
      );
      // Ensure CAS_PAGE_HTML exists on disk for node-runner
      if (!File(CAS_PAGE_HTML).existsSync()) {
        await saveText(CAS_PAGE_HTML, text);
      }
      try {
        final nodeOut = await runNodeRunner(CAS_PAGE_HTML, password);
        final nodeLt = (nodeOut['lt'] ?? '') as String;
        final nodeEnc = (nodeOut['encrypted'] ?? '') as String;
        if (nodeLt.isNotEmpty) {
          lt = nodeLt;
          print('[+] node-runner provided lt (len=${lt.length}).');
        }
        if (nodeEnc.isNotEmpty) {
          // 我们记录 node-runner 密文但不直接使用，保持与 Python 回退加密处理方式统一
          print('[*] node-runner encrypted (len=${nodeEnc.length}), will replace with AES fallback to mimic python flow.');
        }
      } catch (e) {
        print('[!] node-runner failed: $e');
      }
    }
    print('[*] pre-fallback saltLen=${salt.length} ltLen=${lt.length} encLen=${encPassword.length}');

    // 始终使用与 Python 脚本一致的 AES CBC 回退加密（忽略 node-runner 密文差异）
    encPassword = encryptPasswordFallback(password, salt);
    print('[*] Using AES fallback encrypted password (len=${encPassword.length}).');

    // Build payload
    final payload = {
      'username': username,
      'password': encPassword,
      'captcha': '',
      '_eventId': 'submit',
      'cllt': 'userNameLogin',
      'dllt': 'generalLogin',
      'lt': lt,
      'execution': execution,
    };

    // POST login
    final postResp = await httpPostForm(
      client,
      Uri.parse(CAS_LOGIN_URL),
      payload,
      jar,
      extraHeaders: {
        'Referer': CAS_LOGIN_URL,
        'Origin': 'https://cas.swjtu.edu.cn',
      },
    );
    jar.updateFromSetCookie(postResp.headers[HttpHeaders.setCookieHeader]);
    final statusCode = postResp.statusCode;
    final postBody = await responseToString(postResp);
    await saveText(CAS_POST_RESP, postBody);

    if (statusCode != 301 && statusCode != 302) {
      print('[!] Login POST did not redirect; status: $statusCode');
      final low = postBody.toLowerCase();
      if (low.contains('验证码') ||
          low.contains('geetest') ||
          low.contains('滑块')) {
        print(
          '[!] The login response appears to require a captcha/slider. Node-runner / Playwright required.',
        );
      }
      return false;
    }

    // follow location
    final location = postResp.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.isEmpty) {
      print('[!] No Location header after login POST.');
      return false;
    }

    final rTicket = await httpGet(client, Uri.parse(location), jar);
    jar.updateFromSetCookie(rTicket.headers[HttpHeaders.setCookieHeader]);
    final rTicketBody = await responseToString(rTicket);
    await saveText(OUT_USERLOADING, rTicketBody);

    // find meta refresh or go to UserFramework
    final doc = parse(rTicketBody);
    final meta = doc.querySelector('meta[http-equiv]');
    String? metaTarget;
    if (meta != null) {
      final equiv = meta.attributes['http-equiv']?.toLowerCase();
      if (equiv == 'refresh') {
        final content = meta.attributes['content'] ?? '';
        final parts = content.split(';');
        for (final part in parts) {
          final low = part.toLowerCase();
          if (low.contains('url=')) {
            metaTarget = part
                .split('=')[1]
                .trim()
                .replaceAll('"', '')
                .replaceAll("'", '');
            break;
          }
        }
      }
    }

    if (metaTarget != null && metaTarget.isNotEmpty) {
      final rMeta = await httpGet(
        client,
        Uri.parse(metaTarget),
        jar,
        extraHeaders: {'Referer': location},
      );
      jar.updateFromSetCookie(rMeta.headers[HttpHeaders.setCookieHeader]);
      final metaBody = await responseToString(rMeta);
      await saveText(OUT_USERFRAME, metaBody);
    } else {
      final rUf = await httpGet(
        client,
        Uri.parse('$BASE$USERFRAMEWORK_PATH'),
        jar,
        extraHeaders: {'Referer': location},
      );
      jar.updateFromSetCookie(rUf.headers[HttpHeaders.setCookieHeader]);
      final ufBody = await responseToString(rUf);
      await saveText(OUT_USERFRAME, ufBody);
    }

    // Optional AJAX init
    try {
      final ts = (DateTime.now().millisecondsSinceEpoch).toString();
      final ajaxUrl = '$BASE$AJAX_USERMSG&ts=$ts';
      final rAjax = await httpGet(
        client,
        Uri.parse(ajaxUrl),
        jar,
        extraHeaders: {
          'Referer': '$BASE$USERFRAMEWORK_PATH',
          'X-Requested-With': 'XMLHttpRequest',
        },
      );
      jar.updateFromSetCookie(rAjax.headers[HttpHeaders.setCookieHeader]);
      final ajaxBody = await responseToString(rAjax);
      await saveText(OUT_AJAX, ajaxBody);
    } catch (_) {}

    // Save cookies to file
    final cookieMap = jar.toMap();
    await File(
      COOKIES_FILE,
    ).writeAsString(json.encode(cookieMap), encoding: utf8);
    print('[+] Saved cookies to $COOKIES_FILE');

    return true;
  } finally {
    client.close(force: true);
  }
}

Future<void> interactiveLoop() async {
  final jar = SimpleCookieJar();
  final username = Platform.environment['JWC_USERNAME'] ?? '2024111748';
  final password =
      Platform.environment['JWC_PASSWORD'] ?? 'replace-with-your-password';
  final stdinLines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  print(
    'Interactive mode. Commands: status / userframework / studentinfo / login / exit',
  );
  final client = HttpClient();
  while (true) {
    stdout.write('cmd> ');
    final line = await stdinLines.first;
    final cmd = line.trim();
    if (cmd == 'exit') break;
    if (cmd == 'status') {
      // check studentinfo
      final codeAndText = await fetchStudentInfoWithJar(jar);
      print(
        'StudentInfo status: ${codeAndText['status']} Logged in? ${codeAndText['logged']}',
      );
      continue;
    } else if (cmd == 'userframework') {
      final res = await fetchUserFrameworkWithJar(jar);
      print('UserFramework status: ${res['status']} (saved to $OUT_USERFRAME)');
      continue;
    } else if (cmd == 'studentinfo') {
      final res = await fetchStudentInfoWithJar(jar);
      print('StudentInfo status: ${res['status']} (saved to $OUT_STUDENTINFO)');
      continue;
    } else if (cmd == 'login') {
      final ok = await casLoginAndFollow(jar, username, password);
      print('Login flow executed; success flag: $ok');
      continue;
    } else {
      print('Unknown command: $cmd');
    }
  }
  client.close(force: true);
}

Future<Map<String, dynamic>> fetchUserFrameworkWithJar(
  SimpleCookieJar jar,
) async {
  final client = HttpClient();
  try {
    final resp = await httpGet(
      client,
      Uri.parse('$BASE$USERFRAMEWORK_PATH'),
      jar,
    );
    jar.updateFromSetCookie(resp.headers[HttpHeaders.setCookieHeader]);
    final body = await responseToString(resp);
    await saveText(OUT_USERFRAME, body);
    return {'status': resp.statusCode, 'text': body};
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> fetchStudentInfoWithJar(
  SimpleCookieJar jar,
) async {
  final client = HttpClient();
  try {
    final resp = await httpGet(
      client,
      Uri.parse('$BASE$STUDENTINFO_PATH'),
      jar,
      extraHeaders: {'Referer': '$BASE$USERFRAMEWORK_PATH'},
    );
    jar.updateFromSetCookie(resp.headers[HttpHeaders.setCookieHeader]);
    final body = await responseToString(resp);
    await saveText(OUT_STUDENTINFO, body);
    final logged = !(body.contains('您还未登陆') || body.contains('非常抱歉，您还未登陆'));
    return {'status': resp.statusCode, 'text': body, 'logged': logged};
  } finally {
    client.close();
  }
}

Future<void> main() async {
  // Simple CLI: run interactive loop
  print('[*] Dart persistent_jwc_session (uses node-runner when needed).');
  await interactiveLoop();
}

// ------------------------------
// Flutter-friendly Service Layer
// ------------------------------

class LoginResult {
  final bool success;
  final String message;
  const LoginResult({required this.success, required this.message});
}

class CasLoginService {
  final SimpleCookieJar _jar = SimpleCookieJar();
  final List<String> _logs = [];
  bool _disposed = false;
  static const String HARD_USERNAME = '2024111748';
  static const String HARD_PASSWORD = 'replace-with-your-password';

  void _addLog(String line) {
    _logs.add(line);
    if (_logs.length > 1000) _logs.removeAt(0);
  }

  List<String> takeLogs() {
    final copy = List<String>.from(_logs);
    _logs.clear();
    return copy;
  }

  Future<bool> loadCookies() async {
    if (_disposed) return false;
    try {
      final f = File(COOKIES_FILE);
      if (!await f.exists()) return false;
      final txt = await f.readAsString(encoding: utf8);
      final Map<String, dynamic> data = json.decode(txt);
      for (final entry in data.entries) {
        final k = entry.key;
        final v = entry.value?.toString() ?? '';
        // 与 Python 行为一致：cookies.json 里的值当作 jwc.swjtu.edu.cn 域的持久化 cookie
        _jar.set(k, v, domain: 'jwc.swjtu.edu.cn');
      }
      _addLog('[*] Loaded cookies from $COOKIES_FILE');
      return true;
    } catch (e) {
      _addLog('[!] Failed to load cookies: $e');
      return false;
    }
  }

  Future<bool> isLoggedIn() async {
    if (_disposed) return false;
    try {
      final res = await fetchStudentInfoWithJar(_jar);
      final logged = (res['logged'] as bool?) ?? false;
      _addLog('StudentInfo status: ${res['status']} Logged in? $logged');
      return logged;
    } catch (e) {
      _addLog('[!] isLoggedIn error: $e');
      return false;
    }
  }

  Future<LoginResult> login(String username, String password) async {
    if (_disposed)
      return const LoginResult(success: false, message: 'Service disposed');
    // 强制使用硬编码账号密码
    username = HARD_USERNAME;
    password = HARD_PASSWORD;
    bool ok = false;
    await runZoned(
      () async {
        ok = await casLoginAndFollow(_jar, username, password);
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) {
          _addLog(message);
          parent.print(zone, message);
        },
      ),
    );
    return LoginResult(success: ok, message: ok ? '登录成功' : '登录失败');
  }

  Future<String?> getUserFramework() async {
    if (_disposed) return null;
    String? content;
    await runZoned(
      () async {
        final res = await fetchUserFrameworkWithJar(_jar);
        content = res['text'] as String?;
        _addLog('UserFramework status: ${res['status']}');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, msg) {
          _addLog(msg);
          parent.print(zone, msg);
        },
      ),
    );
    return content;
  }

  Future<String?> getStudentInfo() async {
    if (_disposed) return null;
    String? content;
    await runZoned(
      () async {
        final res = await fetchStudentInfoWithJar(_jar);
        content = res['text'] as String?;
        _addLog('StudentInfo status: ${res['status']} logged=${res['logged']}');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, msg) {
          _addLog(msg);
          parent.print(zone, msg);
        },
      ),
    );
    return content;
  }

  Future<void> logout() async {
    if (_disposed) return;
    try {
      final f = File(COOKIES_FILE);
      if (await f.exists()) await f.delete();
      _addLog('[*] Logout: cookies file removed');
    } catch (e) {
      _addLog('[!] Logout delete error: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _logs.clear();
  }

  Map<String,String> getCookies() => _jar.toMap();

}

String _randomString(int n) {
  final rnd = Random.secure();
  final buf = StringBuffer();
  for (int i = 0; i < n; i++) {
    buf.write(AES_CHARS[rnd.nextInt(AES_CHARS.length)]);
  }
  return buf.toString();
}

String encryptPasswordFallback(String plain, String keySalt) {
  if (keySalt.isEmpty) return plain;
  final prefix = _randomString(64);
  final ivStr = _randomString(16);
  final full = prefix + plain;
  final blockSize = 16;
  final bytes = utf8.encode(full);
  final padLen = blockSize - (bytes.length % blockSize);
  final padded = List<int>.from(bytes)..addAll(List<int>.filled(padLen, padLen));
  List<int> keyBytes = utf8.encode(keySalt);
  if (!(keyBytes.length == 16 || keyBytes.length == 24 || keyBytes.length == 32)) {
    keyBytes = md5.convert(keyBytes).bytes;
  }
  final key = enc.Key(Uint8List.fromList(keyBytes));
  final iv = enc.IV.fromUtf8(ivStr);
  final cipher = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: null));
  final encrypted = cipher.encryptBytes(padded, iv: iv);
  return base64.encode(encrypted.bytes);
}
