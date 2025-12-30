/// 平时成绩项目
class ScoreItem {
  final String index; // 序号
  final String term; // 学期
  final String courseCode; // 代码
  final String courseName; // 课程名称
  final String classNumber; // 班号
  final String teacher; // 教师
  final String scoreType; // 平时成绩名称
  final String proportion; // 占比
  final String score; // 成绩
  final String remark; // 备注
  final String submitTime; // 提交时间

  ScoreItem({
    required this.index,
    required this.term,
    required this.courseCode,
    required this.courseName,
    required this.classNumber,
    required this.teacher,
    required this.scoreType,
    required this.proportion,
    required this.score,
    required this.remark,
    required this.submitTime,
  });
}

/// 课程汇总信息
class CourseSummary {
  final String courseName; // 课程名称
  final double totalScore; // 总平时成绩
  final double totalProportion; // 平时成绩占比
  final double convertedScore; // 折算总成绩
  final List<ScoreItem> items; // 成绩项目列表

  CourseSummary({
    required this.courseName,
    required this.totalScore,
    required this.totalProportion,
    required this.convertedScore,
    required this.items,
  });
}

/// 学生平时成绩
class StudentScore {
  final List<CourseSummary> courses; // 课程列表

  StudentScore({required this.courses});
}
