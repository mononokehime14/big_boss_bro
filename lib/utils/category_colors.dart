/// 分类配色（纯 Dart，不依赖 Flutter，方便服务和测试使用）。
///
/// 规则很简单：**按分类顺序轮换调色板**，所以**相邻分类一定不同色**。
/// 调色板里的颜色都偏深，配白色文字对比度足够。
library;

/// 10 个深浅适中、彼此区分度高的颜色（ARGB）。
const List<int> kCategoryPalette = <int>[
  0xFFC62828, // 红
  0xFF1565C0, // 蓝
  0xFF2E7D32, // 绿
  0xFFEF6C00, // 橙
  0xFF6A1B9A, // 紫
  0xFF00838F, // 青
  0xFF4E342E, // 棕
  0xFFAD1457, // 玫红
  0xFF37474F, // 蓝灰
  0xFF558B2F, // 橄榄绿
];

/// 第 [index] 个分类该用的颜色（自动轮换）。
int paletteColorAt(int index) =>
    kCategoryPalette[index % kCategoryPalette.length];

/// 取分类颜色：[colorValue] 为 0（没设过）时按顺序从调色板取。
int categoryColorAt(int colorValue, int index) =>
    colorValue == 0 ? paletteColorAt(index) : colorValue;
