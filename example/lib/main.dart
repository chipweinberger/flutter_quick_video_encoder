import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FqveApp();
  }
}

class FqveApp extends StatefulWidget {
  @override
  _FqveAppState createState() => _FqveAppState();
}

class _FqveAppState extends State<FqveApp> {
  @override
  void initState() {
    super.initState();
    FlutterQuickVideoEncoder.setLogLevel(LogLevel.verbose);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Flutter Quick Video Encoder'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {},
                child: Text('Setup'),
              ),
              ElevatedButton(
                onPressed: () {},
                child: Text('Append Video Frame'),
              ),
              ElevatedButton(
                onPressed: () {},
                child: Text('Append Audio Samples'),
              ),
              ElevatedButton(
                onPressed: () {},
                child: Text('Finish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
