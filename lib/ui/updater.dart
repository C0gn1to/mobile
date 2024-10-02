import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/cache.dart';
import '../api/download.dart';
import '../translations.i18n.dart';
import '../ui/elements.dart';
import '../ui/error.dart';
import '../utils/version.dart';

class UpdaterScreen extends StatefulWidget { 
  @override
  _UpdaterScreenState createState() => _UpdaterScreenState();
}

class _UpdaterScreenState extends State<UpdaterScreen> {

  bool _loading = true;
  bool _error = false;  freezerVersions? _versions;
  String? _current;
  String? _arch;
  double _progress = 0.0;
  bool _buttonEnabled = true;

  Future<void> _checkInstallPackagesPermission() async {
      if (await Permission.requestInstallPackages.isDenied) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw Exception('Permission to install packages not granted');
      }
    }
  }

  Future _load() async {
    //Load current version
    PackageInfo info = await PackageInfo.fromPlatform();
    setState(() => _current = info.version);

    //Get architecture
    _arch = await DownloadManager.platform.invokeMethod("arch");
    if (_arch == 'armv8l')
      _arch = 'arm32';

    //Load from website
    try {
      freezerVersions versions = await freezerVersions.fetch();
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (e, st) {
      print(e.toString() + st.toString());
      _error = true;
      _loading = false;
    }
  }

  freezerDownload? get _versionDownload {
    return _versions?.versions[0].downloads.firstWhere((d) => d.version.toLowerCase().contains(_arch!.toLowerCase()));
  }

  Future _download() async {
    await _checkInstallPackagesPermission(); // Check and request permission if needed
    String? url = _versionDownload?.directUrl;
    //Start request
    http.Client client = new http.Client();
    http.StreamedResponse res = await client.send(http.Request('GET', Uri.parse(url.toString())));
    int? size = res.contentLength;
    //Open file
    String path = p.join((await getExternalStorageDirectory())!.path, 'update.apk');
    File file = File(path);
    IOSink fileSink = file.openWrite();
    //Update progress
    Future.doWhile(() async {
      int received = await file.length();
      setState(() => _progress = received / size!.toInt());
      return received != size;
    });
    //Pipe
    await res.stream.pipe(fileSink);
    fileSink.close();
    debugPrint(path); 
    OpenFilex.open(path);

    setState(() => _buttonEnabled = true);
  }

  @override
  void initState() {
    _load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FreezerAppBar('Updates'.i18n),
      body: ListView(
        children: [

          if (_error)
            ErrorScreen(),

          if (_loading)
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator(color: Theme.of(context).primaryColor,)],
              ),
            ),

          if (!_error && !_loading && Version.parse((_versions?.latest.toString() ?? '0.0.0')) > Version.parse(_current!))
            Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'You are running latest version!'.i18n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26.0
                  )
                ),
              )
            ),

          if (!_error && !_loading && Version.parse((_versions?.latest.toString() ?? '0.0.0')) <= Version.parse(_current!))
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'New update available!'.i18n + ' ' + _versions!.latest.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold
                    ),
                  ),
                ),
                Text(
                  'Current version: ' + _current!,
                  style: TextStyle(
                    fontSize: 14.0,
                    fontStyle: FontStyle.italic
                  ),
                ),
                Container(height: 8.0),
                FreezerDivider(),
                Container(height: 8.0),
                Text(
                  'Changelog',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    _versions!.versions[0].changelog,
                    style: TextStyle(fontSize: 16.0),
                  ),
                ),
                FreezerDivider(),
                Container(height: 8.0),
                //Available download
                if (_versionDownload != null)
                  Column(children: [
                    ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor: MaterialStatePropertyAll<Color>(Theme.of(context).primaryColor),
                      ),
                      child: Text('Download'.i18n + ' (${_versionDownload!.version})'),
                      onPressed: _buttonEnabled ? () {
                        setState(() => _buttonEnabled = false);
                        _download();
                      }:null
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.0),
                      child: LinearProgressIndicator(value: _progress, color: Theme.of(context).primaryColor,),
                    )
                  ]),
                //Unsupported arch
                if (_versionDownload == null)
                  Text(
                    'Unsupported platform!'.i18n + ' $_arch',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16.0),
                  )
              ],
            )
        ],
      )
    );
  }
}

class freezerVersions {
  String latest;
  List<freezerVersion> versions;

  freezerVersions({required this.latest, required this.versions});

  factory freezerVersions.fromJson(Map data) => freezerVersions(
    latest: data['android']['latest'],
    versions: data['android']['versions'].map<freezerVersion>((v) => freezerVersion.fromJson(v)).toList()
  );

  //Fetch from website API
  static Future<freezerVersions> fetch() async {
    http.Response response = await http.get(Uri.parse('https://saturn.kim/api/versions'));
    return freezerVersions.fromJson(jsonDecode(response.body));
  }

  static Future<void> checkUpdate() async {
    // Check every 24 hours
    // int updateDelay = 86400000; // 24 hours in milliseconds
    // if ((DateTime.now().millisecondsSinceEpoch - (cache.lastUpdateCheck ?? 0)) < updateDelay) return;

    // cache.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
    // await cache.save();

    try { 
      
    freezerVersions versions = await freezerVersions.fetch();

    //Load current version
    PackageInfo info = await PackageInfo.fromPlatform();
    if (Version.parse(versions.latest) <= Version.parse(info.version)) return;

      

      //Get architecture
      String _arch = await DownloadManager.platform.invokeMethod("arch");
      if (_arch == 'armv8l') _arch = 'arm32';
      
      //Check compatible architecture
      var compatibleVersion =
          versions.versions[0].downloads.firstWhereOrNull((d) => d.version.toLowerCase().contains(_arch.toLowerCase()));

      if (compatibleVersion == null) return;

      // Show notification
      FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings androidInitializationSettings = AndroidInitializationSettings('drawable/ic_logo');
      final InitializationSettings initializationSettings = InitializationSettings(android: androidInitializationSettings, iOS: null);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      AndroidNotificationDetails androidNotificationDetails = const AndroidNotificationDetails(
        'saturnupdates', // Channel ID
        'Saturn Updates', // Channel Name
        importance: Importance.high,
        priority: Priority.high,
      );

      NotificationDetails notificationDetails = NotificationDetails(android: androidNotificationDetails, iOS: null);

      await flutterLocalNotificationsPlugin.show(
        0, // Notification ID
        'New update available!'.i18n, // Notification title
        'Update to latest version in the settings.'.i18n, // Notification body
        notificationDetails,
      );

    } catch (e) {
      Logger.root.severe('Error checking for updates', e);
    }
  }
}

class freezerVersion {
  String version;
  String changelog;
  List<freezerDownload> downloads;

  freezerVersion({required this.version, required this.changelog, required this.downloads});

  factory freezerVersion.fromJson(Map data) => freezerVersion(
    version: data['version'],
    changelog: data['changelog'],
    downloads: data['downloads'].map<freezerDownload>((d) => freezerDownload.fromJson(d)).toList()
  );
}

class freezerDownload {
  String version;
  String directUrl;

  freezerDownload({required this.version, required this.directUrl});

  factory freezerDownload.fromJson(Map data) => freezerDownload(
    version: data['version'],
    directUrl: data['links'].first['url']
  );
}