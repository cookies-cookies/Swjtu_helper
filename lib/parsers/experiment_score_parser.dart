import 'package:html/parser.dart' as html_parser;
import '../models/experiment_score.dart';

class ExperimentScoreParser {
  /// 解析实验成绩HTML页面
  static List<ExperimentScore> parse(String htmlContent) {
    if (htmlContent.isEmpty) return [];

    try {
      final document = html_parser.parse(htmlContent);
      final scores = <ExperimentScore>[];

      // 根据实际HTML结构解析
      // 通常实验成绩会在表格或列表中
      // 这里先提供一个基础框架，等看到实际HTML结构后再调整

      // 查找所有实验项目行（可能是 tr、li 或 div）
      final rows = document.querySelectorAll(
        'tr.experiment-item, .score-item, tbody tr',
      );

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];

        try {
          // 提取各个字段（具体选择器需要根据实际HTML调整）
          final cells = row.querySelectorAll('td');
          if (cells.length < 4) continue; // 至少需要课程名、实验名、教师、成绩

          final courseName = cells[0].text.trim();
          final experimentName = cells[1].text.trim();
          final teacher = cells[2].text.trim();
          final scoreText = cells[3].text.trim();

          // 判断是否需要评价
          final needsEvaluation =
              row.querySelector('.need-evaluate, .btn-evaluate') != null;

          // 提取成绩（如果有）
          String? score;
          if (scoreText.isNotEmpty &&
              !scoreText.contains('评价') &&
              scoreText != '-') {
            score = scoreText;
          }

          // 提取日期信息
          String? submitDate;
          String? experimentDate;
          if (cells.length > 4) {
            experimentDate = cells[4].text.trim();
          }
          if (cells.length > 5) {
            submitDate = cells[5].text.trim();
          }

          scores.add(
            ExperimentScore(
              id: 'exp_$i',
              courseName: courseName,
              experimentName: experimentName,
              teacher: teacher,
              score: score,
              needsEvaluation: needsEvaluation,
              submitDate: submitDate,
              experimentDate: experimentDate,
            ),
          );
        } catch (e) {
          print('[!] 解析实验项目失败: $e');
          continue;
        }
      }

      return scores;
    } catch (e) {
      print('[!] 解析实验成绩HTML失败: $e');
      return [];
    }
  }

  /// 从JSON数据解析（如果API返回JSON格式）
  static List<ExperimentScore> parseJson(Map<String, dynamic> json) {
    try {
      final data = json['data'] as List?;
      if (data == null) return [];

      return data.map((item) {
        return ExperimentScore(
          id: item['id']?.toString() ?? '',
          courseName: item['courseName']?.toString() ?? '',
          experimentName: item['experimentName']?.toString() ?? '',
          teacher: item['teacher']?.toString() ?? '',
          score: item['score']?.toString(),
          needsEvaluation: item['needsEvaluation'] as bool? ?? false,
          evaluationStatus: item['evaluationStatus']?.toString(),
          submitDate: item['submitDate']?.toString(),
          experimentDate: item['experimentDate']?.toString(),
        );
      }).toList();
    } catch (e) {
      print('[!] 解析实验成绩JSON失败: $e');
      return [];
    }
  }
}
