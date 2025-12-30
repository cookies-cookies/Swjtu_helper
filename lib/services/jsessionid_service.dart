import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' show parse;

const String BASE = 'http://jwc.swjtu.edu.cn';
const String USERFRAMEWORK_PATH = '/vatuu/UserFramework';
const String STUDENTINFO_PATH =
    '/vatuu/StudentInfoAction?setAction=studentInfoQuery';
const String STUDENT_SCORE_PATH =
    '/vatuu/StudentScoreInfoAction?setAction=studentNormalMark';
const String ALL_SCORES_PATH =
    '/vatuu/StudentScoreInfoAction?setAction=studentScoreQuery&viewType=studentScore&orderType=submitDate&orderValue=desc';
const String COURSE_SELECTION_PATH =
    '/vatuu/CourseAction?setAction=userCourseSchedule&selectTableType=ThisTerm';
const String COURSE_STUDENT_ACTION_PATH = '/vatuu/CourseStudentAction';
const String COOKIES_FILE = 'cookies.json';

const Map<String, String> BROWSER_LIKE_HEADERS = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9',
};

class LoginResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  const LoginResult({required this.success, required this.message, this.data});
}

class JSessionIdService {
  String? _jsessionid;
  final List<String> _logs = [];
  bool _disposed = false;

  void _addLog(String line) {
    _logs.add(line);
    if (_logs.length > 5000) _logs.removeAt(0);
    print(line);
  }

  List<String> takeLogs() {
    final copy = List<String>.from(_logs);
    _logs.clear();
    return copy;
  }

  String? get jsessionid => _jsessionid;

  /// 使用 JSESSIONID 登录并验证
  Future<LoginResult> loginWithJSessionId(String jsessionid) async {
    if (_disposed) {
      return const LoginResult(success: false, message: '服务已释放');
    }

    if (jsessionid.isEmpty) {
      return const LoginResult(success: false, message: 'JSESSIONID 不能为空');
    }

    _jsessionid = jsessionid;
    _addLog('[*] 设置 JSESSIONID (长度: ${jsessionid.length})');

    // 保存到文件
    await _saveCookies();

    // 验证会话是否有效
    _addLog('[*] 正在验证会话...');
    final result = await _verifySession();

    if (result.success) {
      _addLog('[+] 会话有效！已成功连接到教务系统');
    } else {
      _addLog('[!] 会话无效或已过期');
    }

    return result;
  }

