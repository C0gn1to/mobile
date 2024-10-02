import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saturn/ui/tiles.dart';

import '../translations.i18n.dart';
import '../ui/elements.dart';
import '../api/clubs.dart';
import '../api/definitions.dart';
import 'package:get_it/get_it.dart';

  // Private internal list to hold info
  final List<ClubUser> _listeners = [];
  final List<Track> _songreq = [];
  final List<ClubMSG> _chatMessages = [];
  ClubRoom clubRoom = ClubRoom();
  BuildContext realcon2 = 0 as BuildContext;
  final SocketManagement socketManagement = GetIt.I<SocketManagement>();

class ClubsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onRefresh;
  ClubsAppBar({super.key, required this.onRefresh});
  final TextEditingController titleController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  Size get preferredSize => AppBar().preferredSize;

  @override
  Widget build(BuildContext context) {
    return FreezerAppBar(
      'Clubs'.i18n,
      actions: <Widget>[
        IconButton(
          icon: Icon(
            Icons.refresh,
            semanticLabel: 'Reload'.i18n,
          ),
          onPressed: onRefresh,
        ),
        IconButton(
          icon: Icon(
            Icons.add,
            semanticLabel: 'Make a Club'.i18n,
          ),
          onPressed: () {
            final realcontext = context;
            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text('Create Club'.i18n),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Name'.i18n,
                          floatingLabelStyle: TextStyle(color: Theme.of(context).primaryColor),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Theme.of(context).primaryColor),
                          ),
                        ),
                        cursorColor: Theme.of(context).primaryColor,
                      ),
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password'.i18n,
                          floatingLabelStyle: TextStyle(color: Theme.of(context).primaryColor),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Theme.of(context).primaryColor),
                          ),
                        ),
                        cursorColor: Theme.of(context).primaryColor,
                        obscureText: true,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      style: ButtonStyle(
                        overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
                      ),
                      child: Text('Cancel'.i18n),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      style: ButtonStyle(
                        overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
                      ),
                      child: Text('Create'.i18n),
                      onPressed: () async {
                        final title = titleController.text;
                        final password = passwordController.text;

                        if (title.length < 3 || password.length < 3) {
                            titleController.clear();
                            passwordController.clear();
                          // Show an error message
                          _showErrorDialog(context, 'Club Name and Password must be at least 3 characters long.'.i18n);
                          return;
                        }

                        _showLoadingDialog(context); // Show loading dialog

                        try {
                          final clubsAPI = ClubsAPI(baseUrl: 'https://clubs.saturn.kim');
                          final createres = await clubsAPI.createClub(title, password);
                          final resdatadecode = jsonDecode(createres.body);
                          ClubRoom clubRoom = ClubRoom();
                          await socketManagement.connect();
                          final join = await socketManagement.joinClub(resdatadecode['id'], resdatadecode['password']);

                          Navigator.of(context).pop(); // Dismiss loading dialog

                          if (join != null && join.isNotEmpty) {
                            titleController.clear();
                            passwordController.clear();
                            _showErrorDialog(context, join);
                            return; // Prevent navigation if there's an error
                          }

                            titleController.clear();
                            passwordController.clear();
                          if (context.mounted) Navigator.of(context).pop();
                          final response = clubRoom.getJoinResponse();
                          print('Response: ' + response);
                          Navigator.of(realcontext).pushReplacement(MaterialPageRoute(
                              builder: (realcontext) => const InClubScreen()));
                        } catch (e) {
                          Navigator.of(context).pop(); // Dismiss loading dialog
                            titleController.clear();
                            passwordController.clear();
                          _showErrorDialog(context, 'Error: $e');
                        }
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  _ClubsScreenState createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  final TextEditingController passwordController = TextEditingController();
  List<dynamic> listofclubs = [];
  bool isLoading = true; // Add loading state

  @override
  void initState() {
    super.initState();
    fetchClubList();
  }

  Future<void> fetchClubList() async {
    ClubsAPI clubsAPI = ClubsAPI(baseUrl: 'https://clubs.saturn.kim:443');
    var response = await clubsAPI.clubList();

    if (response.statusCode == 200) {
      setState(() {
        listofclubs = jsonDecode(response.body);
        isLoading = false; // Set loading to false
      });
    } else {
      setState(() {
        isLoading = false; // Set loading to false on error
      });
      print('Failed to load clubs');
    }
  }

  void _onRefresh() {
    setState(() {
      isLoading = true; // Set loading to true on refresh
    });
    fetchClubList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ClubsAppBar(onRefresh: _onRefresh),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor,)) // Show loading indicator
          : listofclubs.isEmpty
              ? Center(child: Text('No clubs available.'.i18n)) // Show "No clubs available" message
              : ListView(
                  children: List.generate(
                    listofclubs.length,
                    (i) {
                      var club = listofclubs[i];
                      bool hasPassword = club['password'] == true;

                      return ListTile(
                        leading: Icon(
                          hasPassword ? Icons.lock : Icons.public,
                        ),
                        title: Text(club['title']?.toString() ?? 'No Title'),
                        subtitle: Row(
                          children: [
                            const Icon(Icons.group),
                            const SizedBox(width: 8),
                            Text(club['users'].toString()),
                          ],
                        ),
                        onTap: () {
                          final realcontext = context;
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: Text('Club is password protected.'.i18n),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    TextField(
                                      controller: passwordController,
                                      decoration: InputDecoration(
                                        labelText: 'Password'.i18n,
                                        floatingLabelStyle: TextStyle(color: Theme.of(context).primaryColor),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(color: Theme.of(context).primaryColor),
                                        ),
                                      ),
                                      cursorColor: Theme.of(context).primaryColor,
                                      obscureText: true,
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    style: ButtonStyle(
                                      overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
                                    ),
                                    child: Text('Cancel'.i18n),
                                    onPressed: () {
                                      if (context.mounted) Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    style: ButtonStyle(
                                      overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
                                    ),
                                    child: Text('Join'.i18n),
                                    onPressed: () async {
                                      final password = passwordController.text;

                                      if (password.length < 3) {
                                        _showErrorDialog(context, 'Password must be at least 3 characters long.'.i18n);
                                        return;
                                      }

                                      _showLoadingDialog(context); // Show loading dialog

                                      try {
                                        await socketManagement.connect();
                                        final join = await socketManagement.joinClub(club['id'], password);

                                        Navigator.of(context).pop(); // Dismiss loading dialog

                                        if (join != null) {
                                          passwordController.clear();
                                          _showErrorDialog(context, join);
                                          return;
                                        }

                                        if (context.mounted) Navigator.of(context).pop();
                                        passwordController.clear();
                                        Navigator.of(realcontext).pushReplacement(MaterialPageRoute(
                                          builder: (realcontext) => const InClubScreen()));
                                      } catch (e) {
                                        Navigator.of(context).pop();
                                        passwordController.clear(); // Dismiss loading dialog
                                        _showErrorDialog(context, '$e');
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

void _showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Error'.i18n),
        content: Text(message),
        actions: [
          TextButton(
            style: ButtonStyle(
              overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
            ),
            child: Text('OK'.i18n),
            onPressed: () {
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

void _showLoadingDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false, // Prevent closing the dialog
    builder: (context) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Theme.of(context).primaryColor,),
              const SizedBox(width: 16),
              Text('Loading...'.i18n),
            ],
          ),
        ),
      );
    },
  );
}

class InClubAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  final Widget? bottom;
  //Should be specified if bottom is specified
  final double height;

  const InClubAppBar(this.title, {super.key, this.actions = const [], this.bottom, this.height = 56.0});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(primaryColor: (Theme.of(context).brightness == Brightness.light) ? Colors.white : Colors.black),
      child: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            final realcontext = context;
              showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Are you Sure?'.i18n),
      content: Text('Do you want to leave this club.'.i18n),
      actions: [
        TextButton(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
          ),
          child: Text('No'.i18n),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
          ),
          child: Text('Yes'.i18n),
          onPressed: () async {
            socketManagement.disconnect();
            Navigator.of(context).pop();
            Navigator.of(realcontext).pushReplacement(MaterialPageRoute(
              builder: (realcontext) => const ClubsScreen()));
          }
        ),
      ],
    ),
  );
          },
        ),
        systemOverlayStyle: SystemUiOverlayStyle(statusBarBrightness: Theme.of(context).brightness),
        elevation: 0.0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: (Theme.of(context).brightness == Brightness.light) ? Colors.black : Colors.white,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: actions,
        bottom: bottom as PreferredSizeWidget?,
      ),
    );
  }
}

