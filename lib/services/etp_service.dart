import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 实验教学平台服务 (etp.swjtu.edu.cn)
/// 使用 JWT Token (Ytoken) 进行认证
const String ETP_BASE = 'https://etp.swjtu.edu.cn';

class EtpService {
  String? _ytoken;
  final List<String> _logs = [];

  void _addLog(String line) {
    _logs.add(line);
    if (_logs.length > 1000) _logs.removeAt(0);
    print('[ETP] $line');
  }

  List<String> takeLogs() {
    final copy = List<String>.from(_logs);
    _logs.clear();
    return copy;
  }

  String? get ytoken => _ytoken;

  /// 设置 Ytoken
  void setYtoken(String token) {
    _ytoken = token;
    _addLog('设置 Ytoken (长度: ${token.length})');
  }

  /// 使用账号密码登录 ETP 并获取 Ytoken
  /// TODO: 等待抓包分析后实现
  Future<bool> loginWithCredentials(String username, String password) async {
    _addLog('TODO: 登录功能待实现');
    _addLog('请先通过浏览器抓包,获取完整的登录请求信息');
    return false;
  }

  /// 通过已有的 JSESSIONID (VATUU 登录态) 自动获取 Ytoken
  /// 原理: VATUU 和 ETP 共用同一个 CAS 认证中心
  /// 流程: 先访问VATUU获取CASTGC → 用CASTGC访问ETP → CAS返回ticket → ETP回调页面设置ytoken
  Future<bool> getYtokenWithJSessionId(String jsessionid) async {
    try {
      _addLog('=== 开始通过 CAS 认证获取 Ytoken ===');
      _addLog('JSESSIONID: ${jsessionid.substring(0, 8)}...');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (cert, host, port) => true;

      // Step 1: 先访问 VATUU 获取 CASTGC cookie
      _addLog('Step 1: 访问 VATUU 触发 CAS 认证获取 CASTGC');
      final vatuuUrl = 'https://jwc.swjtu.edu.cn/vatuu/UserFramework';

      final request1 = await client.getUrl(Uri.parse(vatuuUrl));
      request1.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      request1.headers.set('Cookie', 'JSESSIONID=$jsessionid');

      final response1 = await request1.close();
      _addLog('VATUU 响应: ${response1.statusCode}');

      // 输出所有响应头
      response1.headers.forEach((name, values) {
        _addLog('  Header [$name]: ${values.join(", ")}');
      });

      // 收集 CASTGC
      String? castgc;
      final setCookies1 = response1.headers['set-cookie'] ?? [];
      _addLog('Set-Cookie 数量: ${setCookies1.length}');

      for (final cookie in setCookies1) {
        _addLog(
          '  Cookie: ${cookie.substring(0, cookie.length > 100 ? 100 : cookie.length)}...',
        );

        if (cookie.startsWith('CASTGC=') && !cookie.startsWith('CASTGC=;')) {
          castgc = cookie.split('=')[1].split(';')[0];
          _addLog('✅ 从 VATUU 获取到 CASTGC: ${castgc.substring(0, 20)}...');
          break;
        }
      }

      await response1.drain();

      if (castgc == null || castgc.isEmpty) {
        _addLog('❌ 未能从 VATUU 获取 CASTGC');
        _addLog('   可能原因1: JSESSIONID 已过期');
        _addLog('   可能原因2: VATUU 未触发 CAS 重定向');
        _addLog('   建议: 重新执行 VATUU 登录获取新的 JSESSIONID');
        client.close();
        return false;
      }

      // Step 2: 用 CASTGC 访问 ETP,触发 CAS 认证
      _addLog('Step 2: 用 CASTGC 访问 ETP 触发 CAS 重定向');
      final etpIndexUrl = 'https://etp.swjtu.edu.cn/user/yethan/index/student';

      var currentUrl = etpIndexUrl;
      var redirectCount = 0;
      const maxRedirects = 10;
      String? etpJSessionId;

      // 手动跟随重定向链
      while (redirectCount < maxRedirects) {
        _addLog('======== 请求 #$redirectCount ========');
        _addLog(
          'URL: ${currentUrl.length > 100 ? currentUrl.substring(0, 100) + "..." : currentUrl}',
        );

        final request = await client.getUrl(Uri.parse(currentUrl));
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
        );
        request.headers.set(
          'Accept',
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        );

        // 根据当前域名设置 Cookie
        final cookieParts = <String>[];
        if (currentUrl.contains('etp.swjtu.edu.cn')) {
          if (etpJSessionId != null) {
            cookieParts.add('JSESSIONID=$etpJSessionId');
          }
          request.headers.set('Referer', 'https://etp.swjtu.edu.cn/');
        } else if (currentUrl.contains('cas.swjtu.edu.cn')) {
          cookieParts.add('CASTGC=$castgc');
        }

        if (cookieParts.isNotEmpty) {
          final cookieHeader = cookieParts.join('; ');
          request.headers.set('Cookie', cookieHeader);
          _addLog(
            'Cookie: ${cookieHeader.substring(0, cookieHeader.length > 100 ? 100 : cookieHeader.length)}...',
          );
        } else {
          _addLog('Cookie: (无)');
        }

        final response = await request.close();
        final statusCode = response.statusCode;
        _addLog('响应: $statusCode');

        // 收集 cookies
        final setCookies = response.headers['set-cookie'] ?? [];
        for (final cookie in setCookies) {
          final parts = cookie.split('=');
          if (parts.length >= 2) {
            final name = parts[0];
            final value = parts[1].split(';')[0];

            if (name == 'JSESSIONID' &&
                currentUrl.contains('etp.swjtu.edu.cn')) {
              etpJSessionId = value;
              _addLog('获取 ETP JSESSIONID: ${value.substring(0, 10)}...');
            }
          }
        }

        // 处理重定向
        if (statusCode == 302 || statusCode == 301) {
          final location = response.headers.value('location');
          _addLog('Location: ${location ?? "(空)"}');

          if (location != null) {
            // 检查是否包含 ticket
            if (location.contains('ticket=')) {
              final ticketMatch = RegExp(
                r'ticket=([^&]+)',
              ).firstMatch(location);
              if (ticketMatch != null) {
                final ticket = ticketMatch.group(1);
                _addLog('✅ 获取到 ticket: ${ticket!.substring(0, 30)}...');
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

            _addLog(
              '重定向到: ${currentUrl.length > 100 ? currentUrl.substring(0, 100) + "..." : currentUrl}',
            );

            await response.drain();
            redirectCount++;
            continue;
          }
        }

        // 200 响应,读取内容
        if (statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          final body = utf8.decode(bytes);

          _addLog('最终响应长度: ${body.length} 字节');
          _addLog('响应前 500 字符:');
          _addLog(body.substring(0, body.length > 500 ? 500 : body.length));

          // 保存响应
          try {
            final file = File('debug_etp_callback_response.html');
            await file.writeAsString(body);
            _addLog('响应已保存到: ${file.absolute.path}');
          } catch (e) {
            _addLog('[WARN] 保存文件失败: $e');
          }

          // 从 localStorage.setItem 中提取 ytoken
          final ytokenPattern = RegExp(
            r"localStorage\.setItem\s*\(\s*['\x22]ytoken['\x22]\s*,\s*['\x22]([^'\x22]+)['\x22]",
            caseSensitive: false,
          );

          final ytokenMatch = ytokenPattern.firstMatch(body);

          if (ytokenMatch != null) {
            final token = ytokenMatch.group(1);
            if (token != null && token.length > 50) {
              _ytoken = token;
              _addLog('✅ 成功提取 Ytoken!');
              _addLog('Ytoken 长度: ${token.length}');
              _addLog('Ytoken 前缀: ${token.substring(0, 40)}...');

              client.close();
              return true;
            }
          }

          _addLog('❌ 响应中未找到 ytoken');
          client.close();
          return false;
        }

        // 其他状态码
        _addLog('❌ 意外的状态码: $statusCode');
        await response.drain();
        client.close();
        return false;
      }

      _addLog('❌ 达到最大重定向次数');
      client.close();
      return false;
    } catch (e) {
      _addLog('❌ 获取 Ytoken 失败: $e');
      return false;
    }
  }

  /// 获取实验选课列表
  /// xqm: 学期码 (例如: 120)
  /// pageNum: 页码 (从1开始)
  /// pageSize: 每页数量
  /// 获取实验选课列表（返回完整响应，包括分页信息）
  Future<Map<String, dynamic>?> getExperimentCourseListWithPagination({
    required String xqm,
    int pageNum = 1,
    int pageSize = 20,
    int totalNum = 0,
    String key = '',
    String value = '',
  }) async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      final url =
          '$ETP_BASE/user/yethan/student/studentList/listPage?'
          'xqm=$xqm&pageSize=$pageSize&pageNum=$pageNum&totalNum=$totalNum'
          '&key=$key&value=$value';

      _addLog('请求实验选课列表: 学期=$xqm, 页码=$pageNum/$pageSize');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));

      // 设置请求头
      request.headers.set('Host', 'etp.swjtu.edu.cn');
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set(
        'Accept',
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/index/student/studentList',
      );

      final response = await request.close();
      final statusCode = response.statusCode;

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);

      // 解析 JSON
      final json = jsonDecode(content) as Map<String, dynamic>;

      client.close();
      return json;
    } catch (e) {
      _addLog('[ERROR] 获取实验选课列表失败: $e');
      return null;
    }
  }

  /// 获取实验选课列表（返回解析后的数据）
  Future<List<dynamic>?> getExperimentCourseList({
    required String xqm,
    int pageNum = 1,
    int pageSize = 20,
    int totalNum = 0,
    String key = '',
    String value = '',
  }) async {
    final response = await getExperimentCourseListWithPagination(
      xqm: xqm,
      pageNum: pageNum,
      pageSize: pageSize,
      totalNum: totalNum,
      key: key,
      value: value,
    );

    if (response == null) {
      return null;
    }

    // 提取 data 数组
    final dataList = response['data'] as List?;

    if (dataList == null) {
      _addLog('[ERROR] 响应格式错误: 无法找到数据列表');
      return null;
    }

    _addLog('成功获取数据: 共 ${dataList.length} 条');

    // 保存为 JSON 文件以便调试
    try {
      final formatted = const JsonEncoder.withIndent('  ').convert(response);
      final file = File('debug_etp_course_list_page$pageNum.json');
      await file.writeAsString(formatted);
      _addLog('已保存到: ${file.path}');
    } catch (e) {
      _addLog('[WARN] 保存文件失败: $e');
    }

    return dataList;
  }

  /// 获取实验成绩列表（页面HTML）
  Future<String?> getExperimentScoreListPage() async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = '$ETP_BASE/user/yethan/score/scoreListPage?_=$timestamp';

      _addLog('请求实验成绩页面');
      _addLog('URL: $url');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));

      // 设置请求头
      request.headers.set('Host', 'etp.swjtu.edu.cn');
      request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
      request.headers.set(
        'Sec-Ch-Ua',
        '"Chromium";v="139", "Not;A=Brand";v="99"',
      );
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set('Sec-Ch-Ua-Mobile', '?0');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      request.headers.set('Accept', 'text/html, */*; q=0.01');
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Sec-Fetch-Mode', 'cors');
      request.headers.set('Sec-Fetch-Dest', 'empty');
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/index/student/studentList',
      );
      request.headers.set('Accept-Encoding', 'gzip, deflate, br');
      request.headers.set('Priority', 'u=1, i');

      final response = await request.close();
      final statusCode = response.statusCode;
      _addLog('状态码: $statusCode');

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);

      _addLog('响应长度: ${content.length} 字节');

      // 保存响应到文件
      try {
        final file = File('debug_etp_score_list.html');
        await file.writeAsString(content);
        _addLog('响应已保存到: ${file.absolute.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      client.close();
      return content;
    } catch (e) {
      _addLog('[ERROR] 获取实验成绩页面失败: $e');
      return null;
    }
  }

  /// 获取实验成绩列表数据（JSON API）
  Future<Map<String, dynamic>?> getExperimentScoreList({
    String? xqm,
    int pageNum = 1,
    int pageSize = 20,
    String? key,
    String? value,
  }) async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      // 构建查询参数
      final queryParams = <String, String>{
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      };

      if (xqm != null && xqm.isNotEmpty) {
        queryParams['xqm'] = xqm;
      }
      if (key != null && key.isNotEmpty) {
        queryParams['key'] = key;
      }
      if (value != null && value.isNotEmpty) {
        queryParams['value'] = value;
      }

      final uri = Uri.parse(
        '$ETP_BASE/user/yethan/score/scoreList/listPage',
      ).replace(queryParameters: queryParams);

      _addLog('请求实验成绩数据');
      _addLog('URL: $uri');
      _addLog('参数: 学期=$xqm, 页码=$pageNum, 每页=$pageSize');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(uri);

      // 设置请求头
      request.headers.set('Host', 'etp.swjtu.edu.cn');
      request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
      request.headers.set(
        'Sec-Ch-Ua',
        '"Chromium";v="139", "Not;A=Brand";v="99"',
      );
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set('Sec-Ch-Ua-Mobile', '?0');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      request.headers.set(
        'Accept',
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Sec-Fetch-Mode', 'cors');
      request.headers.set('Sec-Fetch-Dest', 'empty');
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/score/scoreListPage',
      );
      request.headers.set('Accept-Encoding', 'gzip, deflate, br');
      request.headers.set('Priority', 'u=1, i');

      final response = await request.close();
      final statusCode = response.statusCode;
      _addLog('状态码: $statusCode');

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);

      _addLog('响应长度: ${content.length} 字节');

      // 解析 JSON
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 保存响应到文件
      try {
        final file = File('debug_etp_score_list_page$pageNum.json');
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
        );
        _addLog('数据已保存到: ${file.absolute.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      if (json['code'] == '00000' || json['status'] == true) {
        final total = json['total'] ?? 0;
        final dataList = json['data'] as List?;
        _addLog('✅ 成功获取: 共 $total 条记录');
        if (dataList != null) {
          _addLog('   当前页: ${dataList.length} 条');
        }
      } else {
        _addLog('❌ API 返回失败: ${json['msg'] ?? json['message'] ?? '未知错误'}');
      }

      client.close();
      return json;
    } catch (e) {
      _addLog('[ERROR] 获取实验成绩数据失败: $e');
      return null;
    }
  }

  /// 获取所有页的实验选课数据
  Future<List<List<dynamic>>> getAllExperimentCoursePages({
    required String xqm,
    int pageSize = 20,
  }) async {
    final List<List<dynamic>> allPages = [];

    // 先获取第一页完整响应以获取总页数
    final firstResponse = await getExperimentCourseListWithPagination(
      xqm: xqm,
      pageNum: 1,
      pageSize: pageSize,
    );

    if (firstResponse == null) {
      _addLog('[ERROR] 获取第一页失败');
      return allPages;
    }

    // 解析第一页数据
    final firstPageData = firstResponse['data'] as List?;
    if (firstPageData == null || firstPageData.isEmpty) {
      _addLog('[ERROR] 第一页数据为空');
      return allPages;
    }

    allPages.add(firstPageData);
    _addLog('第 1 页: ${firstPageData.length} 条记录');

    // 解析总页数
    final totalPages = firstResponse['totalPages'] as int? ?? 1;
    final total = firstResponse['total'] as int? ?? 0;
    _addLog('总共 $totalPages 页, $total 条记录');

    // 如果只有一页，直接返回
    if (totalPages <= 1) {
      _addLog('获取完成: 共 1 页, ${firstPageData.length} 条记录');
      return allPages;
    }

    // 循环获取剩余的页
    for (int page = 2; page <= totalPages; page++) {
      _addLog('正在获取第 $page 页...');

      // 延迟 500ms 避免请求过快
      await Future.delayed(const Duration(milliseconds: 500));

      final pageData = await getExperimentCourseList(
        xqm: xqm,
        pageNum: page,
        pageSize: pageSize,
      );

      if (pageData == null || pageData.isEmpty) {
        _addLog('[WARN] 第 $page 页获取失败或为空');
        continue;
      }

      allPages.add(pageData);
      _addLog('第 $page 页: ${pageData.length} 条记录');
    }

    final totalRecords = allPages.fold<int>(
      0,
      (sum, page) => sum + page.length,
    );
    _addLog('获取完成: 共 ${allPages.length} 页, $totalRecords 条记录');

    return allPages;
  }

  /// 获取评价模板
  /// 获取评价模板ID (第一步)
  Future<String?> getEvaluateTemplateId() async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      final uri = Uri.parse(
        '$ETP_BASE/user/yethan/experimentEvaluateTemplate/infoQy',
      );

      _addLog('获取评价模板ID');
      _addLog('URL: $uri');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(uri);
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set(
        'Accept',
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/index/score/scoreListPage',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      _addLog('状态码: $statusCode');

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);
      final json = jsonDecode(content) as Map<String, dynamic>;

      if (json['code'] == '00000' && json['data'] != null) {
        final mbh = json['data']['mbh'] as String?;
        _addLog('✅ 模板ID: $mbh');
        return mbh;
      } else {
        _addLog('[ERROR] 获取模板ID失败: ${json['message']}');
        client.close();
        return null;
      }
    } catch (e) {
      _addLog('[ERROR] 获取模板ID失败: $e');
      return null;
    }
  }

  /// 获取完整评价模板 (第二步)
  Future<Map<String, dynamic>?> getEvaluateTemplate(String mbh) async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      final uri = Uri.parse(
        '$ETP_BASE/user/yethan/experimentEvaluateTemplate/info/$mbh',
      );

      _addLog('获取完整评价模板');
      _addLog('URL: $uri');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(uri);
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set(
        'Accept',
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/index/score/scoreListPage',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      _addLog('状态码: $statusCode');

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 保存响应
      try {
        final file = File('debug_evaluate_template_full.json');
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
        );
        _addLog('完整评价模板已保存: ${file.absolute.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      if (json['code'] == '00000') {
        final titles = (json['data']['titles'] as List?)?.length ?? 0;
        _addLog('✅ 模板包含 $titles 个题目');
      }

      client.close();
      return json;
    } catch (e) {
      _addLog('[ERROR] 获取评价模板失败: $e');
      return null;
    }
  }

  /// 提交实验评价
  ///
  /// [experimentId] 实验记录ID (成绩列表中的id字段)
  /// [template] 评价模板 (包含题目和选项)
  Future<Map<String, dynamic>?> submitEvaluation({
    required String experimentId,
    required Map<String, dynamic> template,
  }) async {
    if (_ytoken == null) {
      _addLog('[ERROR] Ytoken 未设置');
      return null;
    }

    try {
      final uri = Uri.parse('$ETP_BASE/user/yethan/score/scoreList/sumFs2');

      _addLog('提交实验评价');
      _addLog('URL: $uri');
      _addLog('实验ID: $experimentId');

      // 解析模板,构建评价项
      final titles =
          (template['data']['titles'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      final items = <Map<String, String>>[];

      for (final title in titles) {
        final pjbth = title['pjbth'] as String; // 题目ID
        final options =
            (title['optionBeanList'] as List?)?.cast<Map<String, dynamic>>() ??
            [];

        if (options.isNotEmpty) {
          // 选择第一个选项 ("非常满意")
          final firstOption = options[0];
          final pjxxh = firstOption['sid'] as String; // 选项ID

          items.add({'pjbth': pjbth, 'pjxxh': pjxxh});
        }
      }

      _addLog('评价项数量: ${items.length}');

      // 构建请求体
      final payload = {'sid': experimentId, 'items': items};

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.postUrl(uri);
      request.headers.set('Ytoken', _ytoken!);
      request.headers.set('Content-Type', 'application/json;charset=UTF-8');
      request.headers.set(
        'Accept',
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set('Origin', ETP_BASE);
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set(
        'Referer',
        '$ETP_BASE/user/yethan/index/score/scoreListPage',
      );

      // 写入请求体
      final bodyStr = jsonEncode(payload);
      request.write(bodyStr);

      final response = await request.close();
      final statusCode = response.statusCode;
      _addLog('状态码: $statusCode');

      final bytes = await consolidateHttpClientResponseBytes(response);
      final content = utf8.decode(bytes);

      if (statusCode != 200) {
        _addLog('[ERROR] 提交失败: HTTP $statusCode');
        _addLog('响应: $content');
        client.close();
        return null;
      }

      final json = jsonDecode(content) as Map<String, dynamic>;

      if (json['code'] == '00000') {
        _addLog('✅ 评价提交成功');
      } else {
        _addLog('[ERROR] 评价提交失败: ${json['message']}');
      }

      client.close();
      return json;
    } catch (e, stack) {
      _addLog('[ERROR] 提交评价异常: $e');
      _addLog('堆栈: $stack');
      return null;
    }
  }

  void dispose() {
    _ytoken = null;
    _logs.clear();
  }
}