  /// 验证会话是否有效
  Future<LoginResult> _verifySession() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);

      try {
        final uri = Uri.parse('$BASE$STUDENTINFO_PATH');
        _addLog('[*] 请求 URL: $uri');
        final request = await client.getUrl(uri);

        // 设置 headers
        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Referer', '$BASE$USERFRAMEWORK_PATH');
        _addLog('[*] 已设置 Referer: $BASE$USERFRAMEWORK_PATH');

        // 设置 Cookie
        if (_jsessionid != null && _jsessionid!.isNotEmpty) {
          request.headers.set(
            HttpHeaders.cookieHeader,
            'JSESSIONID=$_jsessionid',
          );
        }

        final response = await request.close();
        final statusCode = response.statusCode;
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] StudentInfo 状态码: $statusCode');
        _addLog('[*] 响应内容长度: ${body.length}');

        // 调试：保存响应到文件
        try {
          await File('debug_studentinfo_response.html').writeAsString(body);
          _addLog('[*] 响应已保存到 debug_studentinfo_response.html');
        } catch (_) {}

        if (statusCode == 200) {
          // 检查是否包含登录提示（与 Python 版本逻辑一致）
          final hasUnauthorized =
              body.contains('您还未登陆') || body.contains('非常抱歉，您还未登陆');
          final hasBothLoginFields =
              body.contains('name="username"') &&
              body.contains('name="password"');
          final hasLoginPrompt = hasUnauthorized || hasBothLoginFields;

          _addLog('[*] 包含未登录提示: $hasUnauthorized');
          _addLog('[*] 包含登录表单: $hasBothLoginFields');
          _addLog('[*] 判定为未登录: $hasLoginPrompt');

          if (hasLoginPrompt) {
            return const LoginResult(
              success: false,
              message: 'JSESSIONID 无效或已过期，请重新获取',
            );
          }

          // 尝试提取学生信息
          final studentInfo = _extractStudentInfo(body);

          return LoginResult(success: true, message: '登录成功', data: studentInfo);
        } else {
          return LoginResult(
            success: false,
            message: '验证失败，HTTP 状态码: $statusCode',
          );
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 验证异常: $e');
      return LoginResult(success: false, message: '网络错误: ${e.toString()}');
    }
  }

  /// 提取学生信息
  Map<String, String> _extractStudentInfo(String html) {
    final info = <String, String>{};
    try {
      final doc = parse(html);

      // 尝试提取姓名
      final nameElement = doc.querySelector('input[name="xm"]');
      if (nameElement != null) {
        info['姓名'] = nameElement.attributes['value'] ?? '';
      }

      // 尝试提取学号
      final studentIdElement = doc.querySelector('input[name="xh"]');
      if (studentIdElement != null) {
        info['学号'] = studentIdElement.attributes['value'] ?? '';
      }

      _addLog('[*] 提取到学生信息: ${info.length} 项');
    } catch (e) {
      _addLog('[!] 提取学生信息失败: $e');
    }
    return info;
  }

  /// 获取用户框架页面
  Future<String?> getUserFramework() async {
    if (_disposed || _jsessionid == null) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);

      try {
        final uri = Uri.parse('$BASE$USERFRAMEWORK_PATH');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] UserFramework 状态码: ${response.statusCode}');
        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取 UserFramework 失败: $e');
      return null;
    }
  }

  /// 获取学生信息
  Future<String?> getStudentInfo() async {
    if (_disposed || _jsessionid == null) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      _addLog('[*] 开始获取学生信息...');

      try {
        final uri = Uri.parse('$BASE$STUDENTINFO_PATH');
        _addLog('[*] 请求 URL: $uri');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Referer', '$BASE$USERFRAMEWORK_PATH');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );
        _addLog('[*] Cookie: JSESSIONID=${_jsessionid!.substring(0, 8)}...');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] StudentInfo 状态码: ${response.statusCode}');
        _addLog('[*] StudentInfo 响应长度: ${body.length}');
        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取 StudentInfo 失败: $e');
      return null;
    }
  }

  /// 保存 cookies
  Future<void> _saveCookies() async {
    try {
      final cookieMap = {'JSESSIONID': _jsessionid ?? ''};
      await File(
        COOKIES_FILE,
      ).writeAsString(json.encode(cookieMap), encoding: utf8);
      _addLog('[+] 已保存 cookies 到 $COOKIES_FILE');
    } catch (e) {
      _addLog('[!] 保存 cookies 失败: $e');
    }
  }

  /// 获取平时成绩
  Future<String?> getStudentScore() async {
    if (_disposed || _jsessionid == null) {
      _addLog(
        '[!] 无法获取成绩: disposed=$_disposed, jsessionid=${_jsessionid == null ? 'null' : 'exists'}',
      );
      return null;
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      _addLog('[*] 开始获取平时成绩...');

      try {
        final uri = Uri.parse('$BASE$STUDENT_SCORE_PATH');
        _addLog('[*] 请求 URL: $uri');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set(
          'Referer',
          '$BASE/vatuu/StudentScoreInfoAction?setAction=studentMarkUseProgram',
        );
        request.headers.set('Sec-Fetch-Site', 'same-origin');
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Sec-Fetch-Dest', 'iframe');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );
        _addLog('[*] Cookie: JSESSIONID=${_jsessionid!.substring(0, 8)}...');
        _addLog(
          '[*] Referer: $BASE/vatuu/StudentScoreInfoAction?setAction=studentMarkUseProgram',
        );

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] StudentScore 状态码: ${response.statusCode}');
        _addLog('[*] StudentScore 响应长度: ${body.length}');

        // 保存调试文件
        try {
          await File('debug_student_score.html').writeAsString(body);
          _addLog('[*] 成绩响应已保存到 debug_student_score.html');
        } catch (_) {}

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取平时成绩失败: $e');
      return null;
    }
  }

  /// 获取全部成绩 HTML
  Future<String?> getAllScores() async {
    if (_disposed || _jsessionid == null) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      _addLog('[*] 开始获取全部成绩...');

      try {
        final uri = Uri.parse('$BASE$ALL_SCORES_PATH');
        _addLog('[*] 请求 URL: $uri');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Referer', '$BASE$ALL_SCORES_PATH');
        request.headers.set('Sec-Fetch-Site', 'same-origin');
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Sec-Fetch-Dest', 'iframe');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );
        _addLog('[*] Cookie: JSESSIONID=${_jsessionid!.substring(0, 8)}...');
        _addLog('[*] Referer: $BASE$ALL_SCORES_PATH');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] AllScores 状态码: ${response.statusCode}');
        _addLog('[*] AllScores 响应长度: ${body.length}');

        // 保存调试文件
        try {
          await File('debug_all_scores.html').writeAsString(body);
          _addLog('[*] 全部成绩响应已保存到 debug_all_scores.html');
        } catch (_) {}

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取全部成绩失败: $e');
      return null;
    }
  }

  /// 获取选课信息 HTML
  Future<String?> getCourseSelection() async {
    if (_disposed || _jsessionid == null) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      _addLog('[*] 开始获取选课信息...');

      try {
        final uri = Uri.parse('$BASE$COURSE_SELECTION_PATH');
        _addLog('[*] 请求 URL: $uri');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Referer', '$BASE$COURSE_SELECTION_PATH');
        request.headers.set('Sec-Fetch-Site', 'same-origin');
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Sec-Fetch-Dest', 'iframe');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );
        _addLog('[*] Cookie: JSESSIONID=${_jsessionid!.substring(0, 8)}...');
        _addLog('[*] Referer: $BASE$COURSE_SELECTION_PATH');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        _addLog('[*] CourseSelection 状态码: ${response.statusCode}');
        _addLog('[*] CourseSelection 响应长度: ${body.length}');

        // 保存调试文件
        try {
          await File('debug_course_selection.html').writeAsString(body);
          _addLog('[*] 选课响应已保存到 debug_course_selection.html');
        } catch (_) {}

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取选课信息失败: $e');
      return null;
    }
  }

  /// 课程码/名称查询（课程学生页面）
  ///
  /// 对应浏览器请求：POST /vatuu/CourseStudentAction
  /// form: setAction=studentCourseSysSchedule&...&selectAction=QueryName&key1=...&courseType=all
  ///
  /// 返回 HTML（同时保存 debug 文件：debug_course_student_query_{safeKey}.html）
  Future<String?> postCourseStudentSysScheduleQuery(
    String key1, {
    int jumpPage = 1,
    String courseType = 'all',
    String selectAction = 'QueryName',
  }) async {
    if (_disposed || _jsessionid == null) return null;

    final keyword = key1.trim();
    if (keyword.isEmpty) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 90);
      client.idleTimeout = const Duration(seconds: 90);

      try {
        final uri = Uri.parse('$BASE$COURSE_STUDENT_ACTION_PATH');
        _addLog('[*] CourseStudentAction 查询: key1=$keyword');
        _addLog('[*] 请求 URL: $uri');

        final request = await client.postUrl(uri);

        // 基础 headers
        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Origin', BASE);
        request.headers.set(
          'Referer',
          '$BASE$COURSE_STUDENT_ACTION_PATH?setAction=studentCourseSysSchedule',
        );
        request.headers.set('Cache-Control', 'max-age=0');
        request.headers.set('Upgrade-Insecure-Requests', '1');
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        // 表单 body（按你提供的字段）
        final form = <String, String>{
          'setAction': 'studentCourseSysSchedule',
          'viewType': '',
          'jumpPage': jumpPage.toString(),
          'selectAction': selectAction,
          'key1': keyword,
          'courseType': courseType,
          'key4': '',
          'btn': '执行查询',
        };
        final body = form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&');

        final bytes = utf8.encode(body);
        // 不手写 Content-Length，避免中文导致字节数不一致。
        request.add(bytes);

        final response = await request.close();

        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final html = buffer.toString();

        _addLog('[*] CourseStudentAction 状态码: ${response.statusCode}');
        _addLog('[*] CourseStudentAction 响应长度: ${html.length}');

        try {
          final safeKey = keyword.replaceAll(
            RegExp(r'[^A-Za-z0-9\u4e00-\u9fa5]'),
            '_',
          );
          final file = File('debug_course_student_query_${safeKey}.html');
          await file.writeAsString(html);
          _addLog('[*] 查询响应已保存到 ${file.path}');
        } catch (e) {
          _addLog('[!] 保存查询响应失败: $e');
        }

        return html;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] CourseStudentAction 查询失败: $e');
      return null;
    }
  }

  /// 根据页面里的 href 访问（用于自动抢课尝试“点击”选课链接）
  ///
  /// - 支持相对路径（/vatuu/... 或 vatuu/...）
  /// - 支持绝对 URL（http/https）
  ///
  /// 返回 HTML，并保存 debug 文件：debug_course_grab_action_{ts}.html
  Future<String?> getByRelativeUrl(String href) async {
    if (_disposed || _jsessionid == null) return null;

    final raw = href.trim();
    if (raw.isEmpty) return null;

    Uri uri;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      uri = Uri.parse(raw);
    } else if (raw.startsWith('/')) {
      uri = Uri.parse('$BASE$raw');
    } else {
      uri = Uri.parse('$BASE/$raw');
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 90);
      client.idleTimeout = const Duration(seconds: 90);

      try {
        _addLog('[*] GET action: $uri');
        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set('Referer', '$BASE$USERFRAMEWORK_PATH');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();
        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final body = buffer.toString();

        _addLog('[*] action 状态码: ${response.statusCode}');
        _addLog('[*] action 响应长度: ${body.length}');

        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          await File('debug_course_grab_action_${ts}.html').writeAsString(body);
        } catch (_) {}

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] action GET 失败: $e');
      return null;
    }
  }

  /// 提交选课申请（页面 JS: addStudentCourseApply&teachId=...&isBook=...&tt=...）
  ///
  /// [teachId] 对应页面隐藏字段 teachIdChooseXXXX 的值（通常是 16 位十六进制）
  Future<String?> addStudentCourseApply({
    required String teachId,
    String isBook = '1',
    String? referer,
  }) async {
    if (_disposed || _jsessionid == null) return null;

    final id = teachId.trim();
    if (id.isEmpty) return null;

    final tt = DateTime.now().millisecondsSinceEpoch;
    final url =
        '$BASE$COURSE_STUDENT_ACTION_PATH?setAction=addStudentCourseApply&teachId=${Uri.encodeQueryComponent(id)}&isBook=${Uri.encodeQueryComponent(isBook)}&tt=$tt';
    final uri = Uri.parse(url);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 90);
      client.idleTimeout = const Duration(seconds: 90);

      try {
        _addLog('[*] 提交选课申请: teachId=$id isBook=$isBook');
        _addLog('[*] 请求 URL: $uri');

        final request = await client.getUrl(uri);
        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));

        // 该接口通常由 Ajax 发起（Accept: */*）
        request.headers.set('Accept', '*/*');
        request.headers.set(
          'Referer',
          referer ??
              '$BASE$COURSE_STUDENT_ACTION_PATH?setAction=studentCourseSysRecommend',
        );
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();
        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final body = buffer.toString();

        _addLog('[*] addStudentCourseApply 状态码: ${response.statusCode}');
        _addLog('[*] addStudentCourseApply 响应长度: ${body.length}');

        try {
          await File(
            'debug_add_student_course_apply_${tt}.html',
          ).writeAsString(body);
        } catch (_) {}

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 提交选课申请失败: $e');
      return null;
    }
  }

  /// 根据班级关键字构建查询并获取课程列表页面（保存到 debug_query_course_{safeKey}.html）
  Future<String?> fetchCourseQueryForClass(
    String classKey, {
    bool isNextSemester = false,
  }) async {
    if (_disposed || _jsessionid == null) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.idleTimeout = const Duration(seconds: 30);
      _addLog('[*] 开始按班级查询课程信息: key1=$classKey');

      try {
        final encoded = Uri.encodeComponent(classKey);
        // 先尝试查询下学期看是否已发布
        final tableType = isNextSemester ? 'NextTerm' : 'ThisTerm';
        final path =
            '/vatuu/CourseAction?setAction=queryCourseList&viewType=&jumpPage=1&selectTableType=$tableType&selectAction=QueryTeachType&key1=$encoded&courseType=all&key4=&btn_query=%E6%89%A7%E8%A1%8C%E6%9F%A5%E8%AF%A2&orderType=teachId&orderValue=asc';
        final uri = Uri.parse('$BASE$path');
        _addLog('[*] 请求 URL: $uri');

        final request = await client.getUrl(uri);
        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set(
          'Referer',
          '$BASE/vatuu/CourseAction?setAction=userCourseSchedule&selectTableType=ThisTerm',
        );
        request.headers.set('Sec-Fetch-Site', 'same-origin');
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Sec-Fetch-Dest', 'iframe');
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();

        // 使用 StringBuffer 逐块读取，确保完整性
        final buffer = StringBuffer();
        await for (var chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final body = buffer.toString();

        _addLog('[*] CourseQuery 状态码: ${response.statusCode}');
        _addLog('[*] CourseQuery 响应长度: ${body.length}');

        // 验证响应是否完整（检查是否包含 HTML 结束标签）
        if (!body.contains('</html>') && !body.contains('</HTML>')) {
          _addLog('[!] 警告：响应可能不完整（未找到 </html> 标签）');
        }

        // 保存调试文件（文件名使用简单安全key）
        try {
          final safeKey = classKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
          final file = File('debug_query_course_${safeKey}.html');
          await file.writeAsString(body);
          _addLog('[*] 查询响应已保存到 ${file.path}');
        } catch (e) {
          _addLog('[!] 保存查询响应失败: $e');
        }

        return body;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 按班级查询失败: $e');
      return null;
    }
  }

  /// 从已获取的查询页面 HTML 中解析班级课表链接（queryType='class'），
  /// 构造 printCourseTable 请求并保存响应到 debug_class_schedule_{safeKey}.html
  /// [isNextSemester] 为 true 时查询下学期（学期ID+2，学期名改为"第2学期"）
  /// 返回 Map，包含 'html' 和 'url' 键
  Future<Map<String, String>?> fetchPrintCourseTableFromQueryHtml(
    String queryHtml,
    String targetClassName, {
    bool isNextSemester = false,
  }) async {
    if (_disposed || _jsessionid == null) return null;

    try {
      // 查找所有 viewClassSchedule(...) 匹配
      final reg = RegExp(
        r"viewClassSchedule\('([^']*)','([^']*)','([^']*)','([^']*)','([^']*)','([^']*)'\)",
      );
      final matches = reg.allMatches(queryHtml);

      if (matches.isEmpty) {
        _addLog('[!] 未找到 viewClassSchedule 链接');
        return null;
      }

      // 查找匹配目标班级名称且 queryType='class' 的链接
      RegExpMatch? targetMatch;
      for (var m in matches) {
        final className = m.group(1) ?? '';
        final queryType = m.group(6) ?? '';

        if (queryType == 'class' && className == targetClassName) {
          targetMatch = m;
          _addLog('[*] 找到目标班级课表链接: $className');
          break;
        }
      }

      if (targetMatch == null) {
        _addLog('[!] 未找到班级 $targetClassName 的课表链接（queryType=class）');
        return null;
      }

      final className = targetMatch.group(1) ?? '';
      // 第二组是索引（指定使用keys中的哪个），第三组是多个 key（逗号分隔）
      final indexStr = targetMatch.group(2) ?? '0';
      final keysStr = targetMatch.group(3) ?? '';
      var termId = targetMatch.group(4) ?? '';
      var termName = targetMatch.group(5) ?? '';

      // 根据索引从keys数组中取对应的key
      final keysList = keysStr.split(',').map((s) => s.trim()).toList();
      final index = int.tryParse(indexStr) ?? 0;
      if (index >= keysList.length || keysList.isEmpty) {
        _addLog('[!] 索引 $index 超出范围或keys为空（keys: $keysStr）');
        return null;
      }
      final selectedKey = keysList[index];

      _addLog('[*] 从keys "$keysStr" 中使用索引 $index 选择: $selectedKey');

      // 如果需要查询下学期,只修改学期ID(不修改名称,因为termName已经是正确的)
      if (isNextSemester) {
        final currentTermId = int.tryParse(termId) ?? 0;
        termId = (currentTermId + 2).toString();
        // 不修改termName,保持从HTML中提取的原始值
        _addLog('[*] 修改到下学期：termId=$termId, termName=$termName');
      }

      final encodedName = Uri.encodeComponent(className);
      final encodedTerm = Uri.encodeComponent(termName);

      // 添加时间戳参数防止缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '/vatuu/CourseAction?setAction=printCourseTable&viewType=view&queryType=class&key=$selectedKey&key_name=$encodedName&input_term_id=$termId&input_term_name=$encodedTerm&_t=$timestamp';
      final uri = Uri.parse('$BASE$path');
      final fullUrl = uri.toString();
      _addLog('[*] 构造班级课表 URL: $fullUrl');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.idleTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(uri);
        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        // 完全模拟浏览器直接访问（不设置 Referer）
        request.headers.set('Sec-Fetch-Site', 'none'); // 浏览器直接访问
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Sec-Fetch-Dest', 'document');
        request.headers.set('Upgrade-Insecure-Requests', '1');
        request.headers.set('Cache-Control', 'max-age=0'); // 和浏览器一致
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();

        // 使用 StringBuffer 逐块读取，确保完整性
        final buffer = StringBuffer();
        await for (var chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final body = buffer.toString();

        _addLog('[*] printCourseTable 状态码: ${response.statusCode}');
        _addLog('[*] printCourseTable 响应长度: ${body.length}');

        // 验证响应是否完整
        if (!body.contains('</html>') && !body.contains('</HTML>')) {
          _addLog('[!] 警告：响应可能不完整（未找到 </html> 标签）');
        }
        if (!body.contains('table')) {
          _addLog('[!] 警告：响应中未找到表格元素');
        }

        try {
          // 使用选中的 key 作为文件名
          final safeKey = selectedKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
          final suffix = isNextSemester ? '_next' : '';
          final file = File('debug_class_schedule_$safeKey$suffix.html');
          await file.writeAsString(body);
          _addLog('[*] 班级课表已保存到 ${file.path}');
        } catch (e) {
          _addLog('[!] 保存课表失败: $e');
        }

        return {'html': body, 'url': fullUrl};
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] 获取课表失败: $e');
      return null;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    if (_disposed) return;

    try {
      _jsessionid = null;
      final f = File(COOKIES_FILE);
      if (await f.exists()) {
        await f.delete();
      }
      _addLog('[*] 已退出登录');
    } catch (e) {
      _addLog('[!] 退出登录失败: $e');
    }
  }

  /// 查询下学期课程（CourseAction）
  ///
  /// 对应请求：GET /vatuu/CourseAction?setAction=queryCourseList&viewType=&jumpPage=1
  /// &selectTableType=NextTerm&selectAction=QueryName&key1=...&courseType=all
  /// &key4=&btn_query=执行查询&orderType=teachId&orderValue=asc
  Future<String?> getCourseActionQueryNextTerm(
    String keyword, {
    int jumpPage = 1,
    String selectAction = 'QueryName',
    String courseType = 'all',
  }) async {
    if (_disposed || _jsessionid == null) return null;

    final key1 = keyword.trim();
    if (key1.isEmpty) return null;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 90);
      client.idleTimeout = const Duration(seconds: 90);

      try {
        final queryParams = {
          'setAction': 'queryCourseList',
          'viewType': '',
          'jumpPage': jumpPage.toString(),
          'selectTableType': 'NextTerm',
          'selectAction': selectAction,
          'key1': key1,
          'courseType': courseType,
          'key4': '',
          'btn_query': '执行查询',
          'orderType': 'teachId',
          'orderValue': 'asc',
        };
        final queryString = queryParams.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
        final uri = Uri.parse('$BASE/vatuu/CourseAction?$queryString');

        _addLog('[*] CourseAction 查询下学期: key1=$key1');
        _addLog('[*] 请求 URL: $uri');

        final request = await client.getUrl(uri);

        BROWSER_LIKE_HEADERS.forEach((k, v) => request.headers.set(k, v));
        request.headers.set(
          'Referer',
          '$BASE/vatuu/CourseAction?setAction=queryCourseList&selectTableType=NextTerm',
        );
        request.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_jsessionid',
        );

        final response = await request.close();
        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
        }
        final html = buffer.toString();

        _addLog('[*] CourseAction 状态码: ${response.statusCode}');
        _addLog('[*] CourseAction 响应长度: ${html.length}');

        try {
          final safeKey = key1.replaceAll(
            RegExp(r'[^A-Za-z0-9\u4e00-\u9fa5]'),
            '_',
          );
          final file = File('debug_course_action_query_nextterm_$safeKey.html');
          await file.writeAsString(html);
          _addLog('[*] 查询响应已保存到 ${file.path}');
        } catch (e) {
          _addLog('[!] 保存查询响应失败: $e');
        }

        return html;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _addLog('[!] CourseAction 查询失败: $e');
      return null;
    }
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    if (_disposed || _jsessionid == null) return false;

    final result = await _verifySession();
    return result.success;
  }

  void dispose() {
    _disposed = true;
    _logs.clear();
  }
}
