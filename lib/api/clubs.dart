import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:get_it/get_it.dart';

import '../api/deezer.dart';
import '../api/definitions.dart';
import '../service/audio_service.dart';
import '../translations.i18n.dart';
import '../ui/clubs_screen.dart';

bool userInClub = false;
bool allowcontrols = true;
bool socketConnected = false;
final dataMGMT datamgmt = GetIt.I<dataMGMT>();
final SocketManagement socketManagement = GetIt.I<SocketManagement>();

class ClubsAPI {
  final String baseUrl;
  final http.Client httpClient;

  ClubsAPI({required this.baseUrl}) : httpClient = http.Client();

  Future<http.Response> clubList() async {
    final response = await httpClient.get(Uri.parse('$baseUrl/rooms'));
    return response;
  }

  Future<String> getQueueFilePath() async {
    Directory? dir = await getExternalStorageDirectory();
    if (dir == null) {
      throw Exception('External storage directory is not available');
    }
    return p.join(dir.path, 'playback.json');
  }

  Future<http.Response> createClub(String title, String password) async {
    final url = Uri.parse('$baseUrl/room');
    final queueFilePath = await getQueueFilePath();
    final file = File(queueFilePath);
    final bytes = await file.readAsBytes();
    final jsonData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    final queue = jsonData['queue'] as List;
    final queueIndex = jsonData['index'];

    final trackIds = queue.map((track) => track['id'].toString()).toList();

    final Map<String, dynamic> requestBody = {
      'title': title,
      'queue': trackIds,
      'queueIndex': queueIndex,
      'password': password,
    };

    final response = await httpClient.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return response;
    } else {
      throw Exception('Failed to create room');
    }
  }
}

class ClubRoom {
  String _joinResponse = '';

  String getJoinResponse() {
    return _joinResponse;
  }

  Future<void> processJoinResponse(Map<String, dynamic> data, String sid) async {
    _joinResponse = jsonEncode(data);
    final List<dynamic> queueDynamicList = data['queue'] as List<dynamic>;
    final List<String> queue = queueDynamicList.map((item) => item.toString()).toList();
    final tracklist = await _convertJsonToTracks(queue);
    final int queueIndexNumber = data['queueIndex'];
    final queueIndex = queue[queueIndexNumber];
    dynamic positionDynamic = data['position'];
    bool playing = data['playing'];
    int positionTime = data['positionTime'];
    datamgmt.addInitialData(data['users'] as List<dynamic>);
    final List<dynamic> reqQueueDyanmic = data['requests'] as List<dynamic>;
    final List<String> reqQueue = reqQueueDyanmic.map((item) => item.toString()).toList();
    final reqtracks = await _convertJsonToTracks(reqQueue);
    datamgmt.addInitalTrackIds(reqtracks);
    int pos;
    if (positionDynamic is double) {
      pos = positionDynamic.toInt(); // Convert double to int
    } else if (positionDynamic is int) {
      pos = positionDynamic;
    } else {
      throw Exception('Unexpected type for position: ${positionDynamic.runtimeType}');
    }
    GetIt.I<AudioPlayerHandler>().LoadClubQueue(
      tracklist,
      queueIndex,
      QueueSource(
        text: 'Club'.i18n,
        source: 'club',
        id: 'club',
      ),
      playing,
      pos,
      positionTime,
    );
    final room = jsonDecode(_joinResponse);
    var user = room?['users']?.firstWhere((u) => u['sid'] == sid, orElse: () => null);
    // return user != null && user['admin'] == true;
    if (user['admin'] == true) {
      allowcontrols = true;
    } else {
      allowcontrols = false;
    }
  }

  Future<List<Track>> _convertJsonToTracks(List<String> trackIds) async {
    try {
      final apicall = await deezerAPI.callGwApi('song.getlistdata', params: {'sng_ids': trackIds});
      final Map<String, dynamic> decodedJson = apicall;
      final List<dynamic> trackDataList = decodedJson['results']['data'];
      final List<Track> trackList = trackDataList.map((trackData) {
        return Track.fromPrivateJson(trackData);
      }).toList();
      return trackList;
    } catch (e) {
      print('Error occurred: $e');
      return [];
    }
  }

  bool ifhost() {
    if (userInClub) {
      return allowcontrols;
    } else {
      return true;
    }
  }
    bool ifclub() {
      return userInClub;
  }
}

class SocketManagement {
  late final io.Socket socket;
  final String address;
  final ClubRoom clubRoom;

