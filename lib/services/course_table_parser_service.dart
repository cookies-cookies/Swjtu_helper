import 'package:html/parser.dart' as html_parser show parse;

class CourseSlot {
  final String courseCode;
  final String courseName;
  final String teacher;
  final String weeks; // e.g. "1-17周" or "4-6周"
  final String room; // e.g. "X2416" or "北区田径场"
  final String day; // 星期一..星期日
  final String lectureLabel; // 第2讲
  final String sectionRange; // (3-5节)

  CourseSlot({
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.weeks,
    required this.room,
    required this.day,
    required this.lectureLabel,
    required this.sectionRange,
  });
}

class CourseTable {
  final List<CourseSlot> slots;
  CourseTable(this.slots);
}

class CourseTableParser {
  /// 解析课程表 HTML（printCourseTable 页面），返回结构化课程槽列表
  static CourseTable parse(String html) {
    final doc = html_parser.parse(html);

    final table = doc.querySelector('table.table_border');
    if (table == null) return CourseTable([]);

    // 解析星期头，从第一个行的 th 或 td 中获取星期名称
    final headerRow = table.querySelector('tr');
    final headers = <String>[];
    if (headerRow != null) {
      final headerTds = headerRow.querySelectorAll('td,th');
      for (var i = 0; i < headerTds.length; i++) {
        final text = headerTds[i].text.trim();
        headers.add(text);
      }
    }

    final slots = <CourseSlot>[];

    // 从第二行开始，每行代表一个 lecture block（例如 第2讲）
    final rows = table.querySelectorAll('tr').skip(1);
    for (var row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;

      // 第一列通常是讲次/节次标签
      final lectureLabel = cells.first.text.trim().split('\n').first.trim();
      final sectionRangeMatch = RegExp(
        r"\(([^)]*)\)",
      ).firstMatch(cells.first.text);
      final sectionRange = sectionRangeMatch?.group(1) != null
          ? '(${sectionRangeMatch!.group(1)})'
          : '';

      // weekdays start from index 1
      for (var i = 1; i < cells.length; i++) {
        final dayName = (i - 1) < headers.length ? headers[i] : '星期${i}';
        final cell = cells[i];

        // cell.innerHtml may contain <br> separated entries
        final parts = <String>[];
        for (var node in cell.nodes) {
          final s = node.text?.trim() ?? '';
          if (s.isNotEmpty) parts.add(s);
        }

        // parts likely in pairs: courseLine, weekRoomLine, courseLine, weekRoomLine,...
        for (var p = 0; p + 1 < parts.length; p += 2) {
          final courseLine = parts[p];
          final weekRoomLine = parts[p + 1];

          // 解析 courseLine: 格式示例 "B2161 概率论与数理统计(彭皓)" 或 "B2877 大学物理实验Ⅱ(魏云,樊代和,李相强)"
          final codeMatch = RegExp(
            r'^([A-Za-z0-9]+)\s*(.*)\((.*)\)\s*\$?',
          ).firstMatch(courseLine);
          String code = '';
          String name = courseLine;
          String teacher = '';
          if (codeMatch != null) {
            code = codeMatch.group(1) ?? '';
            name = (codeMatch.group(2) ?? '').trim();
            teacher = (codeMatch.group(3) ?? '').trim();
          } else {
            // 退而求其次：尝试把第一个空格前的作为 code
            final idx = courseLine.indexOf(' ');
            if (idx > 0) {
              code = courseLine.substring(0, idx).trim();
              final rest = courseLine.substring(idx + 1).trim();
              // 尝试提取括号内教师
              final tm = RegExp(r'^(.*)\((.*)\)\s*\$?').firstMatch(rest);
              if (tm != null) {
                name = tm.group(1) ?? rest;
                teacher = tm.group(2) ?? '';
              } else {
                name = rest;
              }
            } else {
              name = courseLine;
            }
          }

          // weekRoomLine 示例: "1-17周 X2416" 或 "北区田径场"
          String weeks = '';
          String room = '';
          final wrParts = weekRoomLine.split(RegExp(r'\s+'));
          if (wrParts.length >= 2) {
            weeks = wrParts[0];
            room = wrParts.sublist(1).join(' ');
          } else if (wrParts.length == 1) {
            // 可能只有位置或只有周次
            final t = wrParts[0];
            if (t.contains('周'))
              weeks = t;
            else
              room = t;
          }

          // 创建 slot
          slots.add(
            CourseSlot(
              courseCode: code,
              courseName: name,
              teacher: teacher,
              weeks: weeks,
              room: room,
              day: dayName,
              lectureLabel: lectureLabel,
              sectionRange: sectionRange,
            ),
          );
        }
      }
    }

    return CourseTable(slots);
  }
}
