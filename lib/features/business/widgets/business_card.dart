import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/business_model.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessCard extends StatelessWidget {
  final BusinessModel business;
  final bool showStatusBadge; // True for 'My Businesses' view in profile

  const BusinessCard({Key? key, required this.business, this.showStatusBadge = false}) : super(key: key);

  Future<void> _makePhoneCall(BuildContext context) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: business.phone,
    );
    if (!await launchUrl(launchUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch dialer')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: business.imageUrl,
                height: 80,
                width: 80,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 80,
                  width: 80,
                  color: Colors.grey[200],
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, err) => Container(
                  height: 80,
                  width: 80,
                  color: Colors.grey[200],
                  child: Icon(Icons.storefront, color: Colors.grey),
                ),
              ),
            ),
            SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),

                  // Category & Status
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          business.category,
                          style: TextStyle(fontSize: 10, color: Colors.blue[800]),
                        ),
                      ),
                      if (showStatusBadge) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: business.status == 'approved'
                                ? Colors.green[50]
                                : business.status == 'rejected'
                                    ? Colors.red[50]
                                    : Colors.orange[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            business.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: business.status == 'approved'
                                  ? Colors.green[800]
                                  : business.status == 'rejected'
                                      ? Colors.red[800]
                                      : Colors.orange[800],
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),

                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          business.area,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),

            // Call Button
            if (!showStatusBadge || business.status == 'approved')
              IconButton(
                icon: Icon(Icons.call, color: Colors.green),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green[50],
                  padding: EdgeInsets.all(12),
                ),
                onPressed: () => _makePhoneCall(context),
              ),
          ],
        ),
      ),
    );
  }
}
