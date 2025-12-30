import 'package:html/parser.dart' show parse;
import '../models/student_info.dart';
import '../models/student_score.dart';
import '../models/all_scores.dart';
import '../models/course_selection.dart';

/// HTML 解析服务
class HtmlParserService {
  /// 从 HTML 提取学生信息
  static StudentInfo? parseStudentInfo(String html) {
    try {
      final doc = parse(html);

      // 提取基本信息的辅助函数
      String getText(String label) {
        final cells = doc.querySelectorAll('td');
        for (int i = 0; i < cells.length; i++) {
          final text = cells[i].text.trim();
          if (text == label && i + 1 < cells.length) {
            return cells[i + 1].text.trim().replaceAll('&nbsp;', '').trim();
          }
        }
        return '';
      }

      // 提取学号
      final studentId = getText('学生学号');
      if (studentId.isEmpty) return null;

      // 提取异动记录
      final changeRecords = <StudentChangeRecord>[];
      final changeTable = doc.querySelector('table#table211');
      if (changeTable != null) {
        final rows = changeTable.querySelectorAll('tr');
        for (int i = 1; i < rows.length; i++) {
          // 跳过表头
          final cells = rows[i].querySelectorAll('td');
          if (cells.length >= 9) {
            changeRecords.add(
              StudentChangeRecord(
                index: cells[0].text.trim(),
                studentId: cells[1].text.trim(),
                name: cells[2].text.trim(),
                changeDate: cells[3].text.trim(),
                approvalDate: cells[4].text.trim(),
                changeType: cells[5].text.trim(),
                changeReason: cells[6].text.trim(),
                previousStatus: cells[7].text.trim(),
                operator: cells[8].text.trim(),
              ),
            );
          }
        }
      }

      return StudentInfo(
        studentId: studentId,
        name: getText('学生姓名'),
        passportName: getText('护照姓名'),
        gender: getText('学生性别'),
        birthDate: getText('出生年月'),
        status: _extractStatus(doc),
        enrollmentStatus: _extractEnrollmentStatus(doc),
        college: getText('专业学院'),
        grade: getText('当前年级'),
        major: getText('就读专业'),
        majorClass: getText('专业班级'),
        nationalMajor: getText('国标专业'),
        campus: getText('所在校区'),
        adminCollege: getText('行政学院'),
        adminClass: getText('行政班级'),
        nativePlace: getText('学生籍贯'),
        ethnicity: getText('学生民族'),
        politicalStatus: getText('政治面貌'),
        idCard: getText('身份证号'),
        examNumber: getText('考 生 号'),
        trainRoute: getText('乘车区间'),
        province: getText('省份'),
        city: getText('城市'),
        phone: getText('联系电话'),
        homeAddress: getText('家庭住址'),
        homePhone: getText('家庭电话'),
        postcode: getText('邮政编码'),
        birthplace: getText('生 源 地'),
        graduateSchool: getText('毕业学校'),
        candidateType: getText('考生类别'),
        admissionType: getText('录取形式'),
        admissionSource: getText('录取来源'),
        examSubject: getText('高考科类'),
        minorDegree: getText('辅修学位（辅修）'),
        studentTag: getText('学生标记'),
        trainingLevel: getText('培养层次'),
        examScore: getText('高考成绩'),
        foreignLanguage: getText('外语语种'),
        enrollmentDate: getText('入学时间'),
        dormitory: getText('宿 舍 号'),
        dormPhone: getText('宿舍电话'),
        motherPhone: getText('母亲电话'),
        fatherPhone: getText('父亲电话'),
        otherPhone: getText('其他电话'),
        email: getText('电子邮件'),
        height: getText('学生身高'),
        weight: _extractWeight(doc),
        bloodType: _extractBloodType(doc),
        specialSkills: getText('个人特长'),
        awards: getText('获奖情况'),
        remarks: _extractRemarks(doc),
        specialRemarks: getText('特殊备注'),
        changeRecords: changeRecords,
      );
    } catch (e) {
      print('[!] 解析学生信息失败: $e');
      return null;
    }
  }

