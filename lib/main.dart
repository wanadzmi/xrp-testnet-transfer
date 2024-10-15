import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ripple_transfer/xrp/xrp.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XRP Wallet',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WalletPage(),
    );
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  WalletPageState createState() => WalletPageState();
}

class WalletPageState extends State<WalletPage> {
  final String senderMnemonic =
      'spin pond apart swear axis address play real floor ripple category ski jelly balance rice';
  final String receiverMnemonic =
      'mean illness wing trophy dignity betray dance electric grunt jelly invest agent certain pulse matter';

  String senderAddress = '';
  String receiverAddress = '';
  String transactionHash = '';
  String senderBalance = 'Fetching...';
  String transactionFee = 'Calculating...';

  final TextEditingController amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initializeWallet();
  }

  Future<void> initializeWallet() async {
    XRPAccount sender = XRP.fromMnemonic(senderMnemonic);
    XRPAccount receiver = XRP.fromMnemonic(receiverMnemonic);

    setState(() {
      senderAddress = sender.address;
      receiverAddress = receiver.address;
    });

    fetchBalance(sender.address);
    await calculateTransactionFee();
  }

  Future<void> fetchBalance(String address) async {
    int drops = await XRP.getBalance(address, XRPCluster.testNet);
    setState(() {
      senderBalance = '${dropsToXrp(drops)} XRP ($drops drops)';
    });
  }

  double dropsToXrp(int drops) => drops / 1000000;

  Future<void> calculateTransactionFee() async {
    try {
      final fee = await getDynamicFee();
      setState(() {
        transactionFee = '${dropsToXrp(fee)} XRP ($fee drops)';
      });
      print('Calculated Dynamic Fee: $fee drops');
    } catch (e) {
      setState(() {
        transactionFee = 'Error calculating fee';
      });
      print('Error calculating dynamic fee: $e');
    }
  }

  Future<int> getDynamicFee() async {
    const url = 'https://s1.ripple.com:51234'; // XRPL public server
    const body = {
      "method": "fee",
      "params": [{}]
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final feeDrops = int.parse(data['result']['drops']['minimum_fee']);
      print('Fetched Fee from XRPL: $feeDrops drops');
      return feeDrops;
    } else {
      print('Failed to fetch dynamic fee: ${response.body}');
      return 12; // Default fallback fee (12 drops)
    }
  }

  Future<void> transferXrp() async {
    double amountXrp = double.tryParse(amountController.text) ?? 0.0;
    if (amountXrp <= 0) {
      showError('Invalid amount');
      return;
    }

    (amountXrp * 1000000).toInt();
    XRPAccount sender = XRP.fromMnemonic(senderMnemonic);

    try {
      String txHash = await XRP.transferToken(
        amount: amountXrp.toString(),
        to: receiverAddress,
        account: sender,
        networkType: XRPCluster.testNet,
      );

      setState(() {
        transactionHash = txHash;
      });

      fetchBalance(sender.address); // Update balance after transfer
      showSuccess('Transaction successful!\nHash: $txHash');
    } catch (e) {
      showError('Transaction failed: $e');
    }
  }

  void showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XRP Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sender Address:',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(senderAddress),
            const SizedBox(height: 16),
            Text('Receiver Address:',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(receiverAddress),
            const SizedBox(height: 16),
            Text('Sender Balance: $senderBalance'),
            const SizedBox(height: 16),
            Text('Transaction Fee: $transactionFee'),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount to Transfer (in XRP)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: transferXrp,
              child: const Text('Transfer XRP'),
            ),
            const SizedBox(height: 16),
            if (transactionHash.isNotEmpty)
              SelectableText('Transaction Hash: $transactionHash'),
          ],
        ),
      ),
    );
  }
}
