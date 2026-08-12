class AppModule {
  const AppModule(this.title, this.route, this.section);
  final String title;
  final String route;
  final String section;
}

/// Mirrors the merchant app module breakdown in the architecture doc,
/// Section 4. Payment collection (4.5) has no dedicated screen — it happens
/// on the hosted checkout page (src/web), not in-app.
const List<AppModule> appModules = [
  AppModule('Catalog & Items', '/catalog', '4.2'),
  AppModule('Invoices', '/invoices', '4.3'),
  AppModule('Messaging', '/messaging', '4.4'),
  AppModule('Order Requests', '/order-requests', '4.6'),
  AppModule('Records & Reporting', '/records', '4.7'),
  AppModule('Fees & Settlement', '/settings', '4.8'),
  AppModule('Staff', '/staff', '4.9'),
  AppModule('Notifications', '/notifications', '4.10'),
  AppModule('Delivery', '/delivery', '4.11'),
];
