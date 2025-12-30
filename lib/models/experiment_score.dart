/// 实验成绩数据模型
class ExperimentScore {
  final String id;
  final String courseName;
  final String experimentName;
  final String teacher;
  final String? score;
  final bool needsEvaluation;
  final String? evaluationStatus;
  final String? submitDate;
  final String? experimentDate;
  final double? evaluationScore; // 评价分数

  const ExperimentScore({
    required this.id,
    required this.courseName,
    required this.experimentName,
    required this.teacher,
    this.score,
    this.needsEvaluation = false,
    this.evaluationStatus,
    this.submitDate,
    this.experimentDate,
    this.evaluationScore,
  });

  /// 是否有成绩
  bool get hasScore => score != null && score!.isNotEmpty;

  /// 成绩显示文本
  String get scoreDisplay => hasScore ? score! : '待评价';

  /// 状态显示文本
  String get statusDisplay {
    if (hasScore) return '已完成';
    if (needsEvaluation) return '待评价';
    return '进行中';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'courseName': courseName,
      'experimentName': experimentName,
      'teacher': teacher,
      'score': score,
      'needsEvaluation': needsEvaluation,
      'evaluationStatus': evaluationStatus,
      'submitDate': submitDate,
      'experimentDate': experimentDate,
      'evaluationScore': evaluationScore,
    };
  }

  factory ExperimentScore.fromJson(Map<String, dynamic> json) {
    return ExperimentScore(
      id: json['id'] as String,
      courseName: json['courseName'] as String,
      experimentName: json['experimentName'] as String,
      teacher: json['teacher'] as String,
      score: json['score'] as String?,
      needsEvaluation: json['needsEvaluation'] as bool? ?? false,
      evaluationStatus: json['evaluationStatus'] as String?,
      submitDate: json['submitDate'] as String?,
      experimentDate: json['experimentDate'] as String?,
      evaluationScore: json['evaluationScore'] as double?,
    );
  }

  @override
  String toString() {
    return 'ExperimentScore(courseName: $courseName, experimentName: $experimentName, score: $scoreDisplay, status: $statusDisplay)';
  }
}
