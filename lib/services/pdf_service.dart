// =============================================================================
// PDF SERVICE (lib/services/pdf_service.dart)
// NOTE: generateAndShareMonthlyBill() is no longer called from
// AdminDashboard._generateTwoDayBill() — that flow now goes through
// BillAutomationService + BillingService instead (see bill_automation_service.dart).
// Kept here unchanged in case anything else in the project still references it.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

class PdfService {
  /// Robust string/number parser
  static double parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is num) return amount.toDouble();

    String strValue = amount.toString();
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(strValue);
    if (match != null) {
      return double.tryParse(match.group(0)!) ?? 0.0;
    }
    return 0.0;
  }

  /// Cleans duplicate prefixes from address fields
  static String resolveAddress(Map<String, dynamic> customer) {
    final String wing = customer['wing']?.toString().trim() ?? '';
    final String houseNo = customer['houseNo']?.toString().trim() ?? customer['house']?.toString().trim() ?? '';
    
    String rawAddress = customer['address']?.toString().trim() ?? customer['society']?.toString().trim() ?? '';
    
    // Clean string prefixes like "Society: Pawan Appartment" or "Society: "
    rawAddress = rawAddress.replaceAll(RegExp(r'^Society:\s*', caseSensitive: false), '').trim();

    List<String> parts = [];
    if (wing.isNotEmpty) parts.add('Wing: $wing');
    if (houseNo.isNotEmpty) parts.add('House No: $houseNo');
    if (rawAddress.isNotEmpty) parts.add('Society: $rawAddress');

    return parts.isNotEmpty ? parts.join(', ') : 'N/A';
  }

  /// Generates PDF bill and launches WhatsApp share modal
  static Future<bool> generateAndShareMonthlyBill(
    Map<String, dynamic> customer, [
    dynamic pendingAmountParam,
  ]) async {
    try {
      final name = customer['name']?.toString() ?? 'Customer';
      final mobile = customer['mobile']?.toString() ?? customer['phone']?.toString() ?? '';
      final routeName = customer['routeName']?.toString() ?? customer['route']?.toString() ?? 'Route2';

      // 1. Resolve Address
      final address = resolveAddress(customer);

      // 2. Resolve Amount: Prioritize explicitly passed param -> Customer Map Keys
      double numericAmount = parseAmount(pendingAmountParam);
      if (numericAmount == 0.0) {
        final possibleKeys = ['pendingAmount', 'totalPending', 'pending', 'paymentPending', 'amount', 'dueAmount', 'balance'];
        for (var key in possibleKeys) {
          if (customer[key] != null) {
            numericAmount = parseAmount(customer[key]);
            if (numericAmount > 0) break;
          }
        }
      }

      final String formattedAmount = numericAmount.toStringAsFixed(2);

      // 3. Load Unicode Fonts
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final fontItalic = await PdfGoogleFonts.robotoItalic();

      // 4. Generate PDF Document
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Viraj Dairy',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 24,
                              color: PdfColors.blue900,
                            ),
                          ),
                          pw.Text(
                            '2-Day Billing Statement',
                            style: pw.TextStyle(font: font, fontSize: 12),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Date: ${DateTime.now().toString().split(' ')[0]}',
                            style: pw.TextStyle(font: font),
                          ),
                          pw.Text(
                            'Route: $routeName',
                            style: pw.TextStyle(font: font),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 1, height: 20),

                  // Customer Details
                  pw.Text('Customer Details:', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  pw.SizedBox(height: 4),
                  pw.Text('Name: $name', style: pw.TextStyle(font: font)),
                  pw.Text('Mobile: $mobile', style: pw.TextStyle(font: font)),
                  pw.Text('Address: $address', style: pw.TextStyle(font: font)),
                  pw.SizedBox(height: 16),

                  // Item Table
                  pw.TableHelper.fromTextArray(
                    headers: ['Description', 'Billing Period', 'Amount'],
                    data: [
                      ['Milk Delivery & Services', '2-Day Cycle', 'Rs. $formattedAmount'],
                    ],
                    headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white),
                    cellStyle: pw.TextStyle(font: font),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                    cellAlignment: pw.Alignment.centerLeft,
                  ),
                  pw.SizedBox(height: 20),

                  // Footer
                  pw.Text(
                    'Note: Please scan the UPI QR code on your app dashboard or pay via UPI to clear pending dues.',
                    style: pw.TextStyle(font: fontItalic, fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      final filename = 'Bill_${mobile}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // 5. Open Share Dialog
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: filename,
      );

      // 6. Launch WhatsApp
      if (mobile.isNotEmpty) {
        final cleanMobile = mobile.toString().replaceAll(RegExp(r'[^0-9]'), '');
        final formattedPhone = cleanMobile.startsWith('91') || cleanMobile.length > 10
            ? cleanMobile
            : '91$cleanMobile';

        final whatsappMessage =
            'Hello $name,\n\n'
            'Your 2-day bill statement from Viraj Dairy has been generated.\n'
            'Amount Due: Rs. $formattedAmount\n\n'
            'Please check your dashboard to view the full PDF and make payment via UPI QR.';

        final whatsappUri = Uri.parse('https://wa.me/$formattedPhone?text=${Uri.encodeComponent(whatsappMessage)}');

        if (await canLaunchUrl(whatsappUri)) {
          await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
        } else {
          debugPrint('Could not launch WhatsApp for $mobile');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error generating/sharing bill PDF: $e');
      return false;
    }
  }
}