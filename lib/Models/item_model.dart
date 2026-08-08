// =============================================================================
// ITEM MODELS (lib/models/item_model.dart)
// Menu structure + cart line items. Kept identical to the original inline
// classes so nothing else in the app has to change shape.
// =============================================================================

class MenuGroupModel {
  final String title;
  final List<MenuItemModel> items;

  MenuGroupModel({required this.title, required this.items});
}

class MenuItemModel {
  final String name;
  final String price;
  final String img;
  final List<String> extras;

  MenuItemModel({
    required this.name,
    required this.price,
    required this.img,
    required this.extras,
  });
}

class CartItemModel {
  final String id;
  final String name;
  final String price;
  final String img;
  final List<String> chosenExtras;

  CartItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.img,
    required this.chosenExtras,
  });
}
