String formatTimestampToRelativeTime(int timeStamp) {
  final difference = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000));

  if (difference.inDays > 365) {
    return '${difference.inDays ~/ 365}年前';
  } else if (difference.inDays > 30) {
    return '${difference.inDays ~/ 30}个月前';
  } else if (difference.inDays > 0) {
    return '${difference.inDays}天前';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}小时前';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}分钟前';
  }
  return '刚刚';
}

String dateFormat(int timeStamp, {String formatType = 'list'}) {
  final time = (DateTime.now().millisecondsSinceEpoch / 1000).round();
  final distance = time - timeStamp;
  var currentYearStr = 'MM月DD日 hh:mm';
  var lastYearStr = 'YY年MM月DD日 hh:mm';
  if (formatType == 'detail') {
    currentYearStr = 'MM-DD hh:mm';
    lastYearStr = 'YY-MM-DD hh:mm';
    return _customTimestampString(
      timestamp: timeStamp,
      date: lastYearStr,
      toInt: false,
      formatType: formatType,
    );
  }
  if (distance <= 60) {
    return '刚刚';
  } else if (distance <= 3600) {
    return '${(distance / 60).floor()}分钟前';
  } else if (distance <= 43200) {
    return '${(distance / 60 / 60).floor()}小时前';
  } else if (DateTime.fromMillisecondsSinceEpoch(time * 1000).year ==
      DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000).year) {
    return _customTimestampString(
      timestamp: timeStamp,
      date: currentYearStr,
      toInt: false,
      formatType: formatType,
    );
  }
  return _customTimestampString(
    timestamp: timeStamp,
    date: lastYearStr,
    toInt: false,
    formatType: formatType,
  );
}

String _customTimestampString({
  int? timestamp,
  String? date,
  bool toInt = true,
  String? formatType,
}) {
  timestamp ??= (DateTime.now().millisecondsSinceEpoch / 1000).round();
  final timeStr =
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toString();
  final dateArr = timeStr.split(' ')[0];
  final timeArr = timeStr.split(' ')[1];

  final yy = dateArr.split('-')[0];
  var mm = dateArr.split('-')[1];
  var dd = dateArr.split('-')[2];
  var hh = timeArr.split(':')[0];
  var minute = timeArr.split(':')[1];
  var ss = timeArr.split(':')[2].split('.')[0];

  if (toInt) {
    mm = int.parse(mm).toString();
    dd = int.parse(dd).toString();
    hh = int.parse(hh).toString();
    minute = int.parse(minute).toString();
  }

  if (date == null) {
    return timeStr;
  }

  final formatted = date
      .replaceAll('YY', yy)
      .replaceAll('MM', mm)
      .replaceAll('DD', dd)
      .replaceAll('hh', hh)
      .replaceAll('mm', minute)
      .replaceAll('ss', ss);
  if (int.parse(yy) == DateTime.now().year &&
      int.parse(mm) == DateTime.now().month &&
      int.parse(dd) == DateTime.now().day) {
    return '今天';
  }
  return formatted;
}

int dateStringToWeekday(String dateString) {
  try {
    return DateTime.parse(dateString).weekday;
  } catch (_) {
    return 1;
  }
}

String formatDate(String dateString) {
  try {
    final date = DateTime.parse(dateString);
    return formatDateTime(date);
  } catch (_) {
    return dateString;
  }
}

String formatDateTime(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// 历史记录时间分组标签：今天 / 昨天 / 本周 / 本月 / 更早。
String historyGroupLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays <= 0) return '今天';
  if (diffDays == 1) return '昨天';
  if (diffDays < 7) return '本周';
  if (t.year == now.year && t.month == now.month) return '本月';
  return '更早';
}

/// 按时间分组标签把已排序（新→旧）列表分段；相邻同组合并，保持原顺序。
List<(String, List<T>)> groupByTimeLabel<T>(
  List<T> items,
  DateTime Function(T) timeOf,
) {
  final groups = <(String, List<T>)>[];
  for (final item in items) {
    final label = historyGroupLabel(timeOf(item));
    if (groups.isNotEmpty && groups.last.$1 == label) {
      groups.last.$2.add(item);
    } else {
      groups.add((label, [item]));
    }
  }
  return groups;
}
