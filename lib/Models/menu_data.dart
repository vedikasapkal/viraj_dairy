// =============================================================================
// MENU CATALOG DATA (lib/models/menu_data.dart)
// Pulled out of CustomerDashboard so the screen file stays about UI, not data.
// Same exact products/prices/extras as before — just relocated.
// =============================================================================

import 'item_model.dart';

final List<MenuGroupModel> menuGroups = [
  MenuGroupModel(title: "Milk & Dahi", items: [
    MenuItemModel(name: 'Cow Milk', price: '₹80', img: 'assets/milk-left.jpg', extras: ['500ml', '1 Litre']),
    MenuItemModel(name: 'Buffalo Milk', price: '₹90', img: 'assets/milk-right.jpg', extras: ['500ml', '1 Litre']),
    MenuItemModel(name: 'Curd', price: '₹180', img: 'assets/chakka.jpg', extras: ['250g', '500g', '1kg']),
    MenuItemModel(name: 'Butter Milk', price: '₹60', img: 'assets/sweet-lassi.jpg', extras: ['500ml', '1 Litre']),
  ]),
  MenuGroupModel(title: "Ghee", items: [
    MenuItemModel(name: "Cow Ghee", price: "₹900", img: "assets/cow-ghee.avif", extras: ["250g", "500g", "1kg"]),
    MenuItemModel(name: "Buffalo Ghee", price: "₹900", img: "assets/buffalo-ghee.avif", extras: ["250g", "500g", "1kg"]),
  ]),
  MenuGroupModel(title: "Butter", items: [
    MenuItemModel(name: 'Cow Butter', price: '₹800', img: 'assets/cow-ghee.avif', extras: ['250g', '500g', '1kg']),
    MenuItemModel(name: 'Buffalo Butter', price: '₹800', img: 'assets/buffalo-ghee.avif', extras: ['250g', '500g', '1kg']),
  ]),
  MenuGroupModel(title: "Lassi & Cold Drinks", items: [
    MenuItemModel(name: "Lassi", price: "₹50", img: "assets/sweet-lassi.jpg", extras: ["200ml"]),
  ]),
  MenuGroupModel(title: "Sweets (Mithai)", items: [
    MenuItemModel(name: "Shrikhand", price: "₹400", img: "assets/shrikhand.jpg", extras: ["250g", "500g"]),
    MenuItemModel(name: "Aamrakhand", price: "₹400", img: "assets/amrakhand.jpg", extras: ["250g", "500g"]),
    MenuItemModel(name: "Basundhi", price: "₹400", img: "assets/basundi4.jpg", extras: ["250g", "500g"]),
    MenuItemModel(name: "Khawa", price: "₹440", img: "assets/khava.jpg", extras: ["250g", "500g", "1kg"]),
    MenuItemModel(name: "Paneer", price: "₹440", img: "assets/paneer.jpg", extras: ["250g", "500g", "1kg"]),
    MenuItemModel(name: "Kharwas Milk", price: "₹350", img: "assets/kharvas-milk.jpg", extras: ["500ml"]),
  ]),
  MenuGroupModel(title: "Other Items", items: [
    MenuItemModel(name: "Green Peas", price: "₹150", img: "assets/greenpeace.jpg", extras: ["200gm", "1kg"]),
  ]),
  MenuGroupModel(title: "Brand - English Oven", items: [
    MenuItemModel(name: "Garlic Bread", price: "₹35", img: "assets/garlic braed.webp", extras: ["200gm"]),
    MenuItemModel(name: "MultiGrain Zero Maida", price: "₹65", img: "assets/MultiGrain Zero Maida.jpg", extras: ["400gm"]),
    MenuItemModel(name: "Sandwich Bread", price: "₹45", img: "assets/Sandwich Bread.jpg", extras: ["400gm"]),
    MenuItemModel(name: "Whole Wheat Bread No Maida", price: "₹60", img: "assets/Whole Wheat Bread No Maida.jpg", extras: ["400gm"]),
    MenuItemModel(name: "Brown Bread", price: "₹55", img: "assets/Brown Bread.jpg", extras: ["400gm"]),
    MenuItemModel(name: "Milk Bread", price: "₹45", img: "assets/Milk Bread.jpg", extras: ["400gm"]),
    MenuItemModel(name: "White Bread", price: "₹65", img: "assets/White Bread.jpg", extras: ["600gm"]),
    MenuItemModel(name: "Nutrilay Fresh Egg", price: "₹60", img: "assets/Nutrilay Fresh Egg.jpg", extras: ["6 pcs"]),
  ]),
  MenuGroupModel(title: "Brand - Amul", items: [
    MenuItemModel(name: "Cheese Cubes", price: "₹135", img: "assets/Cheese Cubes.jpg", extras: ["8 pcs"]),
    MenuItemModel(name: "Cheese Block", price: "₹129", img: "assets/Cheese Block.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Cheese Block", price: "₹300", img: "assets/Cheese Block.jpg", extras: ["500gm"]),
    MenuItemModel(name: "Butter", price: "₹310", img: "assets/Butter.jpg", extras: ["500gm"]),
    MenuItemModel(name: "Butter", price: "₹63", img: "assets/Butter.jpg", extras: ["100gm"]),
    MenuItemModel(name: "Garlic Butter", price: "₹70", img: "assets/Garlic Butter.jpg", extras: ["100gm"]),
    MenuItemModel(name: "Cheese Slice", price: "₹145", img: "assets/Cheese Slice.jpg", extras: ["10 pcs"]),
    MenuItemModel(name: "Cheese S.", price: "₹82", img: "assets/Cheese Slice.jpg", extras: ["5 pcs"]),
    MenuItemModel(name: "Fresh Cream", price: "₹75", img: "assets/Fresh Cream.jpg", extras: ["250gm"]),
    MenuItemModel(name: "Pasteurised Butter", price: "₹130", img: "assets/Pasteurised Butter.jpg", extras: ["200gm"]),
  ]),
  MenuGroupModel(title: "Brand - Malpanis (Bake Lite) Bakery", items: [
    MenuItemModel(name: "Puneri Spcl Khari", price: "₹90", img: "assets/Puneri Spcl Khari.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Brown Khari", price: "₹90", img: "assets/Brown Khari.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Maska Khari", price: "₹80", img: "assets/Maska Khari.jpg", extras: ["175gm"]),
    MenuItemModel(name: "Twisted Khari", price: "₹90", img: "assets/Twisted Khari.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Tuti Fruti Toast", price: "₹52", img: "assets/Tuti Fruti Toast.jpg", extras: ["150gm"]),
    MenuItemModel(name: "Brown Toast No Added Sugar", price: "₹62", img: "assets/Brown Toast No Added Sugar.jpg", extras: ["150gm"]),
    MenuItemModel(name: "Milk Toast", price: "₹68", img: "assets/Milk Toast.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Brown Toast", price: "₹75", img: "assets/Brown Toast.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Sliced Cake Mawa Magic", price: "₹110", img: "assets/Sliced Cake Mawa Magic.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Cream Roll", price: "₹75", img: "assets/Cream Roll.jpg", extras: ["5 pcs"]),
    MenuItemModel(name: "Cream Roll", price: "₹150", img: "assets/Cream Roll.jpg", extras: ["10 pcs"]),
    MenuItemModel(name: "Namkeen Mathri", price: "₹75", img: "assets/Namkeen Mathri.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Shankarpali", price: "₹50", img: "assets/Shankarpali.jpg", extras: ["125gm"]),
    MenuItemModel(name: "Chiroti", price: "₹85", img: "assets/Chiroti.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Jeera Butter", price: "₹78", img: "assets/Jeera Butter.jpg", extras: ["180gm"]),
    MenuItemModel(name: "Bhakareadi", price: "₹80", img: "assets/Bhakareadi.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Chakali", price: "₹80", img: "assets/chakli.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Finger Cake", price: "₹360", img: "assets/Finger Cake.webp", extras: ["24 pcs"]),
  ]),
  MenuGroupModel(title: "Brand - Lakshmi Narayan Farsan", items: [
    MenuItemModel(name: "Farsan Misal Spcl", price: "₹125", img: "assets/Farsan Misal Spcl.jpg", extras: ["450gm"]),
    MenuItemModel(name: "Farsan Namkeen", price: "₹125", img: "assets/Farsan Namkeen.jpg", extras: ["450gm"]),
    MenuItemModel(name: "2no Sev", price: "₹60", img: "assets/2no Sev.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Khari Bundi", price: "₹60", img: "assets/Khari Bundi.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Best Chiwda", price: "₹95", img: "assets/Best Chiwda.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Nylon Shev", price: "₹60", img: "assets/Nylon Shev.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Potato Chiwda", price: "₹95", img: "assets/Potato Chiwda.jpg", extras: ["200gm"]),
    MenuItemModel(name: "Masala Bhavnagari", price: "₹60", img: "assets/Masala Bhavnagari.jpg", extras: ["200gm"]),
  ]),
  MenuGroupModel(title: "Brand - Katdare (कटधरे मसाले)", items: [
    MenuItemModel(name: "Mango Pickle", price: "₹68", img: "assets/Mango Pickle.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Green Chilli Pickle", price: "₹68", img: "assets/Green Chilli Pickle.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Lemon Pickle", price: "₹68", img: "assets/Lemon Pickle.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Mix Pickle", price: "₹68", img: "assets/Mix Pickle.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Sweet Lemon", price: "₹68", img: "assets/Sweet Lemon.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Shengdana Chatni", price: "₹50", img: "assets/Shengdana Chatni.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Kali Chatni", price: "₹50", img: "assets/Kali Chatni.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Jawas Chatni", price: "₹50", img: "assets/Jawas Chatni.jpg", extras: ["Standard"]),
    MenuItemModel(name: "Lasoon Chatni", price: "₹65", img: "assets/Lasoon Chatni.jpg", extras: ["Standard"]),
  ]),
  MenuGroupModel(title: "Brand - Suhana", items: [
    MenuItemModel(name: "paneer Tikka masala", price: "₹50", img: "assets/Paneer Butter Masala.jpg", extras: ["50gm"]),
    MenuItemModel(name: "Paneer Butter Masala", price: "₹50", img: "assets/Paneer Butter Masala.jpg", extras: ["50gm"]),
    MenuItemModel(name: "Shahi Paneer Masala", price: "₹45", img: "assets/Shahi Paneer Masala.jpg", extras: ["50gm"]),
    MenuItemModel(name: "Mattar Paneer Masala", price: "₹50", img: "assets/Mattar Paneer Masala.jpg", extras: ["50gm"]),
    MenuItemModel(name: "Veg Biryani Masala", price: "₹50", img: "assets/Veg Biryani Masala.jpg", extras: ["50gm"]),
    MenuItemModel(name: "Paneer Chilli Masala", price: "₹41", img: "assets/Paneer Chilli Masala.jpg", extras: ["50gm"]),
  ]),
];