  /// 提取学籍状态
  static String _extractStatus(dynamic doc) {
    final cells = doc.querySelectorAll('td');
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].text.trim() == '学籍状态' && i + 1 < cells.length) {
        final cell = cells[i + 1];
        final font = cell.querySelector('font');
        if (font != null) {
          return font.text.trim();
        }
      }
    }
    return '';
  }

  /// 提取在读状态
  static String _extractEnrollmentStatus(dynamic doc) {
    final cells = doc.querySelectorAll('td');
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].text.trim() == '学籍状态' && i + 1 < cells.length) {
        final text = cells[i + 1].text;
        if (text.contains('在读')) {
          return '在读';
        } else if (text.contains('休学')) {
          return '休学';
        } else if (text.contains('退学')) {
          return '退学';
        }
      }
    }
    return '';
  }

  /// 提取体重
  static String _extractWeight(dynamic doc) {
    final cells = doc.querySelectorAll('td');
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].text.trim() == '体重/血型' && i + 1 < cells.length) {
        final text = cells[i + 1].text.trim();
        final match = RegExp(r'(\d+\.?\d*)\s*KG').firstMatch(text);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    }
    return '';
  }

  /// 提取血型
  static String _extractBloodType(dynamic doc) {
    final cells = doc.querySelectorAll('td');
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].text.trim() == '体重/血型' && i + 1 < cells.length) {
        final text = cells[i + 1].text.trim();
        final match = RegExp(r'血型[：:]\s*([ABO]+)').firstMatch(text);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    }
    return '';
  }

  /// 从 HTML 提取平时成绩
  static StudentScore? parseStudentScore(String html) {
    try {
      final doc = parse(html);
      final courses = <CourseSummary>[];

      // 查找表格
      final table = doc.querySelector('table#table3');
      if (table == null) return null;

      final rows = table.querySelectorAll('tr');
      if (rows.length <= 1) return null; // 只有表头

      List<ScoreItem> currentCourseItems = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final cells = row.querySelectorAll('td');

        // 检查是否是汇总行
        if (cells.length == 1) {
          final text = cells[0].text.trim();
          if (text.contains('课程总平时成绩')) {
            // 解析汇总信息
            final match = RegExp(
              r'《(.+?)》课程总平时成绩为：([\d.]+)分，平时成绩占比([\d.]+)%，折算总成绩为：.+?([\d.]+)',
            ).firstMatch(text);

            if (match != null && currentCourseItems.isNotEmpty) {
              courses.add(
                CourseSummary(
                  courseName: match.group(1) ?? '',
                  totalScore: double.tryParse(match.group(2) ?? '0') ?? 0,
                  totalProportion: double.tryParse(match.group(3) ?? '0') ?? 0,
                  convertedScore: double.tryParse(match.group(4) ?? '0') ?? 0,
                  items: List.from(currentCourseItems),
                ),
              );
              currentCourseItems.clear();
            }
          }
        } else if (cells.length >= 11) {
          // 成绩项目行
          currentCourseItems.add(
            ScoreItem(
              index: cells[0].text.trim(),
              term: cells[1].text.trim(),
              courseCode: cells[2].text.trim(),
              courseName: cells[3].text.trim(),
              classNumber: cells[4].text.trim(),
              teacher: cells[5].text.trim(),
              scoreType: cells[6].text.trim(),
              proportion: cells[7].text.trim(),
              score: cells[8].text.trim(),
              remark: cells[9].text.trim(),
              submitTime: cells[10].text.trim(),
            ),
          );
        }
      }

      return StudentScore(courses: courses);
    } catch (e) {
      print('[!] 解析平时成绩失败: $e');
      return null;
    }
  }

  /// 提取备注信息
  static String _extractRemarks(dynamic doc) {
    final cells = doc.querySelectorAll('td');
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].text.trim() == '备注信息' && i + 1 < cells.length) {
        final cell = cells[i + 1];
        return cell.text
            .trim()
            .replaceAll('&nbsp;', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }
    return '';
  }

  /// 解析全部成绩HTML
  static AllScores? parseAllScores(String html) {
    try {
      final doc = parse(html);
      final List<CourseScore> scores = [];

      // 查找成绩表格（id="table3"）
      final table = doc.querySelector('table#table3');
      if (table == null) return null;

      // 获取所有数据行（跳过表头）
      final rows = table.querySelectorAll('tr');

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final cells = row.querySelectorAll('td');

        // 至少需要15个单元格
        if (cells.length < 15) continue;

        try {
          // 提取数据
          final courseCode = cells[1].text.trim();
          final courseName = cells[2].text.trim();
          final classNumber = cells[3].text.trim();
          final nature = cells[4].text.trim();
          final score = cells[5].text.trim();
          final finalScore = cells[6].text.trim();
          final normalScore = cells[7].text.trim();
          final examType = cells[8].text.trim();
          final creditText = cells[9].text.trim();
          final teacher = cells[10].text.trim();
          final gradeSystem = cells[11].text.trim();
          final academicYear = cells[12].text.trim();
          final semester = cells[13].text.trim();
          final remark = cells[14].text.trim();

          // 解析学分
          final credit = double.tryParse(creditText) ?? 0.0;

          scores.add(
            CourseScore(
              courseCode: courseCode,
              courseName: courseName,
              classNumber: classNumber,
              nature: nature,
              score: score,
              finalScore: finalScore,
              normalScore: normalScore,
              examType: examType,
              credit: credit,
              teacher: teacher,
              gradeSystem: gradeSystem,
              academicYear: academicYear,
              semester: semester,
              remark: remark,
            ),
          );
        } catch (e) {
          // 跳过解析失败的行
          continue;
        }
      }

      return AllScores(scores: scores);
    } catch (e) {
      print('解析全部成绩失败: $e');
      return null;
    }
  }

  /// 解析选课信息HTML
  static CourseSelection? parseCourseSelection(String html) {
    try {
      final doc = parse(html);
      final List<SelectedCourse> courses = [];

      // 查找选课表格
      final tables = doc.querySelectorAll('table');
      for (final table in tables) {
        final rows = table.querySelectorAll('tr');

        // 查找表头，确认是否为选课表格
        bool isCorrectTable = false;
        for (final row in rows) {
          final headers = row.querySelectorAll('th');
          if (headers.any((h) => h.text.contains('课程名称'))) {
            isCorrectTable = true;
            break;
          }
        }

        if (!isCorrectTable) continue;

        // 解析数据行
        for (final row in rows) {
          final cells = row.querySelectorAll('td');
          if (cells.length < 11) continue; // 至少需要11列

          try {
            // 提取学期信息（从第2列）
            final term = cells[1].text.trim();
            final selectCode = cells[2].text.trim();
            final courseCode = cells[3].text.trim();
            final courseName = cells[4].text.trim();
            final classNumber = cells[5].text.trim();
            final college = cells[6].text.trim();
            final teacher = cells[7].text.trim();
            final creditText = cells[8].text.trim();
            final nature = cells[9].text.trim();

            // 提取上课时间地点（第11列，索引10）
            String schedule = '';
            if (cells.length > 10) {
              // 获取原始HTML内容，保留<br>标签
              final scheduleHtml = cells[10].innerHtml;
              // 将<br>替换为空格，去除其他HTML标签
              schedule = scheduleHtml
                  .replaceAll(RegExp(r'<br\s*/?>'), ' ')
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
            }

            final credit = double.tryParse(creditText) ?? 0.0;

            courses.add(
              SelectedCourse(
                term: term,
                selectCode: selectCode,
                courseCode: courseCode,
                courseName: courseName,
                classNumber: classNumber,
                college: college,
                teacher: teacher,
                credit: credit,
                nature: nature,
                schedule: schedule,
              ),
            );
          } catch (e) {
            // 跳过解析失败的行
            continue;
          }
        }

        if (courses.isNotEmpty) break;
      }

      return CourseSelection(courses: courses);
    } catch (e) {
      print('解析选课信息失败: $e');
      return null;
    }
  }
}
