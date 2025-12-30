import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// 课程评价服务
class CourseAssessService {
  static const String BASE_URL = 'https://jwc.swjtu.edu.cn/vatuu';

  String? _jsessionid;
  final Map<String, String> _allCookies = {}; // 保存所有Cookie
  final List<String> _logs = [];

  void setJSessionId(String jsessionid) {
    _jsessionid = jsessionid;
    _allCookies['JSESSIONID'] = jsessionid;
    _addLog('JSESSIONID 已设置');
  }

  /// 设置额外的Cookie（如百度统计Cookie）
  void setExtraCookies(Map<String, String> cookies) {
    _allCookies.addAll(cookies);
  }

  /// 获取完整Cookie字符串
  String get _cookieHeader {
    if (_allCookies.isEmpty && _jsessionid != null) {
      return 'JSESSIONID=$_jsessionid';
    }
    return _allCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _addLog(String log) {
    _logs.add('[课程评价] $log');
    if (kDebugMode) print('[课程评价] $log');
  }

  List<String> takeLogs() {
    final result = List<String>.from(_logs);
    _logs.clear();
    return result;
  }

  /// 获取待评价课程列表
  Future<String?> getAssessmentList() async {
    if (_jsessionid == null) {
      _addLog('[ERROR] JSESSIONID 未设置');
      return null;
    }

    try {
      final url = '$BASE_URL/AssessAction?setAction=list';
      _addLog('请求待评价课程列表');

      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));

      // 设置请求头
      request.headers.set('Host', 'jwc.swjtu.edu.cn');
      request.headers.set('Cookie', _cookieHeader);
      request.headers.set(
        'Sec-Ch-Ua',
        '"Chromium";v="139", "Not;A=Brand";v="99"',
      );
      request.headers.set('Sec-Ch-Ua-Mobile', '?0');
      request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
      request.headers.set('Upgrade-Insecure-Requests', '1');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      request.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      );
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Sec-Fetch-Mode', 'navigate');
      request.headers.set('Sec-Fetch-User', '?1');
      request.headers.set('Sec-Fetch-Dest', 'iframe');
      request.headers.set(
        'Referer',
        'https://jwc.swjtu.edu.cn/vatuu/StudentScoreInfoAction?setAction=studentMarkUseProgram',
      );
      request.headers.set('Accept-Encoding', 'gzip, deflate, br');
      request.headers.set('Priority', 'u=0, i');

      final response = await request.close();
      final statusCode = response.statusCode;

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final content = await response.transform(utf8.decoder).join();
      _addLog('成功获取列表页面: ${content.length} 字节');

      // 保存 HTML 文件
      try {
        final file = File('debug_assess_list.html');
        await file.writeAsString(content);
        _addLog('已保存到: ${file.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      client.close();
      return content;
    } catch (e) {
      _addLog('[ERROR] 获取列表失败: $e');
      return null;
    }
  }

  /// 获取评价表单页面
  Future<String?> getAssessmentForm({
    required String sid,
    required String lid,
    int templateFlag = 0,
  }) async {
    if (_jsessionid == null) {
      _addLog('[ERROR] JSESSIONID 未设置');
      return null;
    }

    try {
      final url =
          '$BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag';
      _addLog('请求评价表单: sid=$sid, lid=$lid');

      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));

