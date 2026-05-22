import 'package:flutter/material.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.arrow_back_ios, color: Colors.black54),
                  Row(
                    children: [
                      Stack(
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              color: Colors.green, size: 28),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(width: 16),
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.menu, color: Colors.black87),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),

              // Profile
              Row(
                children: const [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: AssetImage('assets/profile.jpg'),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Robert Williamson',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Discount, Bonuses, Deposit
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF5E35B1),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatisticCard('10%', 'Discount'),
                    Stack(
                      children: [
                        _buildStatisticCard('\$32', 'Bonuses'),
                        Positioned(
                          right: 4,
                          top: 0,
                          child: _buildBadge(),
                        )
                      ],
                    ),
                    _buildStatisticCard('\$70', 'Deposit'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Options Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _buildGridItem(Icons.receipt_long, 'Orders History'),
                  _buildGridItem(Icons.credit_card, 'Payment method'),
                  Stack(
                    children: [
                      _buildGridItem(Icons.public, 'Tracking'),
                      Positioned(
                        right: 12,
                        top: 8,
                        child: _buildBadge(),
                      ),
                    ],
                  ),
                  _buildGridItem(Icons.pie_chart, 'Statistics'),
                  _buildGridItem(Icons.settings, ''),
                  _buildGridItem(Icons.help_outline, ''),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticCard(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildGridItem(IconData icon, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 36),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      height: 14,
      width: 14,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          '1',
          style: TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }
}
