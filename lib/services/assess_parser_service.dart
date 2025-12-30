import 'package:html/parser.dart' as html_parser;

/// 课程评价 HTML 解析服务
class AssessParserService {
  /// 解析待评价课程列表
  static List<Map<String, String>>? parseCourseList(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);
      final rows = document.querySelectorAll('table.table_border tr');

      final List<Map<String, String>> courses = [];

      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final cells = row.querySelectorAll('td');

        if (cells.length >= 6) {
          final number = cells[0].text.trim();
          final courseId = cells[1].text.trim();
          final courseName = cells[2].text.trim();
          final classNumber = cells[3].text.trim();
          final status = cells[4].text.trim();

          // 解析操作链接
          String? assessLink;
          String assessStatus = '未知';
          String sid = '';
          String lid = '';
          int templateFlag = 0;

          final actionCell = cells[5];
          final link = actionCell.querySelector('a');

          if (link != null) {
            // 未评价，有"填写问卷"链接
            assessLink = link.attributes['href'] ?? '';
            assessStatus = '待评价';

            // 解析 URL 参数
            if (assessLink.contains('sid=') && assessLink.contains('lid=')) {
              final uri = Uri.parse('https://jwc.swjtu.edu.cn$assessLink');
              sid = uri.queryParameters['sid'] ?? '';
              lid = uri.queryParameters['lid'] ?? '';
              templateFlag =
                  int.tryParse(uri.queryParameters['templateFlag'] ?? '0') ?? 0;
            }
          } else {
            // 已评价，显示评分
            final cellText = actionCell.text.trim();
            if (cellText.contains('评分')) {
              assessStatus = '已评价';
              final match = RegExp(r'评分：\s*(\d+)').firstMatch(cellText);
              if (match != null) {
                assessStatus = '已评价(${match.group(1)}分)';
              }
            }
          }

          courses.add({
            'number': number,
            'courseId': courseId,
            'courseName': courseName,
            'classNumber': classNumber,
            'status': status,
            'assessStatus': assessStatus,
            'assessLink': assessLink ?? '',
            'sid': sid,
            'lid': lid,
            'templateFlag': templateFlag.toString(),
          });
        }
      }

      return courses;
    } catch (e) {
      print('[ERROR] 解析课程列表失败: $e');
      return null;
    }
  }

  /// 解析评价表单，提取所有题目的ID和必要信息
  static Map<String, dynamic>? parseAssessForm(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);

      // 提取 assess_id
      final assessIdInput = document.querySelector('input[name="assess_id"]');
      final assessId = assessIdInput?.attributes['value'] ?? '';

      // 提取所有选择题的 ID (input[type="radio"])
      final questionIds = <String>[];
      final inputs = document.querySelectorAll('input[type="radio"]');

      final seenQuestions = <String>{};
      for (var input in inputs) {
        final name = input.attributes['name'] ?? '';
        if (name.startsWith('question_')) {
          final id = name.replaceFirst('question_', '');
          if (!seenQuestions.contains(id)) {
            seenQuestions.add(id);
            questionIds.add(id);
          }
        }
      }

      // 提取主观题 ID (textarea)
      final textareas = document.querySelectorAll('textarea');
      final textQuestionIds = <String>[];
      for (var textarea in textareas) {
        final name = textarea.attributes['name'] ?? '';
        if (name.startsWith('text_question_')) {
          textQuestionIds.add(name.replaceFirst('text_question_', ''));
        }
      }

      // 提取隐藏的 id 字段（每个题目对应的唯一ID）
      final hiddenIds = <String>[];
      final hiddenInputs = document.querySelectorAll(
        'input[type="hidden"][name="id"]',
      );
      for (var input in hiddenInputs) {
        final value = input.attributes['value'] ?? '';
        if (value.isNotEmpty) {
          hiddenIds.add(value);
        }
      }

      return {
        'assessId': assessId,
        'questionIds': questionIds,
        'textQuestionIds': textQuestionIds,
        'hiddenIds': hiddenIds,
      };
    } catch (e) {
      print('[ERROR] 解析表单失败: $e');
      return null;
    }
  }
}