class InClubScreen extends StatefulWidget {
  const InClubScreen({super.key});

  @override
  _InClubScreenState createState() => _InClubScreenState();
}

class _InClubScreenState extends State<InClubScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Example chat messages list using ClubMSG objects

  @override
  void initState() {
    super.initState();
    GetIt.I<dataMGMT>().onListenersChanged = refreshListeners;
    GetIt.I<dataMGMT>().ondisconnect = serversidedisconnect;
    GetIt.I<dataMGMT>().scroll = _scrollToBottom;
  }

  void refreshListeners() {
    setState(() {});
    print('refcall');
  }

  void serversidedisconnect() {
    datamgmt.clear();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (realcontext) => const ClubsScreen()),
    );
  }

  // Method to scroll to the bottom
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: InClubAppBar(
          'Club'.i18n,
          bottom: TabBar(
            dividerColor: Colors.transparent,
            indicatorColor: Theme.of(context).primaryColor,
            overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {if (states.contains(WidgetState.pressed)) {return Theme.of(context).primaryColor.withOpacity(0.3);}return null;}),
            labelColor: Theme.of(context).primaryColor,
            tabs: [
              const Tab(icon: Icon(Icons.people, semanticLabel: 'Listeners')),
              const Tab(icon: Icon(Icons.queue_music, semanticLabel: 'Music Requests')),
              const Tab(icon: Icon(Icons.chat, semanticLabel: 'Chat')),
            ],
          ),
          height: 100.0,
        ),
        body: TabBarView(
          children: [
            // Listeners
            ListView(
              children: List.generate(
                _listeners.length,
                (index) {
                  final user = _listeners[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(user.picture),
                    ),
                    title: Text(
                      user.username,
                      style: TextStyle(
                        color: user.admin
                            ? Theme.of(context).primaryColor
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    subtitle: user.admin ? const Text('Admin') : null,
                    trailing: clubRoom.ifhost() 
                        ? !user.admin 
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  socketManagement.ban(user.sid);
                                },
                              ) 
                            : null 
                        : null,
                  );
                },
              ),
            ),
            // Music Requests
            ListView(
              children: List.generate(
                _songreq.length,
                (index) {
                  Track t = _songreq[index];
                  return TrackTile(
                    t,
                    trailing: clubRoom.ifhost() 
                        ? Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  socketManagement.removeRequest(t.id.toString());
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.playlist_play),
                                onPressed: () {
                                  datamgmt.requestnext(t);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.playlist_add),
                                onPressed: () {
                                  datamgmt.requestplay(t);
                                },
                              ),
                            ],
                          ) 
                        : null,
                  );
                },
              ),
            ),
            // Chat Tab
            Column(
              children: [
                // Chat message list
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final message = _chatMessages[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: NetworkImage(message.photo),
                        ),
                        title: Text(
                          message.profile, // Replace with actual profile name
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        subtitle: Text(
                          message.content,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    },
                  ),
                ),
                // Input field and Send button
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          cursorColor: Theme.of(context).primaryColor,
                          decoration: InputDecoration(
                            hintText: 'Enter message'.i18n,
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                            enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Theme.of(context).primaryColor)),
                          ),
                        ),
                      ),
                       const SizedBox(width: 8.0),
                      ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor: WidgetStatePropertyAll<Color>(Theme.of(context).primaryColor),
                      ),
                      onPressed: () {
                        final String message = _messageController.text.trim();
                        // Check if the message is empty, return if so
                        if (message.isEmpty) {
                          return;
                        }
                        // If not empty, send the message
                        socketManagement.sendMessage(message);
                        _messageController.clear(); // Clear the input after sending
                      },
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class dataMGMT {
  void Function()? onListenersChanged;
  void Function()? ondisconnect;
  void Function()? scroll;
  static dataMGMT get instance => GetIt.I<dataMGMT>();
  

  // Function to get the list of listeners
  List<ClubUser> getListenerList() {
    return List.unmodifiable(_listeners); // Return an unmodifiable copy to prevent external modification
  }

  // Function to clear all listeners
  void clear() {
    _listeners.clear();
    _songreq.clear();
    _chatMessages.clear();
  }

// Function to add initial data (bulk add)
void addInitialData(dynamic initialListeners) {
  if (initialListeners is List<dynamic>) {
    // Cast each item in the list to a Map<String, dynamic>
    List<Map<String, dynamic>> listenersList = initialListeners
        .where((item) => item is Map<String, dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();

    // Convert each Map<String, dynamic> to a ClubUser instance
    List<ClubUser> users = listenersList.map((json) {
      return ClubUser.fromJson(json);
    }).toList();

    // Add all the mapped ClubUser instances to _listeners
    _listeners.addAll(users);
  } else {
    // Handle or log unexpected data types
    print("Expected List<dynamic>, but got: ${initialListeners.runtimeType}");
  }
}

  // Function to add a single listener
  void addListener(ClubUser newUser) {
    _listeners.add(newUser);
    onListenersChanged?.call(); 
  }

  // Function to remove a listener
  void removeListener(ClubUser userToRemove) {
    _listeners.removeWhere((user) => user.sid == userToRemove.sid);
    onListenersChanged?.call(); 
  }

      // Function to add a single listener
  void addmsg(ClubMSG msg) {
    _chatMessages.add(msg);
    onListenersChanged?.call(); 
    scroll?.call();
  }

    // Function to add a single listener
  void addreq(Track trackToAdd) {
    _songreq.add(trackToAdd);
    onListenersChanged?.call(); 
  }

  // Function to remove a listener
  void removereq(String trackid) {
    _songreq.removeWhere((Track) => Track.id == trackid);
    socketManagement.removeRequest(trackid);
    onListenersChanged?.call(); 
  }

  // Function to add a single listener
  void requestnext(Track next) {
    socketManagement.addQueue(next, true);
    datamgmt.removereq(next.id.toString());
    onListenersChanged?.call(); 
  }

  // Function to add a single listener
  void requestplay(Track play) {
    socketManagement.addQueue(play, false);
    datamgmt.removereq(play.id.toString());
    onListenersChanged?.call(); 
  }

  void addInitalTrackIds(dynamic initialTracks) {
  if (initialTracks is List<Track>) {
    // Cast each item in the list to a Map<String, dynamic>
    List<Map<String, dynamic>> listenersList = initialTracks
        .where((item) => item is Map<String, dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();

    // Convert each Map<String, dynamic> to a ClubUser instance
    List<ClubUser> users = listenersList.map((json) {
      return ClubUser.fromJson(json);
    }).toList();

    // Add all the mapped ClubUser instances to _listeners
    _listeners.addAll(users);
    print('Added initial data: ' + _listeners.toString());
  } else {
    // Handle or log unexpected data types
  }
}
}