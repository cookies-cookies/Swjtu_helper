/// 全部成绩数据模型

class AllScores {
  final List<CourseScore> scores;

  AllScores({required this.scores});

  // 获取总学分
  double get totalCredits {
    return scores.fold(0.0, (sum, score) => sum + score.credit);
  }

  // 按学期分组
  Map<String, List<CourseScore>> groupByTerm() {
    final Map<String, List<CourseScore>> grouped = {};
    for (final score in scores) {
      final key = '${score.academicYear}-${score.semester}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(score);
    }
    return grouped;
  }

  // 计算平均分
  double get averageScore {
    if (scores.isEmpty) return 0.0;
    final validScores = scores
        .where((s) => s.numericScore != null)
        .map((s) => s.numericScore!)
        .toList();
    if (validScores.isEmpty) return 0.0;
    return validScores.reduce((a, b) => a + b) / validScores.length;
  }
}

class CourseScore {
  final String courseCode; // 课程代码
  final String courseName; // 课程名称
  final String classNumber; // 班号
  final String nature; // 性质（必修/选修）
  final String score; // 成绩（可能是数字或等级）
  final String finalScore; // 期末成绩
  final String normalScore; // 平时成绩
  final String examType; // 考试类型（正考/重修/补考）
  final double credit; // 学分
  final String teacher; // 教师
  final String gradeSystem; // 分制
  final String academicYear; // 学年
  final String semester; // 学期
  final String remark; // 备注

  CourseScore({
    required this.courseCode,
    required this.courseName,
    required this.classNumber,
    required this.nature,
    required this.score,
    required this.finalScore,
    required this.normalScore,
    required this.examType,
    required this.credit,
    required this.teacher,
    required this.gradeSystem,
    required this.academicYear,
    required this.semester,
    required this.remark,
  });

  // 获取数字成绩（如果是数字格式）
  double? get numericScore {
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(score);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  // 判断是否及格
  bool get isPassed {
    final numeric = numericScore;
    if (numeric != null) {
      return numeric >= 60;
    }
    // 对于非数字成绩，判断是否包含"优秀"、"良好"、"通过"等关键词
    return score.contains('优秀') ||
        score.contains('良好') ||
        score.contains('中等') ||
        score.contains('及格') ||
        score.contains('通过') ||
        score.contains('合格');
  }

  // 判断是否为必修课
  bool get isRequired => nature.contains('必');

  // 判断是否为选修课
  bool get isElective => nature.contains('选');
}
