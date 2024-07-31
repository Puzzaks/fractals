import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'generator.dart';

class FractalWidget extends StatefulWidget {
  const FractalWidget({super.key});

  @override
  _FractalWidgetState createState() => _FractalWidgetState();
}

class _FractalWidgetState extends State<FractalWidget> {
  late FractalGenerator _fractalGenerator;

  @override
  void initState() {
    SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual, overlays: [
      SystemUiOverlay.top,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
      ),
    );
    super.initState();
    _fractalGenerator = FractalGenerator();
    _fractalGenerator.startReceivingFrames();
  }

  String formatDouble(String stringValue) {
    int lastZero = 0;
    int dotIndex = stringValue.indexOf('.') + 1;
    if (double.parse(stringValue) >= 1) {
      return (double.parse(stringValue).toInt().toString());
    }
    if (double.parse(stringValue) >= 0.1) {
      return (stringValue.substring(0, 3));
    }
    for (int i = dotIndex; i < stringValue.length; i++) {
      if (stringValue[i] == "0") {
        lastZero = i;
      } else {
        break;
      }
    }

    return stringValue.substring(0, dotIndex + lastZero);
  }

  static final _defaultLightColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal);

  static final _defaultDarkColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal, brightness: Brightness.dark);

  @override
  Widget build(BuildContext topContext) {
    _fractalGenerator.canvasHeight = View.of(topContext).physicalSize.height.toInt();
    _fractalGenerator.canvasWidth = View.of(topContext).physicalSize.width.toInt();
    double startOffsetX = _fractalGenerator.offsetX;
    double startOffsetY = _fractalGenerator.offsetY;
    Offset startPoint = Offset.zero;
    double startResScale = 0.0;
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: lightColorScheme ?? _defaultLightColorScheme,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          // floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: topContext,
                isScrollControlled: true,
                enableDrag: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (BuildContext topContext) {
                  return mainSettings(fractalGenerator: _fractalGenerator,);
                },
              );
            },
            child: const Icon(Icons.info_outline_rounded),
          ),
          body: Stack(
            children: [
              StreamBuilder<Uint8List>(
                stream: _fractalGenerator.imageStream,
                builder: (topContext, snapshot) {
                  if(_fractalGenerator.useSysColor){
                    _fractalGenerator.R = Theme.of(topContext).colorScheme.primary.red ~/ 25.5;
                    _fractalGenerator.G = Theme.of(topContext).colorScheme.primary.green ~/ 25.5;
                    _fractalGenerator.B = Theme.of(topContext).colorScheme.primary.blue ~/ 25.5;
                  }
                  if (snapshot.hasData) {
                    return Stack(
                      children: [
                        Image.memory(
                          snapshot.data!,
                          width: MediaQuery.of(topContext).size.width,
                          height: MediaQuery.of(topContext).size.height,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                        SafeArea(
                            child: Column(
                          children: [
                            _fractalGenerator.showTelemetry
                                ? Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                            "Zoomed at ${_fractalGenerator.zoom.toInt()} (${((100 / 5000000000000000000) * _fractalGenerator.zoom) >= 0 ? formatDouble(((100 / 5000000000000000000) * _fractalGenerator.zoom).toStringAsFixed(20)) : ((100 / 5000000000000000000) * _fractalGenerator.zoom).toInt()}%)"),
                                        Text("Offset X: ${_fractalGenerator.offsetX.toStringAsFixed(17)}\nOffset Y: ${_fractalGenerator.offsetY.toStringAsFixed(17)}"),
                                        Text("Iterations:  ${_fractalGenerator.maxIterations}"),
                                        Text((_fractalGenerator.resolutionScale == 1) ? "Rendered in ${_fractalGenerator.lastTime}ms" : "Rendering, ${(100 / _fractalGenerator.lastTime).toStringAsFixed(0)}fps"),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ) : Container()
                          ],
                        ))
                      ],
                    );
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
              GestureDetector(
                onScaleStart: (details) {
                  _fractalGenerator.canvasHeight = View.of(topContext).physicalSize.height.toInt();
                  _fractalGenerator.canvasWidth = View.of(topContext).physicalSize.width.toInt();
                  _fractalGenerator.resolutionScale = 0.075;
                  _fractalGenerator.paused = false;
                  var localTouchPosition = (topContext.findRenderObject() as RenderBox).globalToLocal(details.localFocalPoint);
                  startPoint = (localTouchPosition - Offset(MediaQuery.of(topContext).size.width, MediaQuery.of(topContext).size.height) * 0.5);
                  startOffsetX = _fractalGenerator.offsetX;
                  startOffsetY = _fractalGenerator.offsetY;
                },
                onScaleUpdate: (details) {
                  if (details.scale != 1.0) {
                    if (!(startResScale == details.scale)) {
                      if (details.scale < 1.0) {
                        if (_fractalGenerator.zoom > 300) {
                          _fractalGenerator.zoom -= (0.01 * _fractalGenerator.zoom) / (details.scale * 10);
                        }
                      } else {
                        if ((_fractalGenerator.zoom < 5000000000000000000)) {
                          _fractalGenerator.zoom += (0.01 * _fractalGenerator.zoom) / details.scale;
                        } else {
                          _fractalGenerator.zoom = 5000000000000000000;
                        }
                      }
                    }
                    startResScale = details.scale;
                  }
                  var localTouchPosition = (topContext.findRenderObject() as RenderBox).globalToLocal(details.localFocalPoint);
                  Offset delta = ((localTouchPosition - Offset(MediaQuery.of(topContext).size.width, MediaQuery.of(topContext).size.height) * 0.5) - startPoint) / _fractalGenerator.zoom * 3.5;
                  if ((startOffsetX - delta.dx) < 5) {
                    if ((startOffsetX - delta.dx) > -5) {
                      _fractalGenerator.offsetX = (startOffsetX - delta.dx);
                    } else {
                      _fractalGenerator.offsetX = -5;
                    }
                  } else {
                    _fractalGenerator.offsetX = 5;
                  }
                  if ((startOffsetY - delta.dy) > -5) {
                    if ((startOffsetY - delta.dy) < 5) {
                      _fractalGenerator.offsetY = (startOffsetY - delta.dy);
                    } else {
                      _fractalGenerator.offsetY = 5;
                    }
                  } else {
                    _fractalGenerator.offsetY = -5;
                  }
                },
                onScaleEnd: (details) {
                  _fractalGenerator.paused = true;
                },
                child: Container(
                  width: MediaQuery.of(topContext).size.width,
                  height: MediaQuery.of(topContext).size.height,
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fractalGenerator.dispose();
    super.dispose();
  }
}

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(),
    darkTheme: ThemeData.dark(), // standard dark theme
    themeMode: ThemeMode.system,
    home: const FractalWidget(),
  ));
}
class mainSettings extends StatefulWidget {
  final FractalGenerator fractalGenerator;
  const mainSettings({super.key, required this.fractalGenerator});

  @override
  _mainSettingsState createState() => _mainSettingsState();
}

class _mainSettingsState extends State<mainSettings> {
  late FractalGenerator _fractalGenerator ;
  @override
  void initState() {
    super.initState();
    _fractalGenerator = widget.fractalGenerator;
    // _fractalGenerator.startReceivingFrames();
  }

  String formatDouble(String stringValue) {
    int lastZero = 0;
    int dotIndex = stringValue.indexOf('.') + 1;
    if (double.parse(stringValue) >= 1) {
      return (double.parse(stringValue).toInt().toString());
    }
    if (double.parse(stringValue) >= 0.1) {
      return (stringValue.substring(0, 3));
    }
    for (int i = dotIndex; i < stringValue.length; i++) {
      if (stringValue[i] == "0") {
        lastZero = i;
      } else {
        break;
      }
    }

    return stringValue.substring(0, dotIndex + lastZero);
  }

  static final _defaultLightColorScheme =
  ColorScheme.fromSwatch(primarySwatch: Colors.teal);

  static final _defaultDarkColorScheme = ColorScheme.fromSwatch(
      primarySwatch: Colors.teal, brightness: Brightness.dark);
  final MaterialStateProperty<Icon?> thumbIcon =
  MaterialStateProperty.resolveWith<Icon?>(
        (Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return const Icon(Icons.check);
      }
      return const Icon(Icons.close);
    },
  );

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
          theme: ThemeData(
            colorScheme: lightColorScheme ?? _defaultLightColorScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          home: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30.0),
                topRight: Radius.circular(30.0),
              ),
              child: Scaffold(
                appBar: AppBar(
                  title: const Text(
                    "Settings",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18
                    ),
                  ),
                  centerTitle: true,
                ),
                body: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: SegmentedButton<String>(
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(
                              value: "Mandelbrot",
                              label: Text('Mandelbrot'),
                              icon: Icon(Icons.schema_rounded)),
                          ButtonSegment<String>(
                              value: "Sierpinski",
                              label: Text('Sierpinski'),
                              icon: Icon(Icons.square_foot_rounded)),
                        ],
                        selected: <String>{_fractalGenerator.currentFractal},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _fractalGenerator.currentFractal = newSelection.first;
                          });
                        },
                      ),
                    ),
                    Card(
                      elevation: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(15),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Use system colors",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18
                                      ),
                                    ),
                                    Text(
                                      "Fractal will match your system colors",
                                    ),
                                  ],
                                ),
                                Switch(
                                  thumbIcon: thumbIcon,
                                  value: _fractalGenerator.useSysColor,
                                  onChanged: (bool value) {
                                    setState(() {
                                      _fractalGenerator.R = Theme.of(context).colorScheme.primary.red ~/ 25.5;
                                      _fractalGenerator.G = Theme.of(context).colorScheme.primary.green ~/ 25.5;
                                      _fractalGenerator.B = Theme.of(context).colorScheme.primary.blue ~/ 25.5;
                                      _fractalGenerator.useSysColor = value;
                                    });
                                  },
                                )
                              ],
                            ),
                          ),
                          !_fractalGenerator.useSysColor ? Slider(
                            value: _fractalGenerator.R.toDouble(),
                            activeColor: Colors.red,
                            max: 10,
                            divisions: 10,
                            label: "Red: ${_fractalGenerator.R * 10}%",
                            onChanged: (double value) {
                              setState(() {
                                _fractalGenerator.R = value.toInt();
                              });
                            },
                          ) : Container(),
                          !_fractalGenerator.useSysColor ? Slider(
                            value: _fractalGenerator.G.toDouble(),
                            activeColor: Colors.green,
                            max: 10,
                            divisions: 10,
                            label: "Green: ${_fractalGenerator.G * 10}%",
                            onChanged: (double value) {
                              setState(() {
                                _fractalGenerator.G = value.toInt();
                              });
                            },
                          ) : Container(),
                          !_fractalGenerator.useSysColor ? Slider(
                            value: _fractalGenerator.B.toDouble(),
                            activeColor: Colors.blue,
                            max: 10,
                            divisions: 10,
                            label: "Blue: ${_fractalGenerator.B * 10}%",
                            onChanged: (double value) {
                              setState(() {
                                _fractalGenerator.B = value.toInt();
                              });
                            },
                          ) : Container(),
                        ],
                      ),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Telemetry",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18
                                  ),
                                ),
                                Text(
                                  "Display info above the fractal",
                                )
                              ],
                            ),
                            Switch(
                              thumbIcon: thumbIcon,
                              value: _fractalGenerator.showTelemetry,
                              onChanged: (bool value) {
                                setState(() {
                                  _fractalGenerator.showTelemetry = value;
                                });
                              },
                            )
                          ],
                        ),
                      ),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fractalGenerator.resolutionScale == 1 ? "Render time" : "Rendering speed",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text((_fractalGenerator.resolutionScale == 1) ? "${_fractalGenerator.lastTime}ms" : "${(100 / _fractalGenerator.lastTime).toStringAsFixed(0)}fps"),
                            ],
                          )),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Zoom level",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text("${_fractalGenerator.zoom.toInt()} (${((100 / 5000000000000000000) * _fractalGenerator.zoom) >= 0 ? formatDouble(((100 / 5000000000000000000) * _fractalGenerator.zoom).toStringAsFixed(20)) : ((100 / 5000000000000000000) * _fractalGenerator.zoom).toInt()}%)"),
                            ],
                          )),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "X Offset",
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(_fractalGenerator.offsetX.toStringAsFixed(17)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Y Offset",
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(_fractalGenerator.offsetY.toStringAsFixed(17)),
                                ],
                              )
                            ],
                          )
                      ),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Reset position",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18
                                  ),
                                ),
                                Text(
                                  "Go back to the initial fractal view",
                                )
                              ],
                            ),
                            FilledButton(
                                onPressed: (){
                                  _fractalGenerator.zoom = 300.0;
                                  _fractalGenerator.offsetX = 0;
                                  _fractalGenerator.offsetY = 0;
                                  _fractalGenerator.skipGen = 3;
                                  Navigator.pop(context);
                                },
                                child: const Text('Reset')
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
      );
    });
  }
}
