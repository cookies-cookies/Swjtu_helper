/// 学生信息模型
class StudentInfo {
  final String studentId; // 学号
  final String name; // 姓名
  final String passportName; // 护照姓名
  final String gender; // 性别
  final String birthDate; // 出生年月
  final String status; // 学籍状态
  final String enrollmentStatus; // 在读状态
  final String college; // 专业学院
  final String grade; // 当前年级
  final String major; // 就读专业
  final String majorClass; // 专业班级
  final String nationalMajor; // 国标专业
  final String campus; // 所在校区
  final String adminCollege; // 行政学院
  final String adminClass; // 行政班级
  final String nativePlace; // 籍贯
  final String ethnicity; // 民族
  final String politicalStatus; // 政治面貌
  final String idCard; // 身份证号
  final String examNumber; // 考生号
  final String trainRoute; // 乘车区间
  final String province; // 省份
  final String city; // 城市
  final String phone; // 联系电话
  final String homeAddress; // 家庭住址
  final String homePhone; // 家庭电话
  final String postcode; // 邮政编码
  final String birthplace; // 生源地
  final String graduateSchool; // 毕业学校
  final String candidateType; // 考生类别
  final String admissionType; // 录取形式
  final String admissionSource; // 录取来源
  final String examSubject; // 高考科类
  final String minorDegree; // 辅修学位
  final String studentTag; // 学生标记
  final String trainingLevel; // 培养层次
  final String examScore; // 高考成绩
  final String foreignLanguage; // 外语语种
  final String enrollmentDate; // 入学时间
  final String dormitory; // 宿舍号
  final String dormPhone; // 宿舍电话
  final String motherPhone; // 母亲电话
  final String fatherPhone; // 父亲电话
  final String otherPhone; // 其他电话
  final String email; // 电子邮件
  final String height; // 学生身高
  final String weight; // 体重
  final String bloodType; // 血型
  final String specialSkills; // 个人特长
  final String awards; // 获奖情况
  final String remarks; // 备注信息
  final String specialRemarks; // 特殊备注
  final List<StudentChangeRecord> changeRecords; // 学籍异动记录

  StudentInfo({
    required this.studentId,
    required this.name,
    this.passportName = '',
    this.gender = '',
    this.birthDate = '',
    this.status = '',
    this.enrollmentStatus = '',
    this.college = '',
    this.grade = '',
    this.major = '',
    this.majorClass = '',
    this.nationalMajor = '',
    this.campus = '',
    this.adminCollege = '',
    this.adminClass = '',
    this.nativePlace = '',
    this.ethnicity = '',
    this.politicalStatus = '',
    this.idCard = '',
    this.examNumber = '',
    this.trainRoute = '',
    this.province = '',
    this.city = '',
    this.phone = '',
    this.homeAddress = '',
    this.homePhone = '',
    this.postcode = '',
    this.birthplace = '',
    this.graduateSchool = '',
    this.candidateType = '',
    this.admissionType = '',
    this.admissionSource = '',
    this.examSubject = '',
    this.minorDegree = '',
    this.studentTag = '',
    this.trainingLevel = '',
    this.examScore = '',
    this.foreignLanguage = '',
    this.enrollmentDate = '',
    this.dormitory = '',
    this.dormPhone = '',
    this.motherPhone = '',
    this.fatherPhone = '',
    this.otherPhone = '',
    this.email = '',
    this.height = '',
    this.weight = '',
    this.bloodType = '',
    this.specialSkills = '',
    this.awards = '',
    this.remarks = '',
    this.specialRemarks = '',
    this.changeRecords = const [],
  });
}

/// 学籍异动记录
class StudentChangeRecord {
  final String index; // 序号
  final String studentId; // 学号
  final String name; // 姓名
  final String changeDate; // 异动日期
  final String approvalDate; // 批准日期
  final String changeType; // 异动类型
  final String changeReason; // 异动原因
  final String previousStatus; // 异动前学籍
  final String operator; // 经办人

  StudentChangeRecord({
    required this.index,
    required this.studentId,
    required this.name,
    required this.changeDate,
    required this.approvalDate,
    required this.changeType,
    required this.changeReason,
    required this.previousStatus,
    required this.operator,
  });
}
