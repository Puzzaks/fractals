import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

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
    super.initState();
    _fractalGenerator = FractalGenerator();
    _fractalGenerator.startReceivingFrames();
  }

  String formatDouble(String stringValue) {
    int lastZero = 0;
    int dotIndex = stringValue.indexOf('.') + 1;
    if(double.parse(stringValue) >= 1){
      return(double.parse(stringValue).toInt().toString());
    }
    if(double.parse(stringValue) >= 0.1){
      return(stringValue.substring(0, 3));
    }
    for(int i=dotIndex; i<stringValue.length;i++){
      if(stringValue[i] == "0"){
        lastZero = i;
      }else{
        break;
      }
    }

    return stringValue.substring(0, dotIndex + lastZero);
  }

  @override
  Widget build(BuildContext topContext) {
    _fractalGenerator.canvasHeight = View.of(topContext).physicalSize.height.toInt();
    _fractalGenerator.canvasWidth = View.of(topContext).physicalSize.width.toInt();
    double startOffsetX = _fractalGenerator.offsetX;
    double startOffsetY = _fractalGenerator.offsetY;
    Offset startPoint = Offset.zero;
    double startResScale = 0.0;
    return Scaffold(
      body: Stack(
        children: [
          StreamBuilder<Uint8List>(
            stream: _fractalGenerator.imageStream,
            builder: (context, snapshot) {
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(15)),
                            child: Container(
                              color: Colors.teal,
                              height: 110 ,
                              child: Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text("Zoomed at: ${_fractalGenerator.zoom.toInt()} (${
                                                ((100 / 5000000000000000000) * _fractalGenerator.zoom) >= 0
                                                    ? formatDouble(((100 / 5000000000000000000) * _fractalGenerator.zoom).toStringAsFixed(20))
                                                  : ((100 / 5000000000000000000) * _fractalGenerator.zoom).toInt()}%)"),
                                            Text("Offset X: ${_fractalGenerator.offsetX.toStringAsFixed(17)}\nOffset Y: ${_fractalGenerator.offsetY.toStringAsFixed(17)}"),
                                            Text("Iterations:  ${_fractalGenerator.maxIterations}"),
                                            Text((_fractalGenerator.resolutionScale == 1) ? "Rendered in ${_fractalGenerator.lastTime}ms" : "Rendering, ${(100/_fractalGenerator.lastTime).toStringAsFixed(0)}fps"),
                                          ],
                                        ),
                                        Icon(
                                            (_fractalGenerator.resolutionScale == 1 && _fractalGenerator.skipGen == 0)
                                                ? Icons.done_rounded
                                                : Icons.access_time_rounded,
                                          size: 42,
                                        ),
                                  ])),
                            ),
                          ),
                        )
                      ],
                    )
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
                    if((_fractalGenerator.zoom < 5000000000000000000)){
                      _fractalGenerator.zoom += (0.01 * _fractalGenerator.zoom) / details.scale;
                    }else{
                      _fractalGenerator.zoom = 5000000000000000000;
                    }
                  }
                }
                startResScale = details.scale;
              }
              var localTouchPosition = (topContext.findRenderObject() as RenderBox).globalToLocal(details.localFocalPoint);
              Offset delta = ((localTouchPosition - Offset(MediaQuery.of(topContext).size.width, MediaQuery.of(topContext).size.height) * 0.5) - startPoint) / _fractalGenerator.zoom * 3.5;
              if((startOffsetX - delta.dx) < 5){
                _fractalGenerator.offsetX = (startOffsetX - delta.dx);
              }else{
                _fractalGenerator.offsetX = 5;
              }
              if((startOffsetX - delta.dx) < -5){
                _fractalGenerator.offsetX = (startOffsetX - delta.dx);
              }else{
                _fractalGenerator.offsetX = -5;
              }
              if((startOffsetY - delta.dy) < 5 && (startOffsetY - delta.dy) > -5){
                _fractalGenerator.offsetY = (startOffsetY - delta.dy);
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
    );
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
    home: const FractalWidget(),
  ));
}
