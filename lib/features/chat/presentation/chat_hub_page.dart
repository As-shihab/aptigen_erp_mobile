import 'package:flutter/material.dart';
import '../../../shared/widgets/aptigen_app_bar.dart';
import 'direct_messages_page.dart';
import 'groups_page.dart';
import 'schedule_page.dart';

class ChatHubPage extends StatefulWidget {
  const ChatHubPage({super.key});

  @override
  State<ChatHubPage> createState() => _ChatHubPageState();
}

class _ChatHubPageState extends State<ChatHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AptigenAppBar(
        title: 'Chat',
        showBack: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Direct Messages'),
            Tab(text: 'Groups'),
            Tab(text: 'Schedule'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          DirectMessagesPage(),
          GroupsPage(),
          SchedulePage(),
        ],
      ),
    );
  }
}
