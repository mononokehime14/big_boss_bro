import '../models/category.dart';
import '../models/menu_item.dart';

/// 示例分类与菜品（先用写死的数据，之后自己做分类/菜品管理界面）。
/// 分类图片以后用 assets/images/ 里的真实图片替换 emoji。
const List<Category> sampleCategories = [
  Category(id: 'hot', name: '热菜', emoji: '🍳'),
  Category(id: 'staple', name: '主食', emoji: '🍚'),
  Category(id: 'drink', name: '饮料', emoji: '🥤'),
  Category(id: 'cold', name: '凉菜', emoji: '🥗'),
];

const List<MenuItem> sampleMenu = [
  // 热菜
  MenuItem(id: 'h1', name: '牛肉炒饭', price: 28.00, emoji: '🍛', categoryId: 'hot'),
  MenuItem(id: 'h2', name: '宫保鸡丁', price: 32.00, emoji: '🍗', categoryId: 'hot'),
  MenuItem(id: 'h3', name: '麻婆豆腐', price: 22.00, emoji: '🌶️', categoryId: 'hot'),
  MenuItem(id: 'h4', name: '糖醋里脊', price: 36.00, emoji: '🍖', categoryId: 'hot'),
  // 主食
  MenuItem(id: 's1', name: '米饭', price: 5.00, emoji: '🍚', categoryId: 'staple'),
  MenuItem(id: 's2', name: '牛肉面', price: 25.00, emoji: '🍜', categoryId: 'staple'),
  MenuItem(id: 's3', name: '蛋炒饭', price: 18.00, emoji: '🍳', categoryId: 'staple'),
  MenuItem(id: 's4', name: '饺子', price: 20.00, emoji: '🥟', categoryId: 'staple'),
  // 饮料
  MenuItem(id: 'd1', name: '可乐', price: 5.00, emoji: '🥤', categoryId: 'drink'),
  MenuItem(id: 'd2', name: '橙汁', price: 8.00, emoji: '🍊', categoryId: 'drink'),
  MenuItem(id: 'd3', name: '绿茶', price: 6.00, emoji: '🍵', categoryId: 'drink'),
  MenuItem(id: 'd4', name: '啤酒', price: 10.00, emoji: '🍺', categoryId: 'drink'),
  // 凉菜
  MenuItem(id: 'c1', name: '凉拌黄瓜', price: 12.00, emoji: '🥒', categoryId: 'cold'),
  MenuItem(id: 'c2', name: '拍黄瓜', price: 10.00, emoji: '🥗', categoryId: 'cold'),
];