  SocketManagement({required this.address, required this.clubRoom}) {
    socket = io.io(address, io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());

    socket.onConnect((_) {
      print('Connected to $address');
    });

    socket.onDisconnect((_) {
      print('Disconnected from $address');
      datamgmt.ondisconnect;
      userInClub = false;
    });

    socket.onConnectError((error) {
      print('Connection Error: $error');
      datamgmt.ondisconnect;
      userInClub = false;
    });

    socket.onError((error) {
      print('General Error: $error');
      datamgmt.ondisconnect;
      userInClub = false;
    });

    socket.on('join', (data) async {
      print('Joined room: $data');
    });

    socket.on('joined', (data) {
      var usr = ClubUser.fromJson(data);
      datamgmt.addListener(usr);
      print('Person joined: $usr');
    });

    socket.on('left', (data) {
      var usr = ClubUser.fromJson(data);
      datamgmt.removeListener(usr);
      print('Person left: $usr');
    });

    socket.on('message', (ddata) {
  try {
    print('Message: $ddata');
    
    // Check if ddata is a List
    if (ddata is List) {
      // Access the first item in the list
      var data = ddata[0];
      
      // Ensure that the data is a Map
      if (data is Map<String, dynamic>) {
        var profile = data['profile'];
        var photo = data['photo'];
        var content = data['content'];
        
        // Create ClubMSG instance with proper type casting
        var msg = ClubMSG(
          profile: profile as String? ?? 'Unknown profile', 
          photo: photo as String? ?? 'Unknown photo',
          content: content as String? ?? 'No content'
        );
        
        // Add message to datamgmt
        datamgmt.addmsg(msg);
      } else {
        print('First item is not a valid map');
      }
    } else {
      print('ddata is not a List');
    }
  } catch (e) {
    print('Error processing message: $e');
  }
});

    socket.on('request', (data) async {
      print(data);
      final res = await deezerAPI.callGwApi('deezer.pageTrack', params: {'sng_id': data['id']['SNG_ID']});
      print(res);
      final Map<String, dynamic> reqtrack = res['results']['DATA'];
      datamgmt.addreq(Track.fromPrivateJson(reqtrack));
      print('Add Request: $data');
    });

    socket.on('removeRequest', (data) async {
      datamgmt.removereq(data);
      print('Remove Request: $data');
    });

    socket.on('addQueue', (data) async {
      print('addqueue');
      var trackId = data['track'];
      var next = data['next'];
      List<String> trackIds = [trackId];
      List<Track?> trackList = await clubRoom._convertJsonToTracks(trackIds);
      Track? track = trackList.isNotEmpty ? trackList[0] : null;
      if (track != null) {
        if (next == false) {
          await GetIt.I<AudioPlayerHandler>().addQueueItem(track.toMediaItem());
        } else {
          await GetIt.I<AudioPlayerHandler>().insertQueueItem(-1, track.toMediaItem());
        }
      } else {
        print('Error: not a valid track');
      }
    });

    socket.on('sync', (data) async {
      var playing = data['playing'];
      var position = data['position'];
      var timestamp = data['timestamp'];
      dynamic positionDynamic = data['position'];
      if (positionDynamic is double) {
        position = positionDynamic.toInt();
      } else if (positionDynamic is int) {
        position = positionDynamic;
      } else {
        throw Exception('Unexpected type for position: ${positionDynamic.runtimeType}');
      }
      await GetIt.I<AudioPlayerHandler>().ClubSync(playing, position, timestamp);
      print('sync');
    });

    socket.on('index', (data) async {
      var index = data['index'];
      await GetIt.I<AudioPlayerHandler>().skipToQueueItem(index);
    });
  }

  Future<void> connect() async {
    print('Attempting to connect to $address');

    // Create a Completer for the new connection attempt
    final Completer<void> completer = Completer<void>();

    // Flag to track if the completer has been completed
    bool isCompleted = false;

    // Callback for successful connection
    void onConnectCallback(_) {
      if (!isCompleted) {
        completer.complete(); // Complete the Future
        isCompleted = true; // Mark as completed
      }
    }

    // Callback for connection errors
    void onConnectErrorCallback(error) {
      if (!isCompleted) {
        completer.completeError(error); // Complete the Future with an error
        isCompleted = true; // Mark as completed
      }
    }

    // Callback for disconnection
    void onDisconnectCallback(_) {
      if (!isCompleted) {
        completer.completeError('Disconnected unexpectedly'); // Handle unexpected disconnection
        isCompleted = true; // Mark as completed
      }
    }

    // Add listeners for socket events
    socket.onConnect(onConnectCallback);
    socket.onConnectError(onConnectErrorCallback);
    socket.onDisconnect(onDisconnectCallback);

    // Initiate the socket connection
    socket.connect();

    // Return the Future from the Completer
    return completer.future;
  }

  void disconnect() {
    print('Disconnecting from $address');
    socket.disconnect();
    userInClub = false;
    datamgmt.clear();
  }

sync() async {
  if (clubRoom.ifclub()) return;
  bool playing = await GetIt.I<AudioPlayerHandler>().playing();
  Duration position = await GetIt.I<AudioPlayerHandler>().position();
  bool admin = clubRoom.ifhost();
  socket.emit('sync', {
    'playing': playing,
    'position': position.inMilliseconds, // Convert Duration to milliseconds
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'admin': admin
  });
}

