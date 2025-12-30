import 'package:flutter/material.dart';
import '../models/student_score.dart';

/// 平时成绩展示页面
class StudentScorePage extends StatelessWidget {
  final StudentScore studentScore;

  const StudentScorePage({super.key, required this.studentScore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('平时成绩'), centerTitle: true),
      body: studentScore.courses.isEmpty
          ? const Center(child: Text('暂无成绩数据', style: TextStyle(fontSize: 16)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: studentScore.courses.length,
              itemBuilder: (context, index) {
                final course = studentScore.courses[index];
                return _buildCourseCard(context, course, index + 1);
              },
            ),
    );
  }

  /// 构建课程卡片
  Widget _buildCourseCard(
    BuildContext context,
    CourseSummary course,
    int courseIndex,
  ) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 课程标题头部
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getCourseColor(courseIndex),
                  _getCourseColor(courseIndex).withOpacity(0.7),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildTag(
                      '总成绩',
                      '${course.totalScore.toStringAsFixed(1)}分',
                    ),
                    const SizedBox(width: 8),
                    _buildTag(
                      '占比',
                      '${course.totalProportion.toStringAsFixed(1)}%',
                    ),
                    const SizedBox(width: 8),
                    _buildTag(
                      '折算',
                      '${course.convertedScore.toStringAsFixed(1)}分',
                      isHighlight: true,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 成绩项目列表
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: course.items
                  .map((item) => _buildScoreItem(context, item))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建标签
  Widget _buildTag(String label, String value, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlight ? Colors.yellow[700] : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isHighlight ? Colors.white : Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.white : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建成绩项目
  Widget _buildScoreItem(BuildContext context, ScoreItem item) {
    final score = double.tryParse(item.score) ?? 0;
    final scoreColor = _getScoreColor(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.scoreType,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '教师: ${item.teacher} | 班号: ${item.classNumber}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scoreColor, width: 1.5),
                    ),
                    child: Text(
                      item.score,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '占比 ${item.proportion}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
          if (item.remark.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.remark,
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '课程代码: ${item.courseCode}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                '提交时间: ${item.submitTime}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 根据课程索引获取颜色
  Color _getCourseColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }

  /// 根据分数获取颜色
  Color _getScoreColor(double score) {
    if (score >= 90) return Colors.green[700]!;
    if (score >= 80) return Colors.blue[700]!;
    if (score >= 70) return Colors.orange[700]!;
    if (score >= 60) return Colors.amber[800]!;
    return Colors.red[700]!;
  }
}
