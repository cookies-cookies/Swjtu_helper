/// 选课数据模型

class CourseSelection {
  final List<SelectedCourse> courses;

  CourseSelection({required this.courses});

  // 按学期分组
  Map<String, List<SelectedCourse>> groupByTerm() {
    final Map<String, List<SelectedCourse>> grouped = {};
    for (final course in courses) {
      final key = course.term;
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(course);
    }
    return grouped;
  }

  // 计算总学分
  double get totalCredits {
    return courses.fold(0.0, (sum, course) => sum + course.credit);
  }
}

class SelectedCourse {
  final String term; // 学期（如：2025-2026第1学期）
  final String selectCode; // 选课编号
  final String courseCode; // 课程代码
  final String courseName; // 课程名称
  final String classNumber; // 班号
  final String college; // 开课学院
  final String teacher; // 任课教师
  final double credit; // 学分
  final String nature; // 课程性质（必修/选修）
  final String schedule; // 上课时间地点

  SelectedCourse({
    required this.term,
    required this.selectCode,
    required this.courseCode,
    required this.courseName,
    required this.classNumber,
    required this.college,
    required this.teacher,
    required this.credit,
    required this.nature,
    required this.schedule,
  });

  // 判断是否为必修课
  bool get isRequired => nature.contains('必');

  // 判断是否为选修课
  bool get isElective => nature.contains('选');
}