  addQueue(track, bool next) {
        print('addqueue emitted for track:' + track.id.toString() + next.toString());
        if (!clubRoom.ifclub()) return();
        if (!clubRoom.ifhost()) return();
        //Emit
        socket.emit('addQueue', {
            'track': track.id,
            'next': next,
        });
    }

  addQueueID(String id, bool next) {
        print('addqueue emitted for track:' + id.toString() + next.toString());
        if (!clubRoom.ifclub()) return();
        if (!clubRoom.ifhost()) return();
        //Emit
        socket.emit('addQueue', {
            'track': id,
            'next': next,
        });
    }

    playIndex(int i) async {
      if (clubRoom.ifclub()) return;
      if (clubRoom.ifhost()) return;
      socket.emit('index', i);
      bool isPlaying = await GetIt.I<AudioPlayerHandler>().playing();
      if (isPlaying) {
        await sync();
      }
    }

    //Callback
    togglePlayback(playing) async {
        Duration position = await GetIt.I<AudioPlayerHandler>().position();
        if (!clubRoom.ifclub()) return;
        //Send sync signal
        socket.emit('sync', {
            'playing': playing,
            'position': position.inMilliseconds,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'admin': clubRoom.ifclub()
        });
    }

    trackEnd(int queuenumber, int queuelength) async {
      int realqueuenumber = queuenumber - 1;
      //End of queue
      if ((queuelength - 1) == realqueuenumber) {
          togglePlayback(false);
          return;
      }
      if (!clubRoom.ifhost()) return;
      //Next track
      await playIndex(realqueuenumber + 1);
      await Future.delayed(const Duration(seconds: 5));
      await playIndex(realqueuenumber + 1);
      await rundesktopcompat();
      await togglePlayback(true);
  }

  rundesktopcompat() async {
    await sync();
    await togglePlayback(true);
  }


    //Ban user
    ban(id) {
        socket.emit('ban', id);
    }

    //Send message to chat
    sendMessage(content) async {
        final usrdata = await deezerAPI.callGwApi('deezer.getUserData', params: {});
        DeezerImage photo = DeezerImage(usrdata['results']['USER']['USER_PICTURE'], type: 'user');
        String profile = usrdata['results']['USER']['BLOG_NAME'];
        socket.emit('message', {
          'content': content, 
          'profile': profile, 
          'photo':photo.full});
    }

  Future songRequest(String id) async {
    final res = await deezerAPI.callGwApi('deezer.pageTrack',  params: {'sng_id': id});
        socket.emit('request', {
          'id': res['results']['DATA'],
        });
  }

  //Remove request
  Future removeRequest(String id) async {
    print('rmrequest emitted for track:' + id);
    if (!clubRoom.ifhost()) return;
    datamgmt.removereq(id);
    socket.emit('removeRequest', id.toString());
  }

  Future<String?> joinClub(String id, String password) async {
    if (socket.connected) {
      try {
        final usrdata = await deezerAPI.callGwApi('deezer.getUserData', params: {});
        DeezerImage image = DeezerImage(usrdata['results']['USER']['USER_PICTURE'], type: 'user');
        Map<String, dynamic> imagejson = image.toJson();

        Completer<void> joinCompleter = Completer<void>();
        Completer<void> errorCompleter = Completer<void>();

        socket.once('join', (data) async {
          await clubRoom.processJoinResponse(data, socket.id.toString());
          joinCompleter.complete();
          userInClub = true;
        });

        socket.once('error', (data) {
          if (!errorCompleter.isCompleted) {
            errorCompleter.completeError(Exception('Error received from server: $data'));
            userInClub = false;
            socket.disconnect();
          }
        });

        socket.emit('join', {
          'room': id,
          'sid': socket.id,
          'id': usrdata['results']['USER']['USER_ID'],
          'name': usrdata['results']['USER']['BLOG_NAME'],
          'photo': imagejson,
          'password': password,
        });

        await Future.any([
          joinCompleter.future,
          errorCompleter.future,
        ]);

        return null;
      } catch (e) {
        userInClub = false;
        return e.toString();
      } finally {
        socket.off('error');
        socket.off('join');
      }
    } else {
      userInClub = false;
      return 'Failed to connect to the server.';
    }
  }
}

class DeezerImage {
  final String hash;
  final String type;
  late final String full;
  late final String thumb;

  DeezerImage(this.hash, {this.type = 'cover'}) {
    full = url(hash, type, 1400);
    thumb = url(hash, type, 264);
  }

  static String url(String hash, String type, [int size = 264]) {
    if (hash.isEmpty) {
      return 'https://e-cdns-images.dzcdn.net/images/$type/${size}x${size}-000000-80-0-0.jpg';
    } else {
      return 'https://e-cdns-images.dzcdn.net/images/$type/$hash/${size}x${size}-000000-80-0-0.jpg';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'type': type,
      'full': full,
      'thumb': thumb,
    };
  }
}