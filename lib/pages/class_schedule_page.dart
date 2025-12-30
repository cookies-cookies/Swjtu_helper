import 'package:flutter/material.dart';
import '../services/course_table_parser_service.dart';

class ClassSchedulePage extends StatelessWidget {
  final CourseTable table;
  final bool embedded;

  const ClassSchedulePage({
    super.key,
    required this.table,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    // 按 day 分组
    final Map<String, List<CourseSlot>> byDay = {};
    for (var s in table.slots) {
      byDay.putIfAbsent(s.day, () => []).add(s);
    }

    final days = byDay.keys.toList();

    final content = days.isEmpty
        ? const Center(child: Text('未解析到课程'))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: days.length,
            itemBuilder: (context, idx) {
              final day = days[idx];
              final slots = byDay[day]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var s in slots)
                        ListTile(
                          title: Text('${s.courseName} (${s.courseCode})'),
                          subtitle: Text(
                            '${s.teacher}\n${s.weeks}  ${s.room}\n${s.lectureLabel} ${s.sectionRange}',
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );

    // 如果是嵌入模式，直接返回内容
    if (embedded) {
      return content;
    }

    // 否则返回带 AppBar 的完整页面
    return Scaffold(
      appBar: AppBar(title: const Text('解析的班级课表')),
      body: content,
    );
  }
}
