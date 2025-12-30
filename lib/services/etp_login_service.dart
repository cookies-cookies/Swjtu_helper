import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';
import 'dart:io';

/// ETP（实验教学平台）登录结果
class EtpLoginResult {
  final bool success;
  final String message;
  final String? ytoken;
  final String? etpJsessionId;

  const EtpLoginResult({
    required this.success,
    required this.message,
    this.ytoken,
    this.etpJsessionId,
  });
}

/// ETP（实验教学平台）登录服务
/// 通过 CAS 认证获取存储在 localStorage 中的 Ytoken
class EtpLoginService {
  static const String CAS_BASE = 'https://cas.swjtu.edu.cn';
  static const String CAS_LOGIN = '$CAS_BASE/authserver/login';
  static const String ETP_BASE = 'https://etp.swjtu.edu.cn';
  static const String ETP_SERVICE = '$ETP_BASE/yethan/login/cas';
  static const String ETP_INDEX = '$ETP_BASE/yethan/index';

  late final Dio _dio;
  late final CookieJar _cookieJar;

  EtpLoginService() {
    _cookieJar = CookieJar();
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));

    // 日志拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          print('[ETP→] ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          print('[ETP←] ${response.statusCode} ${response.realUri}');
          handler.next(response);
        },
        onError: (error, handler) {
          print('[ETP✗] ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  void dispose() {
    _dio.close();
  }

  /// 通过账号密码登录 ETP 并获取 Ytoken
  ///
  /// 流程类似 VATUU：
  /// 1. 访问 CAS 登录页面（带 service=ETP），提取 salt, lt, execution
  /// 2. 加密密码并 POST 登录
  /// 3. CAS 重定向到 ETP（携带 ticket）
  /// 4. 跟随重定向链，提取 JSESSIONID
  /// 5. 访问 index 页面，从页面中提取 Ytoken（localStorage.setItem）
  Future<EtpLoginResult> login(String username, String password) async {
    try {
      print('[ETP] ========== 开始 ETP CAS 登录 ==========');
      print('[ETP] 账号: $username');

      // 步骤1: 访问 CAS 登录页面（带 ETP service 参数）
      print('[ETP] [1/5] 获取 CAS 登录页面...');
      final casLoginUrl =
          '$CAS_LOGIN?service=${Uri.encodeComponent(ETP_SERVICE)}';
      print('[ETP] CAS URL: $casLoginUrl');

      final loginPageResponse = await _dio.get(casLoginUrl);

      if (loginPageResponse.statusCode != 200) {
        return EtpLoginResult(
          success: false,
          message: '无法访问 CAS 登录页面: ${loginPageResponse.statusCode}',
        );
      }

      final loginHtml = loginPageResponse.data as String;
      print('[ETP] [*] CAS 登录页面响应长度: ${loginHtml.length} 字节');

      // 等待2秒让页面JavaScript加载完成
      print('[ETP] [*] 等待页面加载完成...');
      await Future.delayed(const Duration(seconds: 2));

      // 提取隐藏字段
      final hiddenFields = _parseHiddenFields(loginHtml);
      final salt = hiddenFields['salt'];
      final lt = hiddenFields['lt'] ?? '';
      final execution = hiddenFields['execution'];

      print('[ETP] [DEBUG] 提取结果:');
      print(
        '[ETP]    salt: ${salt != null ? '${salt.length}字符 - ${salt.length > 20 ? salt.substring(0, 20) : salt}...' : 'null'}',
      );
      print('[ETP]    lt: ${lt.isNotEmpty ? '${lt.length}字符' : '空'}');
      print(
        '[ETP]    execution: ${execution != null ? '${execution.length}字符 - ${execution.length > 20 ? execution.substring(0, 20) : execution}...' : 'null'}',
      );

      if (salt == null || execution == null) {
        if (salt == null) print('[ETP] [✗] 未能提取 salt (pwdEncryptSalt)');
        if (execution == null) print('[ETP] [✗] 未能提取 execution');

        // 保存失败的 HTML 以便调试
        await File('debug_etp_login_page_failed.html').writeAsString(loginHtml);
        print('[ETP] [*] 失败的登录页面已保存到 debug_etp_login_page_failed.html');

        return const EtpLoginResult(
          success: false,
          message: '无法提取 CAS 登录参数 (salt/execution)',
        );
      }

      print(
        '[ETP] [*] 表单参数: salt=${salt.length}字符, lt=${lt.length}字符, execution=${execution.length}字符',
      );
      if (lt.isEmpty) {
        print('[ETP] [*] lt 参数为空（正常现象）');
      }

      // 步骤2: 加密密码
      print('[ETP] [2/5] 加密密码...');
      final encryptedPassword = _encryptPassword(password, salt);
      print('[ETP] [*] 密码加密完成，长度: ${encryptedPassword.length}');

      // 步骤3: POST 登录（不自动跟随重定向）
      print('[ETP] [3/5] 提交登录表单...');
      final loginResponse = await _dio.post(
        casLoginUrl,
        data: {
          'username': username,
          'password': encryptedPassword,
          'lt': lt,
          'dllt': 'userNamePasswordLogin',
          'execution': execution,
          '_eventId': 'submit',
          'rmShown': '1',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      print('[ETP] [*] 登录响应状态: ${loginResponse.statusCode}');

      if (loginResponse.statusCode != 302) {
        // 保存错误响应用于调试
        if (loginResponse.data != null) {
          await File(
            'debug_etp_login_error.html',
          ).writeAsString(loginResponse.data.toString());
          print('[ETP] [*] 错误响应已保存到 debug_etp_login_error.html');
        }

        // 检查是否有错误信息
        final errorMsg = _extractErrorMessage(loginResponse.data as String);
        return EtpLoginResult(
          success: false,
          message: errorMsg ?? 'CAS 登录失败: ${loginResponse.statusCode}',
        );
      }

      // 步骤4: 提取 ticket
      final ticketUrl = loginResponse.headers.value('location');
      if (ticketUrl == null || !ticketUrl.contains('ticket=')) {
        return const EtpLoginResult(success: false, message: 'CAS 未返回 ticket');
      }

      // 提取 ticket
      final ticketMatch = RegExp(r'ticket=([^&]+)').firstMatch(ticketUrl);
      final ticket = ticketMatch?.group(1);
      if (ticket != null) {
        print('[ETP] [*] 获取到 ticket: ${ticket.substring(0, 30)}...');
      }
      print(
        '[ETP] [*] Ticket URL: ${ticketUrl.substring(0, ticketUrl.length > 100 ? 100 : ticketUrl.length)}...',
      );

      // 步骤4: 手动跟随重定向链，检查 Ytoken
      print('[ETP] [4/5] 跟随重定向获取 Ytoken...');

      var currentUrl = ticketUrl;
      var redirectCount = 0;
      const maxRedirects = 10;
      String? etpJsessionId;
      String? ytoken;

      while (redirectCount < maxRedirects) {
        print('[ETP] ========== 请求 #$redirectCount ==========');
        final displayUrl = currentUrl.length > 120
            ? '${currentUrl.substring(0, 120)}...'
            : currentUrl;
        print('[ETP] [→ 请求] GET $displayUrl');

        final response = await _dio.get(
          currentUrl,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        final statusCode = response.statusCode;
        print('[ETP] [← 响应] 状态码: $statusCode');

        // 保存第一次响应内容用于调试
        if (redirectCount == 0 && response.data != null) {
          try {
            final html = response.data.toString();
            await File('debug_etp_callback_response.html').writeAsString(html);
            print('[ETP] [*] 回调响应已保存到: debug_etp_callback_response.html');
            print('[ETP] [*] 响应长度: ${html.length} 字节');

            // 从 HTML 中提取 Ytoken
            final ytokenRegex = RegExp(
              r"localStorage\.setItem\([" +
                  "'" +
                  r']ytoken[' +
                  "'" +
                  r']\s*,\s*[' +
                  "'" +
                  r'"]([^' +
                  "'" +
                  r'"]+)[' +
                  "'" +
                  r'"]',
              caseSensitive: false,
            );
            final ytokenMatch = ytokenRegex.firstMatch(html);
            if (ytokenMatch != null) {
              ytoken = ytokenMatch.group(1);
              if (ytoken != null) {
                print('[ETP] ✅ 从 callback 页面提取到 Ytoken!');
                print('[ETP]    长度: ${ytoken.length} 字符');
                final displayYtoken = ytoken.length > 60
                    ? '${ytoken.substring(0, 60)}...'
                    : ytoken;
                print('[ETP]    内容: $displayYtoken');
              }
            }
          } catch (e) {
            print('[ETP] [!] 保存/提取回调响应失败: $e');
          }
        }

        // 检查并显示关键响应头
        final ytokenHeader = response.headers.value('ytoken');
        final locationHeader = response.headers.value('location');
        final setCookies = response.headers['set-cookie'] ?? [];

        if (ytokenHeader != null) {
          final displayYtoken = ytokenHeader.length > 50
              ? '${ytokenHeader.substring(0, 50)}...'
              : ytokenHeader;
          print('[ETP] [*] 响应头包含 Ytoken: $displayYtoken');
        }

        if (locationHeader != null) {
          final displayLoc = locationHeader.length > 100
              ? '${locationHeader.substring(0, 100)}...'
              : locationHeader;
          print('[ETP] [*] Location: $displayLoc');
        }

        if (setCookies.isNotEmpty) {
          print('[ETP] [*] Set-Cookie 数量: ${setCookies.length}');
          for (final cookie in setCookies) {
            if (cookie.startsWith('JSESSIONID=')) {
              final jsid = cookie.split('=')[1].split(';')[0];
              final displayJsid = jsid.length > 16
                  ? '${jsid.substring(0, 16)}...'
                  : jsid;
              print('[ETP]     → JSESSIONID: $displayJsid');
            }
          }
        }

        // 检查响应头中的 Ytoken
        if (ytokenHeader != null && ytokenHeader.isNotEmpty) {
          ytoken = ytokenHeader;
          print('[ETP] ✅ 从响应头获取到 Ytoken!');
          print('[ETP]    长度: ${ytoken.length} 字符');
          final displayFullYtoken = ytoken.length > 60
              ? '${ytoken.substring(0, 60)}...'
              : ytoken;
          print('[ETP]    内容: $displayFullYtoken');
        }

        // 收集 JSESSIONID
        for (final cookie in setCookies) {
          if (cookie.startsWith('JSESSIONID=') &&
              !cookie.startsWith('JSESSIONID=;')) {
            etpJsessionId = cookie.split('=')[1].split(';')[0];
            final displayJsid = etpJsessionId.substring(
              0,
              etpJsessionId.length > 16 ? 16 : etpJsessionId.length,
            );
            print('[ETP] [*] 提取 ETP JSESSIONID: $displayJsid...');

            // 手动设置到 CookieJar
            final cookieObj = Cookie('JSESSIONID', etpJsessionId);
            cookieObj.domain = 'etp.swjtu.edu.cn';
            cookieObj.path = '/';
            await _cookieJar.saveFromResponse(Uri.parse(ETP_BASE), [cookieObj]);
            print(
              '[ETP] [✓] 已将 JSESSIONID 设置到 CookieJar (domain: etp.swjtu.edu.cn)',
            );
          }
        }

        // 如果找到 Ytoken 且状态码是 200，完成
        if (ytoken != null && statusCode == 200) {
          print('[ETP] ========== 登录成功！ ==========');
          final displayYtoken = ytoken.substring(
            0,
            ytoken.length > 60 ? 60 : ytoken.length,
          );
          print('[ETP] [✓] Ytoken: $displayYtoken...');
          if (etpJsessionId != null) {
            final displayJsid = etpJsessionId.substring(
              0,
              etpJsessionId.length > 16 ? 16 : etpJsessionId.length,
            );
            print('[ETP] [✓] JSESSIONID: $displayJsid...');
          } else {
            print('[ETP] [!] JSESSIONID: 无');
          }
          return EtpLoginResult(
            success: true,
            message: '登录成功',
            ytoken: ytoken,
            etpJsessionId: etpJsessionId,
          );
        }

        // 处理重定向
        if (statusCode == 302 || statusCode == 301) {
          final location = response.headers.value('location');
          if (location == null) {
            print('[ETP] ❌ 状态码 $statusCode 但 Location 头为空');
            return EtpLoginResult(
              success: false,
              message: '重定向响应缺少 Location 头',
              etpJsessionId: etpJsessionId,
            );
          }

          print('[ETP] [*] 检测到重定向 ($statusCode)');

          // 检查是否包含 ticket
          if (location.contains('ticket=')) {
            final ticketMatch = RegExp(r'ticket=([^&]+)').firstMatch(location);
            if (ticketMatch != null) {
              final ticket = ticketMatch.group(1);
              final displayTicket = ticket!.length > 30
                  ? '${ticket.substring(0, 30)}...'
                  : ticket;
              print('[ETP] [*] Location 包含 ticket: $displayTicket');
            }
          }

          // 构建绝对 URL
          if (location.startsWith('http')) {
            currentUrl = location;
          } else if (location.startsWith('/')) {
            final uri = Uri.parse(currentUrl);
            currentUrl = '${uri.scheme}://${uri.host}$location';
          } else {
            final uri = Uri.parse(currentUrl);
            final path = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
            currentUrl = '${uri.scheme}://${uri.host}$path$location';
          }

          final displayNextUrl = currentUrl.length > 100
              ? '${currentUrl.substring(0, 100)}...'
              : currentUrl;
          print('[ETP] [→] 跟随重定向到: $displayNextUrl');

          // 等待3秒让页面加载完成
          print('[ETP] [*] 等待页面加载...');
          await Future.delayed(const Duration(seconds: 3));

          redirectCount++;
          continue;
        }

        // 200 响应但没有 Ytoken，检查是否有 meta refresh 或 JavaScript 跳转
        if (statusCode == 200) {
          print('[ETP] [*] 收到 200 响应，检查页面跳转...');

          // 检查响应内容
          if (response.data != null) {
            final html = response.data.toString();

            // 1. 检查 meta refresh
            final metaRefreshRegex = RegExp(
              r'<meta[^>]*http-equiv=["' +
                  "'" +
                  r']?refresh["' +
                  "'" +
                  r']?[^>]*content=["' +
                  "'" +
                  r']?\d+;\s*url=([^"' +
                  "'" +
                  r'>\s]+)',
              caseSensitive: false,
            );
            final metaMatch = metaRefreshRegex.firstMatch(html);

            if (metaMatch != null) {
              var nextUrl = metaMatch.group(1)!;
              print(
                '[ETP] [*] 检测到 meta refresh: ${nextUrl.substring(0, nextUrl.length > 80 ? 80 : nextUrl.length)}...',
              );

              // 构建绝对 URL
              if (!nextUrl.startsWith('http')) {
                if (nextUrl.startsWith('/')) {
                  final uri = Uri.parse(currentUrl);
                  nextUrl = '${uri.scheme}://${uri.host}$nextUrl';
                } else {
                  final uri = Uri.parse(currentUrl);
                  final path = uri.path.substring(
                    0,
                    uri.path.lastIndexOf('/') + 1,
                  );
                  nextUrl = '${uri.scheme}://${uri.host}$path$nextUrl';
                }
              }

              // 等待 meta refresh 的延迟时间（通常是 0-3 秒）
              final delayMatch = RegExp(
                r'content=["' + "'" + r']?(\d+);',
              ).firstMatch(html);
              if (delayMatch != null) {
                final delaySec = int.tryParse(delayMatch.group(1)!) ?? 0;
                if (delaySec > 0 && delaySec <= 3) {
                  print('[ETP] [*] 等待 meta refresh 延迟 $delaySec 秒...');
                  await Future.delayed(Duration(seconds: delaySec));
                }
              }

              currentUrl = nextUrl;
              print(
                '[ETP] [→] 跟随 meta refresh 到: ${currentUrl.substring(0, currentUrl.length > 100 ? 100 : currentUrl.length)}...',
              );

              // 等待3秒让页面加载完成
              print('[ETP] [*] 等待页面加载...');
              await Future.delayed(const Duration(seconds: 3));

              redirectCount++;
              continue;
            }

            // 2. 检查 JavaScript window.location 跳转
            final jsLocationRegex = RegExp(
              r'window\.location(?:\.href)?\s*=\s*["' +
                  "'" +
                  r']([^"' +
                  "'" +
                  r']+)["' +
                  "'" +
                  r']',
              caseSensitive: false,
            );
            final jsMatch = jsLocationRegex.firstMatch(html);

            if (jsMatch != null) {
              var nextUrl = jsMatch.group(1)!;
              print(
                '[ETP] [*] 检测到 JavaScript 跳转: ${nextUrl.substring(0, nextUrl.length > 80 ? 80 : nextUrl.length)}...',
              );

              // 构建绝对 URL
              if (!nextUrl.startsWith('http')) {
                if (nextUrl.startsWith('/')) {
                  final uri = Uri.parse(currentUrl);
                  nextUrl = '${uri.scheme}://${uri.host}$nextUrl';
                } else {
                  final uri = Uri.parse(currentUrl);
                  final path = uri.path.substring(
                    0,
                    uri.path.lastIndexOf('/') + 1,
                  );
                  nextUrl = '${uri.scheme}://${uri.host}$path$nextUrl';
                }
              }

              currentUrl = nextUrl;
              print(
                '[ETP] [→] 跟随 JavaScript 跳转到: ${currentUrl.substring(0, currentUrl.length > 100 ? 100 : currentUrl.length)}...',
              );

              // 等待3秒让页面加载完成
              print('[ETP] [*] 等待页面加载...');
              await Future.delayed(const Duration(seconds: 3));

              redirectCount++;
              continue;
            }
          }

          // 如果没有找到跳转，且还没有 Ytoken，尝试访问常见的 API 端点
          if (ytoken == null && etpJsessionId != null) {
            print('[ETP] [5/5] 未检测到页面跳转，尝试访问 API 端点获取 Ytoken...');

            // 尝试访问 index 页面
            print('[ETP] [→ 请求] GET $ETP_BASE/yethan/index');
            final indexResponse = await _dio.get(
              '$ETP_BASE/yethan/index',
              options: Options(followRedirects: false),
            );

            print('[ETP] [← 响应] 状态码: ${indexResponse.statusCode}');

            // 保存响应内容
            if (indexResponse.data != null) {
              try {
                final indexHtml = indexResponse.data.toString();
                await File('debug_etp_index.html').writeAsString(indexHtml);
                print('[ETP] [*] index 页面已保存到: debug_etp_index.html');
                print('[ETP] [*] 响应长度: ${indexHtml.length} 字节');
              } catch (e) {
                print('[ETP] [!] 保存 index 页面失败: $e');
              }
            }

            final indexYtoken = indexResponse.headers.value('ytoken');
            if (indexYtoken != null && indexYtoken.isNotEmpty) {
              ytoken = indexYtoken;
              final displayYtoken = indexYtoken.length > 60
                  ? '${indexYtoken.substring(0, 60)}...'
                  : indexYtoken;
              print('[ETP] ✅ 从 index 页面获取到 Ytoken!');
              print('[ETP]    长度: ${ytoken.length} 字符');
              print('[ETP]    内容: $displayYtoken');

              print('[ETP] ========== 登录成功！ ==========');
              final displayJsid = etpJsessionId.substring(
                0,
                etpJsessionId.length > 16 ? 16 : etpJsessionId.length,
              );
              print('[ETP] [✓] Ytoken: $displayYtoken...');
              print('[ETP] [✓] JSESSIONID: $displayJsid...');
              return EtpLoginResult(
                success: true,
                message: '登录成功',
                ytoken: ytoken,
                etpJsessionId: etpJsessionId,
              );
            }

            // 如果 index 页面也没有，尝试配置页面
            print('[ETP] [→ 请求] GET $ETP_BASE/yethan/public/sys/config/web');
            final configResponse = await _dio.get(
              '$ETP_BASE/yethan/public/sys/config/web',
              options: Options(
                headers: {
                  'X-Requested-With': 'XMLHttpRequest',
                  'Referer': '$ETP_BASE/yethan/index',
                },
              ),
            );

            print('[ETP] [← 响应] 状态码: ${configResponse.statusCode}');

            // 保存响应内容
            if (configResponse.data != null) {
              try {
                final configData = configResponse.data.toString();
                await File('debug_etp_config.json').writeAsString(configData);
                print('[ETP] [*] 配置页面已保存到: debug_etp_config.json');
                print('[ETP] [*] 响应长度: ${configData.length} 字节');
                print(
                  '[ETP] [*] 响应内容: ${configData.substring(0, configData.length > 200 ? 200 : configData.length)}...',
                );
              } catch (e) {
                print('[ETP] [!] 保存配置页面失败: $e');
              }
            }

            // 打印所有响应头
            print('[ETP] [*] 响应头:');
            configResponse.headers.forEach((name, values) {
              print('[ETP]     $name: ${values.join(", ")}');
            });

            final configYtoken = configResponse.headers.value('ytoken');
            if (configYtoken != null && configYtoken.isNotEmpty) {
              ytoken = configYtoken;
              final displayYtoken = configYtoken.length > 60
                  ? '${configYtoken.substring(0, 60)}...'
                  : configYtoken;
              print('[ETP] ✅ 从配置页面获取到 Ytoken!');
              print('[ETP]    长度: ${ytoken.length} 字符');
              print('[ETP]    内容: $displayYtoken');

              print('[ETP] ========== 登录成功！ ==========');
              final displayJsid = etpJsessionId.substring(
                0,
                etpJsessionId.length > 16 ? 16 : etpJsessionId.length,
              );
              print('[ETP] [✓] Ytoken: $displayYtoken...');
              print('[ETP] [✓] JSESSIONID: $displayJsid...');
              return EtpLoginResult(
                success: true,
                message: '登录成功',
                ytoken: ytoken,
                etpJsessionId: etpJsessionId,
              );
            } else {
              print('[ETP] [!] 配置页面响应头未包含 Ytoken');
            }
          }

          // 没有更多重定向，结束循环
          print('[ETP] ⚠ 未能获取 Ytoken');
          return EtpLoginResult(
            success: false,
            message: '登录成功但未能提取 Ytoken',
            etpJsessionId: etpJsessionId,
          );
        }

        // 其他状态码
        print('[ETP] ❌ 意外的状态码: $statusCode');
        return EtpLoginResult(
          success: false,
          message: '重定向过程出现异常状态码: $statusCode',
          etpJsessionId: etpJsessionId,
        );
      }

      print('[ETP] ❌ 达到最大重定向次数 ($maxRedirects)');
      return EtpLoginResult(
        success: false,
        message: '达到最大重定向次数',
        etpJsessionId: etpJsessionId,
      );
    } catch (e, stackTrace) {
      print('[ETP] ✗ 异常: $e');
      print('[ETP] ✗ 堆栈: $stackTrace');
      return EtpLoginResult(success: false, message: '登录异常: $e');
    }
  }

  /// 从 HTML 提取隐藏字段（salt, lt, execution）
  Map<String, String?> _parseHiddenFields(String html) {
    final Map<String, String?> fields = {};

    // 提取 salt (pwdEncryptSalt)
    final saltMatch = RegExp(
      r'id="pwdEncryptSalt"[^>]*value="([^"]*)"',
    ).firstMatch(html);
    fields['salt'] = saltMatch?.group(1);

    // 提取 lt
    final ltMatch = RegExp(r'name="lt"[^>]*value="([^"]*)"').firstMatch(html);
    fields['lt'] = ltMatch?.group(1);

    // 提取 execution
    final executionMatch = RegExp(
      r'name="execution"[^>]*value="([^"]*)"',
    ).firstMatch(html);
    fields['execution'] = executionMatch?.group(1);

    return fields;
  }

  /// AES 加密密码
  String _encryptPassword(String password, String keySalt) {
    // 生成随机 64 字符前缀
    const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
    final random = Random.secure();
    final randomPrefix = List.generate(
      64,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    // 生成随机 16 字符 IV
    final randomIv = List.generate(
      16,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    // 准备密钥和 IV
    final key = encrypt.Key.fromUtf8(keySalt);
    final iv = encrypt.IV.fromUtf8(randomIv);

    // 加密
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(randomPrefix + password, iv: iv);

    return encrypted.base64;
  }

  /// 从响应中提取错误信息
  String? _extractErrorMessage(String html) {
    final errorMatch = RegExp(
      r'<span[^>]*id="errorMsg"[^>]*>([^<]+)</span>',
    ).firstMatch(html);
    return errorMatch?.group(1)?.trim();
  }
}