      // 设置请求头
      request.headers.set('Host', 'jwc.swjtu.edu.cn');
      request.headers.set('Cookie', _cookieHeader);
      request.headers.set(
        'Sec-Ch-Ua',
        '"Chromium";v="139", "Not;A=Brand";v="99"',
      );
      request.headers.set('Sec-Ch-Ua-Mobile', '?0');
      request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
      request.headers.set('Upgrade-Insecure-Requests', '1');
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      request.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      );
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Sec-Fetch-Mode', 'navigate');
      request.headers.set('Sec-Fetch-User', '?1');
      request.headers.set('Sec-Fetch-Dest', 'iframe');
      request.headers.set('Referer', '$BASE_URL/AssessAction?setAction=list');
      request.headers.set('Accept-Encoding', 'gzip, deflate, br');
      request.headers.set('Priority', 'u=0, i');

      final response = await request.close();
      final statusCode = response.statusCode;

      if (statusCode != 200) {
        _addLog('[ERROR] 请求失败: HTTP $statusCode');
        await response.drain();
        client.close();
        return null;
      }

      final content = await response.transform(utf8.decoder).join();
      _addLog('成功获取表单页面: ${content.length} 字节');

      // 保存 HTML 文件
      try {
        final file = File('debug_assess_form_${sid}.html');
        await file.writeAsString(content);
        _addLog('已保存到: ${file.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      client.close();
      return content;
    } catch (e) {
      _addLog('[ERROR] 获取表单失败: $e');
      return null;
    }
  }

  /// 提交评价
  Future<bool> submitAssessment({
    required String answer,
    required String scores,
    required String percents,
    required String assessId,
    required int templateFlag,
    required String id,
    required String sid,
    required String lid,
  }) async {
    if (_jsessionid == null) {
      _addLog('[ERROR] JSESSIONID 未设置');
      return false;
    }

    try {
      final url = '$BASE_URL/AssessAction';
      _addLog('提交评价: assessId=$assessId');

      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client.postUrl(Uri.parse(url));

      // 设置请求头
      request.headers.set('Host', 'jwc.swjtu.edu.cn');
      request.headers.set('Cookie', _cookieHeader); // 使用完整Cookie
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.headers.set(
        'Sec-Ch-Ua',
        '"Chromium";v="142", "Microsoft Edge";v="142", "Not_A Brand";v="99"',
      );
      request.headers.set('Sec-Ch-Ua-Mobile', '?0');
      request.headers.set('Sec-Ch-Ua-Platform', '"Windows"');
      request.headers.set(
        'Accept-Language',
        'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
      );
      request.headers.set('Cache-Control', 'max-age=0');
      request.headers.set('Origin', 'https://jwc.swjtu.edu.cn');
      request.headers.set(
        'Referer',
        '$BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag',
      );
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0',
      );
      request.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      );
      request.headers.set('Sec-Fetch-Dest', 'iframe');
      request.headers.set('Sec-Fetch-Mode', 'navigate');
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Sec-Fetch-User', '?1');
      request.headers.set('Upgrade-Insecure-Requests', '1');

      // 构建表单数据 - 严格按照form2的字段顺序和内容
      // 生成和JavaScript Math.random()一样格式的随机数：0.xxxxx（0到1之间）
      final t = Random().nextDouble();

      final bodyParts = <String>[
        'answer=$answer',
        'scores=$scores',
        'percents=$percents',
        'assess_id=$assessId',
        'templateFlag=$templateFlag',
        't=$t',
        'keyword=null',
        'id=$id',
        'teacherId=', // 空值但必须有
        'logId=$lid',
        'setAction=answerStudent',
      ];

      final body = bodyParts.join('&');

      _addLog('---------- 完整请求体 ----------');
      _addLog('Body长度: ${utf8.encode(body).length} 字节');
      _addLog('Body内容:');
      _addLog(body);
      _addLog('---------- 请求头信息 ----------');
      _addLog('Content-Type: ${request.headers.value('Content-Type')}');
      _addLog('Content-Length: ${utf8.encode(body).length}');
      _addLog('Cookie: $_cookieHeader');
      _addLog('完整Cookie内容: ${_allCookies.toString()}');
      _addLog(
        'Referer: $BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag',
      );
      _addLog('-----------------------------------');

      request.headers.set(
        'Content-Length',
        utf8.encode(body).length.toString(),
      );
      request.write(body);

      final response = await request.close();
      final statusCode = response.statusCode;

      final content = await response.transform(utf8.decoder).join();

      if (statusCode == 200) {
        _addLog('提交成功: HTTP $statusCode');
        _addLog(
          '响应: ${content.substring(0, content.length > 200 ? 200 : content.length)}',
        );

        // 保存响应
        try {
          final file = File('debug_assess_submit_response.html');
          await file.writeAsString(content);
          _addLog('已保存响应到: ${file.path}');
        } catch (e) {
          _addLog('[WARN] 保存文件失败: $e');
        }

        client.close();
        return true;
      } else {
        _addLog('[ERROR] 提交失败: HTTP $statusCode');
        client.close();
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] 提交失败: $e');
      return false;
    }
  }

  /// 自动评价单门课程（先获取表单，再提交）- 使用同一会话
  Future<bool> autoAssessCourse({
    required String sid,
    required String lid,
    int templateFlag = 0,
    String textAnswer1 = '老师的讲解',
    String textAnswer2 = '无，都挺好的',
    bool testMode = false,
  }) async {
    _addLog('========== 开始自动评价 ==========');
    _addLog('参数: sid=$sid, lid=$lid, templateFlag=$templateFlag');
    _addLog('测试模式: ${testMode ? "是（不实际提交）" : "否（将实际提交）"}');

    // 创建一个持久的 HttpClient 用于整个评价流程
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      // 1. 获取评价表单页面（使用同一个client）
      final formUrl =
          '$BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag';
      _addLog('请求评价表单: sid=$sid, lid=$lid');

      final formRequest = await client.getUrl(Uri.parse(formUrl));
      formRequest.headers.set('Host', 'jwc.swjtu.edu.cn');
      formRequest.headers.set('Cookie', _cookieHeader);
      formRequest.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      formRequest.headers.set(
        'Referer',
        '$BASE_URL/AssessAction?setAction=list',
      );

      final formResponse = await formRequest.close();
      if (formResponse.statusCode != 200) {
        _addLog('[ERROR] 获取表单失败: HTTP ${formResponse.statusCode}');
        client.close();
        return false;
      }

      final formHtml = await formResponse.transform(utf8.decoder).join();
      _addLog('成功获取表单页面: ${formHtml.length} 字节');

      // 保存表单HTML
      try {
        final file = File('debug_assess_form_$sid.html');
        await file.writeAsString(formHtml);
        _addLog('已保存到: ${file.path}');
      } catch (e) {
        _addLog('[WARN] 保存文件失败: $e');
      }

      // 2. 解析表单，提取必要信息
      _addLog('---------- 解析表单数据 ----------');

      // 提取 assess_id
      final assessIdMatch = RegExp(
        r'name="assess_id"[^>]*value="(\d+)"',
      ).firstMatch(formHtml);
      if (assessIdMatch == null) {
        _addLog('[ERROR] 未找到 assess_id');
        return false;
      }
      final assessId = assessIdMatch.group(1)!;
      _addLog('✓ assess_id: $assessId');

      // 提取所有题目的 problem_id 和对应的最高分选项
      final List<Map<String, String>> questions = [];

      // 匹配所有题目的 problem_id
      final problemIdMatches = RegExp(
        r'<input[^>]*name="problem_id"[^>]*value="([^"]+)"[^>]*perc="([^"]+)"',
      ).allMatches(formHtml);

      for (var match in problemIdMatches) {
        final problemId = match.group(1)!;
        final perc = match.group(2)!;

        // 找到这个题目的最高分选项（score="5.0"）
        // 使用动态构建的正则表达式
        final optionPattern =
            'name="problem$problemId"[^>]*value="([^"]+)"[^>]*score="5\\.0"';
        final optionMatch = RegExp(optionPattern).firstMatch(formHtml);

        if (optionMatch != null) {
          // 单选题：有选项
          questions.add({
            'problemId': problemId,
            'optionId': optionMatch.group(1)!,
            'perc': perc,
            'type': 'radio',
          });
        } else {
          // 检查是否是主观题（textarea）
          final textareaPattern = 'name="problem$problemId"[^>]*>';
          if (RegExp(textareaPattern).hasMatch(formHtml)) {
            // 主观题：没有选项
            questions.add({
              'problemId': problemId,
              'optionId': '', // 主观题没有选项ID
              'perc': perc,
              'type': 'textarea',
            });
          } else {
            _addLog('[WARN] 题目 $problemId 未找到5分选项');
          }
        }
      }

      if (questions.isEmpty) {
        _addLog('[ERROR] 未找到题目');
        return false;
      }

      _addLog('✓ 解析到 ${questions.length} 个题目:');
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        final typeStr = q['type'] == 'radio' ? '单选' : '主观';
        _addLog(
          '  题目${i + 1}: [$typeStr] problemId=${q['problemId']}, optionId=${q['optionId']}, perc=${q['perc']}%',
        );
      }

      // 3. 构建提交数据
      _addLog('---------- 构建提交数据 ----------');

      final answerParts = <String>[''];
      final scoreParts = <String>[''];
      final percentParts = <String>[''];
      final idParts = <String>[''];

      // 处理所有题目
      for (var q in questions) {
        // answer 字段：只添加单选题的选项ID，主观题不添加
        if (q['type'] == 'radio') {
          answerParts.add(q['optionId']!);
        }

        // id 字段：所有题目的问题ID都要添加
        idParts.add(q['problemId']!);

        // scores 字段：单选题是5.0，主观题是空
        if (q['type'] == 'radio') {
          scoreParts.add('5.0');
        } else {
          scoreParts.add('');
        }

        // percents 字段：所有题目都添加其权重
        percentParts.add(q['perc']!);
      }

      // 添加主观题答案
      answerParts.add(Uri.encodeComponent(textAnswer1));
      answerParts.add(Uri.encodeComponent(textAnswer2));

      _addLog('主观题答案1: $textAnswer1 → ${Uri.encodeComponent(textAnswer1)}');
      _addLog('主观题答案2: $textAnswer2 → ${Uri.encodeComponent(textAnswer2)}');

      final answer = answerParts.join('_');
      final scores = scoreParts.join('_');
      final percents = percentParts.join('_');
      final id = idParts.join('_');

      _addLog('---------- 最终提交数据 ----------');
      _addLog('answer元素数: ${answer.split('_').length}');
      _addLog('answer长度: ${answer.length} 字符');
      _addLog('answer内容: $answer');
      _addLog('');
      _addLog('scores元素数: ${scores.split('_').length}');
      _addLog('scores长度: ${scores.length} 字符');
      _addLog('scores内容: $scores');
      _addLog('');
      _addLog('percents元素数: ${percents.split('_').length}');
      _addLog('percents长度: ${percents.length} 字符');
      _addLog('percents内容: $percents');
      _addLog('');
      _addLog('id元素数: ${id.split('_').length}');
      _addLog('id长度: ${id.length} 字符');
      _addLog('id内容: $id');
      _addLog('');
      _addLog('assess_id: $assessId');
      _addLog('templateFlag: $templateFlag');
      _addLog('logId: $lid');
      _addLog('========================================');

      if (testMode) {
        _addLog('');
        _addLog('🔴 测试模式：数据已准备完成，但不会实际提交');
        _addLog('如需实际提交，请在代码中设置 testMode = false');
        client.close();
        return true; // 测试模式返回成功
      }

      _addLog('准备实际提交评价...');

      // 等待60秒,模拟人工填写时间（服务器可能要求至少1分钟）
      _addLog('⏱️  等待60秒（模拟填写时间）...');
      await Future.delayed(const Duration(seconds: 65));

      _addLog('✓ 等待完成，开始提交');

      // 4. 提交评价（使用同一个 client，保持会话）
      _addLog('提交评价: assessId=$assessId');

      final t = Random().nextDouble();
      final body =
          'answer=$answer&'
          'scores=$scores&'
          'percents=$percents&'
          'id=$id&'
          'assess_id=$assessId&'
          'templateFlag=$templateFlag&'
          't=$t&'
          'keyword=null&'
          'teacherId=&'
          'logId=$lid&'
          'setAction=answerStudent';

      _addLog('---------- 完整请求体 ----------');
      _addLog('Body长度: ${utf8.encode(body).length} 字节');
      _addLog('Body内容:');
      _addLog(body);
      _addLog('---------- 请求头信息 ----------');
      _addLog('Content-Type: application/x-www-form-urlencoded');
      _addLog('Content-Length: ${utf8.encode(body).length}');
      _addLog('Cookie: $_cookieHeader');
      _addLog(
        'Referer: $BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag',
      );
      _addLog('-----------------------------------');

      final submitUrl = '$BASE_URL/AssessAction';
      final submitRequest = await client.postUrl(Uri.parse(submitUrl));

      // 设置完整的请求头,匹配浏览器
      submitRequest.headers.set('Host', 'jwc.swjtu.edu.cn');
      submitRequest.headers.set('Cookie', _cookieHeader);
      submitRequest.headers.set(
        'Content-Length',
        utf8.encode(body).length.toString(),
      );
      submitRequest.headers.set('Cache-Control', 'max-age=0');
      submitRequest.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
      submitRequest.headers.set('Origin', 'https://jwc.swjtu.edu.cn');
      submitRequest.headers.set(
        'Content-Type',
        'application/x-www-form-urlencoded',
      );
      submitRequest.headers.set('Upgrade-Insecure-Requests', '1');
      submitRequest.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
      );
      submitRequest.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      );
      submitRequest.headers.set('Sec-Fetch-Site', 'same-origin');
      submitRequest.headers.set('Sec-Fetch-Mode', 'navigate');
      submitRequest.headers.set('Sec-Fetch-User', '?1');
      submitRequest.headers.set('Sec-Fetch-Dest', 'iframe');
      submitRequest.headers.set(
        'Referer',
        '$BASE_URL/AssessAction?setAction=viewAssess&sid=$sid&lid=$lid&templateFlag=$templateFlag',
      );
      submitRequest.headers.set('Accept-Encoding', 'gzip, deflate, br');
      submitRequest.headers.set('Priority', 'u=0, i');
      submitRequest.write(body);

      final submitResponse = await submitRequest.close();
      final submitContent = await submitResponse.transform(utf8.decoder).join();

      if (submitResponse.statusCode == 200) {
        _addLog('提交成功: HTTP ${submitResponse.statusCode}');
        _addLog(
          '响应: ${submitContent.substring(0, submitContent.length > 200 ? 200 : submitContent.length)}',
        );

        // 保存响应
        try {
          final file = File('debug_assess_submit_response.html');
          await file.writeAsString(submitContent);
          _addLog('已保存响应到: ${file.path}');
        } catch (e) {
          _addLog('[WARN] 保存文件失败: $e');
        }

        client.close();
        return true;
      } else {
        _addLog('[ERROR] 提交失败: HTTP ${submitResponse.statusCode}');
        client.close();
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] 自动评价失败: $e');
      client.close();
      return false;
    }
  }

  void dispose() {
    _jsessionid = null;
    _logs.clear();
  }
}
